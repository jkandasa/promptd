package scheduler

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/robfig/cron/v3"
	"go.uber.org/zap"
)

// Scheduler fires scheduled prompt executions via cron or one-time timers.
type Scheduler struct {
	store         *Store
	runner        *Runner
	systemPrompts map[string]string // prompt name → content
	log           *zap.Logger
	cron          *cron.Cron
	mu            sync.Mutex
	entries       map[string]cron.EntryID // scheduleID → cron entry
	timers        map[string]*time.Timer  // scheduleID → one-time timer
	running       map[string]bool         // scheduleID → active execution guard
	ctx           context.Context         // app-lifetime context for all executions
}

// New creates a Scheduler. Call Start to load existing schedules and begin ticking.
func New(store *Store, runner *Runner, systemPrompts map[string]string, log *zap.Logger) *Scheduler {
	return &Scheduler{
		store:         store,
		runner:        runner,
		systemPrompts: systemPrompts,
		log:           log,
		cron:          cron.New(cron.WithSeconds()),
		entries:       make(map[string]cron.EntryID),
		timers:        make(map[string]*time.Timer),
		running:       make(map[string]bool),
	}
}

// Store returns the underlying Store (used by the HTTP handler for direct reads).
func (s *Scheduler) Store() *Store { return s.store }

// Start loads all enabled schedules and begins the cron ticker.
func (s *Scheduler) Start(ctx context.Context) error {
	s.ctx = ctx
	schedules, err := s.store.ListSchedules()
	if err != nil {
		return fmt.Errorf("load schedules on start: %w", err)
	}
	var loaded int
	for _, sc := range schedules {
		if !sc.Enabled {
			continue
		}
		if err := s.schedule(sc); err != nil {
			s.log.Warn("failed to schedule on startup",
				zap.String("id", sc.ID), zap.String("name", sc.Name), zap.Error(err))
			continue
		}
		loaded++
	}
	s.cron.Start()
	s.log.Info("scheduler started", zap.Int("active", loaded), zap.Int("total", len(schedules)))
	return nil
}

// Stop cancels all pending jobs.
func (s *Scheduler) Stop() {
	s.cron.Stop()
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, t := range s.timers {
		t.Stop()
	}
	s.log.Info("scheduler stopped")
}

// Add creates a new schedule, persists it, and activates it if enabled.
func (s *Scheduler) Add(ctx context.Context, sc *Schedule) error {
	now := time.Now()
	sc.ID = uuid.New().String()
	sc.CreatedAt = now
	sc.UpdatedAt = now

	if err := s.computeNextRun(sc); err != nil {
		return err
	}
	if err := s.store.SaveSchedule(sc); err != nil {
		return err
	}
	if sc.Enabled {
		return s.schedule(sc)
	}
	return nil
}

// Update saves changes to an existing schedule and re-registers it.
func (s *Scheduler) Update(ctx context.Context, sc *Schedule) error {
	// Load to preserve CreatedAt.
	existing, err := s.store.LoadSchedule(sc.ID)
	if err != nil {
		return err
	}
	sc.CreatedAt = existing.CreatedAt
	sc.UpdatedAt = time.Now()

	if err := s.computeNextRun(sc); err != nil {
		return err
	}
	s.unschedule(sc.ID)
	if err := s.store.SaveSchedule(sc); err != nil {
		return err
	}
	if sc.Enabled {
		return s.schedule(sc)
	}
	return nil
}

// Remove deletes a schedule and cancels any pending job.
func (s *Scheduler) Remove(id string) error {
	s.unschedule(id)
	return s.store.DeleteSchedule(id)
}

// Trigger runs a schedule immediately in the background (non-blocking).
// Uses s.ctx (app-lifetime) so the execution is not tied to the HTTP request.
func (s *Scheduler) Trigger(ctx context.Context, id string) error {
	if _, err := s.store.LoadSchedule(id); err != nil {
		return err
	}
	go s.execute(s.ctx, id, true)
	return nil
}

// schedule registers a job with the cron engine or a one-time timer.
// It always uses s.ctx (the app-lifetime context) so that closures are never
// tied to a short-lived HTTP request context.
func (s *Scheduler) schedule(sc *Schedule) error {
	switch sc.Type {
	case ScheduleTypeCron:
		entryID, err := s.cron.AddFunc(sc.CronExpr, func() {
			s.execute(s.ctx, sc.ID, false)
		})
		if err != nil {
			return fmt.Errorf("invalid cron expression %q: %w", sc.CronExpr, err)
		}
		s.mu.Lock()
		s.entries[sc.ID] = entryID
		s.mu.Unlock()

	case ScheduleTypeOnce:
		if sc.RunAt == nil {
			return fmt.Errorf("run_at is required for once schedule")
		}
		delay := time.Until(*sc.RunAt)
		if delay <= 0 {
			return nil // already past — skip silently
		}
		t := time.AfterFunc(delay, func() {
			s.execute(s.ctx, sc.ID, false)
		})
		s.mu.Lock()
		s.timers[sc.ID] = t
		s.mu.Unlock()
	}
	return nil
}

