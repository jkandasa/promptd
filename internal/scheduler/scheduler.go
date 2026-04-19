package scheduler

import (
	"context"
	"fmt"
	"sync"
	"time"

	"promptd/internal/auth"
	"promptd/internal/storage"

	"github.com/google/uuid"
	"github.com/robfig/cron/v3"
	"go.uber.org/zap"
)

type Scheduler struct {
	store         *Store
	runner        *Runner
	authService   *auth.Service
	systemPrompts map[string]string
	log           *zap.Logger
	cron          *cron.Cron
	mu            sync.Mutex
	entries       map[string]cron.EntryID
	timers        map[string]*time.Timer
	running       map[string]bool
	ctx           context.Context
}

func New(store *Store, runner *Runner, authService *auth.Service, systemPrompts map[string]string, log *zap.Logger) *Scheduler {
	return &Scheduler{
		store:         store,
		runner:        runner,
		authService:   authService,
		systemPrompts: systemPrompts,
		log:           log,
		cron:          cron.New(cron.WithSeconds()),
		entries:       make(map[string]cron.EntryID),
		timers:        make(map[string]*time.Timer),
		running:       make(map[string]bool),
	}
}

func (s *Scheduler) Store() *Store { return s.store }

func scheduleKey(scope storage.Scope, id string) string { return scope.Key() + ":" + id }

func (s *Scheduler) Start(ctx context.Context) error {
	s.ctx = ctx
	schedules, err := s.store.ListAllSchedules()
	if err != nil {
		return fmt.Errorf("load schedules on start: %w", err)
	}
	var loaded int
	for _, sc := range schedules {
		if !sc.Enabled {
			continue
		}
		if err := s.schedule(sc); err != nil {
			s.log.Warn("failed to schedule on startup", zap.String("id", sc.ID), zap.String("name", sc.Name), zap.Error(err))
			continue
		}
		loaded++
	}
	s.cron.Start()
	s.log.Info("scheduler started", zap.Int("active", loaded), zap.Int("total", len(schedules)))
	return nil
}

func (s *Scheduler) Stop() {
	s.cron.Stop()
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, t := range s.timers {
		t.Stop()
	}
	s.log.Info("scheduler stopped")
}

func (s *Scheduler) validateSchedule(scope storage.Scope, sc *Schedule) error {
	principal, err := s.authService.BuildPrincipalByScope(auth.ResourceScope{TenantID: scope.TenantID, UserID: scope.UserID})
	if err != nil {
		return err
	}
	if !principal.Policy.Permissions.SchedulesWrite {
		return fmt.Errorf("schedule write not allowed")
	}
	if sc.SystemPrompt != "" && !principal.Policy.AllowPrompt(sc.SystemPrompt) {
		return fmt.Errorf("system prompt %q is not allowed", sc.SystemPrompt)
	}
	if sc.ModelID != "" && sc.Provider != "" && !principal.Policy.AllowModel(sc.Provider, sc.ModelID) {
		return fmt.Errorf("model %q is not allowed", sc.ModelID)
	}
	for _, tool := range sc.AllowedTools {
		if !principal.Policy.AllowTool(tool) {
			return fmt.Errorf("tool %q is not allowed", tool)
		}
	}
	return nil
}

func (s *Scheduler) Add(ctx context.Context, scope storage.Scope, sc *Schedule) error {
	now := time.Now()
	sc.ID = uuid.New().String()
	sc.CreatedAt = now
	sc.UpdatedAt = now
	sc.TenantID = scope.TenantID
	sc.UserID = scope.UserID
	if err := s.validateSchedule(scope, sc); err != nil {
		return err
	}
	if err := s.computeNextRun(sc); err != nil {
		return err
	}
	if err := s.store.SaveSchedule(scope, sc); err != nil {
		return err
	}
	if sc.Enabled {
		return s.schedule(sc)
	}
	return nil
}

func (s *Scheduler) Update(ctx context.Context, scope storage.Scope, sc *Schedule) error {
	existing, err := s.store.LoadSchedule(scope, sc.ID)
	if err != nil {
		return err
	}
	sc.CreatedAt = existing.CreatedAt
	sc.UpdatedAt = time.Now()
	sc.TenantID = scope.TenantID
	sc.UserID = scope.UserID
	if err := s.validateSchedule(scope, sc); err != nil {
		return err
	}
	if err := s.computeNextRun(sc); err != nil {
		return err
	}
	s.unschedule(scope, sc.ID)
	if err := s.store.SaveSchedule(scope, sc); err != nil {
		return err
	}
	if sc.Enabled {
		return s.schedule(sc)
	}
	return nil
}

func (s *Scheduler) Remove(scope storage.Scope, id string) error {
	s.unschedule(scope, id)
	return s.store.DeleteSchedule(scope, id)
}

func (s *Scheduler) Trigger(ctx context.Context, scope storage.Scope, id string) error {
	if _, err := s.store.LoadSchedule(scope, id); err != nil {
		return err
	}
	go s.execute(s.ctx, scope, id, true)
	return nil
}

