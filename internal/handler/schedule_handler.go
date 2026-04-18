package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"promptd/internal/scheduler"

	"go.uber.org/zap"
)

// ScheduleHandler exposes CRUD + trigger/execution-history endpoints for schedules.
type ScheduleHandler struct {
	sched *scheduler.Scheduler
	log   *zap.Logger
}

// NewScheduleHandler creates a ScheduleHandler.
func NewScheduleHandler(sched *scheduler.Scheduler, log *zap.Logger) *ScheduleHandler {
	return &ScheduleHandler{sched: sched, log: log}
}

// List returns all schedules.
func (h *ScheduleHandler) List(w http.ResponseWriter, r *http.Request) {
	schedules, err := h.sched.Store().ListSchedules()
	if err != nil {
		h.log.Error("list schedules failed", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to list schedules"})
		return
	}
	if schedules == nil {
		schedules = []*scheduler.Schedule{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"schedules": schedules})
}

// Get returns a single schedule by ID.
func (h *ScheduleHandler) Get(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	sc, err := h.sched.Store().LoadSchedule(id)
	if err != nil {
		if errors.Is(err, scheduler.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "not found"})
		} else {
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to load schedule"})
		}
		return
	}
	writeJSON(w, http.StatusOK, sc)
}

// Create creates a new schedule.
func (h *ScheduleHandler) Create(w http.ResponseWriter, r *http.Request) {
	var sc scheduler.Schedule
	if err := json.NewDecoder(r.Body).Decode(&sc); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request body"})
		return
	}
	if sc.Name == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "name is required"})
		return
	}
	if sc.Prompt == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "prompt is required"})
		return
	}
	if err := h.sched.Add(r.Context(), &sc); err != nil {
		h.log.Error("create schedule failed", zap.Error(err))
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, sc)
}

// Update replaces an existing schedule.
func (h *ScheduleHandler) Update(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var sc scheduler.Schedule
	if err := json.NewDecoder(r.Body).Decode(&sc); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request body"})
		return
	}
	sc.ID = id
	if err := h.sched.Update(r.Context(), &sc); err != nil {
		if errors.Is(err, scheduler.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "not found"})
		} else {
			h.log.Error("update schedule failed", zap.Error(err))
			writeJSON(w, http.StatusBadRequest, errorResponse{Error: err.Error()})
		}
		return
	}
	writeJSON(w, http.StatusOK, sc)
}

// Delete removes a schedule.
func (h *ScheduleHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := h.sched.Remove(id); err != nil {
		if errors.Is(err, scheduler.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "not found"})
		} else {
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to delete"})
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// Trigger runs a schedule immediately (non-blocking — returns before execution completes).
func (h *ScheduleHandler) Trigger(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := h.sched.Trigger(r.Context(), id); err != nil {
		if errors.Is(err, scheduler.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "not found"})
		} else {
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		}
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]string{"status": "triggered"})
}

// ListExecutions returns the execution history for a schedule.
func (h *ScheduleHandler) ListExecutions(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	execs, err := h.sched.Store().ListExecutions(id)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to list executions"})
		return
	}
	if execs == nil {
		execs = []*scheduler.Execution{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"executions": execs})
}

// DeleteExecution removes a single execution record.
func (h *ScheduleHandler) DeleteExecution(w http.ResponseWriter, r *http.Request) {
	schedID := r.PathValue("id")
	execID := r.PathValue("execId")
	if err := h.sched.Store().DeleteExecution(schedID, execID); err != nil {
		if errors.Is(err, scheduler.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "not found"})
		} else {
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to delete execution"})
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