// unschedule cancels any registered job for the given schedule ID.
func (s *Scheduler) unschedule(id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if eid, ok := s.entries[id]; ok {
		s.cron.Remove(eid)
		delete(s.entries, id)
	}
	if t, ok := s.timers[id]; ok {
		t.Stop()
		delete(s.timers, id)
	}
}

// execute runs a single schedule. It is concurrency-safe: concurrent invocations
// for the same schedule are skipped (the previous run takes precedence).
// Manual triggers bypass the Enabled guard so "Run now" works for disabled schedules.
func (s *Scheduler) execute(ctx context.Context, scheduleID string, manual bool) {
	// Guard against concurrent runs of the same schedule.
	s.mu.Lock()
	if s.running[scheduleID] {
		s.mu.Unlock()
		s.log.Info("skipping execution — previous run still active", zap.String("id", scheduleID))
		return
	}
	s.running[scheduleID] = true
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(s.running, scheduleID)
		s.mu.Unlock()
	}()

	sc, err := s.store.LoadSchedule(scheduleID)
	if err != nil {
		s.log.Error("execute: load schedule failed", zap.String("id", scheduleID), zap.Error(err))
		return
	}
	if !manual && !sc.Enabled {
		return
	}

	exec := &Execution{
		ID:          uuid.New().String(),
		ScheduleID:  scheduleID,
		TriggeredAt: time.Now(),
		Status:      ExecutionStatusRunning,
	}

	var systemPromptText string
	if sc.SystemPrompt != "" {
		systemPromptText = s.systemPrompts[sc.SystemPrompt]
	}

	s.log.Info("executing schedule", zap.String("id", scheduleID), zap.String("name", sc.Name))

	runCtx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()

	start := time.Now()
	result, runErr := s.runner.Run(runCtx, RunConfig{
		Prompt:       sc.Prompt,
		ModelID:      sc.ModelID,
		Provider:     sc.Provider,
		SystemPrompt: systemPromptText,
		AllowedTools: sc.AllowedTools,
		Params:       sc.Params,
		TraceEnabled: sc.TraceEnabled,
	})
	durationMs := time.Since(start).Milliseconds()

	now := time.Now()
	exec.CompletedAt = &now
	exec.DurationMs = durationMs

	if runErr != nil {
		exec.Status = ExecutionStatusError
		exec.Error = runErr.Error()
		s.log.Error("schedule execution failed",
			zap.String("id", scheduleID), zap.String("name", sc.Name), zap.Error(runErr))
	} else {
		exec.Status = ExecutionStatusSuccess
		exec.Response = result.Response
		exec.ModelUsed = result.ModelUsed
		exec.ProviderUsed = result.ProviderUsed
		exec.LLMCalls = result.LLMCalls
		exec.ToolCalls = result.ToolCalls
		exec.Trace = result.Trace
		s.log.Info("schedule executed",
			zap.String("id", scheduleID), zap.String("name", sc.Name),
			zap.Int64("duration_ms", durationMs), zap.String("model", result.ModelUsed))
	}

	if err := s.store.SaveExecution(exec, sc.RetainHistory); err != nil {
		s.log.Error("failed to save execution", zap.String("schedule_id", scheduleID), zap.Error(err))
	}

	// Update last/next run on the schedule record.
	triggered := exec.TriggeredAt
	sc.LastRunAt = &triggered
	if sc.Type == ScheduleTypeOnce {
		sc.Enabled = false
		sc.NextRunAt = nil
		s.unschedule(scheduleID)
	} else if sc.Type == ScheduleTypeCron && sc.CronExpr != "" {
		if next, err := nextCronTime(sc.CronExpr); err == nil {
			sc.NextRunAt = &next
		}
	}
	if err := s.store.SaveSchedule(sc); err != nil {
		s.log.Error("failed to update schedule post-execution", zap.String("id", scheduleID), zap.Error(err))
	}
}

// computeNextRun sets sc.NextRunAt based on the schedule type; validates cron expressions.
func (s *Scheduler) computeNextRun(sc *Schedule) error {
	switch sc.Type {
	case ScheduleTypeCron:
		if sc.CronExpr == "" {
			return fmt.Errorf("cron_expr is required for cron schedule")
		}
		next, err := nextCronTime(sc.CronExpr)
		if err != nil {
			return fmt.Errorf("invalid cron expression: %w", err)
		}
		sc.NextRunAt = &next
	case ScheduleTypeOnce:
		if sc.RunAt == nil {
			return fmt.Errorf("run_at is required for once schedule")
		}
		sc.NextRunAt = sc.RunAt
	default:
		return fmt.Errorf("unknown schedule type %q", sc.Type)
	}
	return nil
}

// nextCronTime parses a 6-field cron expression (with seconds) and returns the
// next scheduled time after now.
func nextCronTime(expr string) (time.Time, error) {
	parser := cron.NewParser(cron.Second | cron.Minute | cron.Hour | cron.Dom | cron.Month | cron.Dow)
	sched, err := parser.Parse(expr)
	if err != nil {
		return time.Time{}, err
	}
	return sched.Next(time.Now()), nil
}