func (s *Scheduler) schedule(sc *Schedule) error {
	scope := storage.Scope{TenantID: sc.TenantID, UserID: sc.UserID}
	key := scheduleKey(scope, sc.ID)
	switch sc.Type {
	case ScheduleTypeCron:
		entryID, err := s.cron.AddFunc(sc.CronExpr, func() {
			s.execute(s.ctx, scope, sc.ID, false)
		})
		if err != nil {
			return fmt.Errorf("invalid cron expression %q: %w", sc.CronExpr, err)
		}
		s.mu.Lock()
		s.entries[key] = entryID
		s.mu.Unlock()
	case ScheduleTypeOnce:
		if sc.RunAt == nil {
			return fmt.Errorf("run_at is required for once schedule")
		}
		delay := time.Until(*sc.RunAt)
		if delay <= 0 {
			return nil
		}
		t := time.AfterFunc(delay, func() {
			s.execute(s.ctx, scope, sc.ID, false)
		})
		s.mu.Lock()
		s.timers[key] = t
		s.mu.Unlock()
	}
	return nil
}

func (s *Scheduler) unschedule(scope storage.Scope, id string) {
	key := scheduleKey(scope, id)
	s.mu.Lock()
	defer s.mu.Unlock()
	if eid, ok := s.entries[key]; ok {
		s.cron.Remove(eid)
		delete(s.entries, key)
	}
	if t, ok := s.timers[key]; ok {
		t.Stop()
		delete(s.timers, key)
	}
}

func (s *Scheduler) execute(ctx context.Context, scope storage.Scope, scheduleID string, manual bool) {
	key := scheduleKey(scope, scheduleID)
	s.mu.Lock()
	if s.running[key] {
		s.mu.Unlock()
		s.log.Info("skipping execution — previous run still active", zap.String("id", scheduleID), zap.String("scope", key))
		return
	}
	s.running[key] = true
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(s.running, key)
		s.mu.Unlock()
	}()

	sc, err := s.store.LoadSchedule(scope, scheduleID)
	if err != nil {
		s.log.Error("execute: load schedule failed", zap.String("id", scheduleID), zap.Error(err))
		return
	}
	if !manual && !sc.Enabled {
		return
	}
	principal, err := s.authService.BuildPrincipalByScope(auth.ResourceScope{TenantID: scope.TenantID, UserID: scope.UserID})
	if err != nil {
		s.log.Error("schedule principal resolve failed", zap.String("id", scheduleID), zap.Error(err))
		return
	}
	exec := &Execution{ID: uuid.New().String(), ScheduleID: scheduleID, TriggeredAt: time.Now(), Status: ExecutionStatusRunning}
	var systemPromptText string
	if sc.SystemPrompt != "" {
		if !principal.Policy.AllowPrompt(sc.SystemPrompt) {
			exec.Status = ExecutionStatusError
			exec.Error = fmt.Sprintf("system prompt %q is not allowed", sc.SystemPrompt)
			_ = s.store.SaveExecution(scope, exec, sc.RetainHistory)
			return
		}
		systemPromptText = s.systemPrompts[sc.SystemPrompt]
	}
	resolvedModel, _, resolvedProvider, _ := s.runner.resolver.ResolveModel(sc.ModelID, sc.Provider)
	if resolvedModel != "" && !principal.Policy.AllowModel(resolvedProvider, resolvedModel) {
		exec.Status = ExecutionStatusError
		exec.Error = fmt.Sprintf("model %q from provider %q is not allowed", resolvedModel, resolvedProvider)
		_ = s.store.SaveExecution(scope, exec, sc.RetainHistory)
		return
	}
	allowedTools := principal.Policy.FilterAllowedToolNames(sc.AllowedTools)
	if sc.AllowedTools == nil {
		allowedTools = principal.Policy.FilterAllowedToolNames(s.runner.registry.Names())
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
		AllowedTools: allowedTools,
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
		s.log.Error("schedule execution failed", zap.String("id", scheduleID), zap.String("name", sc.Name), zap.Error(runErr))
	} else {
		exec.Status = ExecutionStatusSuccess
		exec.Response = result.Response
		exec.ModelUsed = result.ModelUsed
		exec.ProviderUsed = result.ProviderUsed
		exec.LLMCalls = result.LLMCalls
		exec.ToolCalls = result.ToolCalls
		exec.Trace = result.Trace
		s.log.Info("schedule executed", zap.String("id", scheduleID), zap.String("name", sc.Name), zap.Int64("duration_ms", durationMs), zap.String("model", result.ModelUsed))
	}
	if err := s.store.SaveExecution(scope, exec, sc.RetainHistory); err != nil {
		s.log.Error("failed to save execution", zap.String("schedule_id", scheduleID), zap.Error(err))
	}
	triggered := exec.TriggeredAt
	sc.LastRunAt = &triggered
	if sc.Type == ScheduleTypeOnce {
		sc.Enabled = false
		sc.NextRunAt = nil
		s.unschedule(scope, scheduleID)
	} else if sc.Type == ScheduleTypeCron && sc.CronExpr != "" {
		if next, err := nextCronTime(sc.CronExpr); err == nil {
			sc.NextRunAt = &next
		}
	}
	if err := s.store.SaveSchedule(scope, sc); err != nil {
		s.log.Error("failed to update schedule post-execution", zap.String("id", scheduleID), zap.Error(err))
	}
}

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

func nextCronTime(expr string) (time.Time, error) {
	parser := cron.NewParser(cron.Second | cron.Minute | cron.Hour | cron.Dom | cron.Month | cron.Dow)
	sched, err := parser.Parse(expr)
	if err != nil {
		return time.Time{}, err
	}
	return sched.Next(time.Now()), nil
}
