package scheduler

import (
	"time"

	"promptd/internal/storage"
)

// ScheduleType determines how a schedule fires.
type ScheduleType string

const (
	ScheduleTypeCron ScheduleType = "cron"
	ScheduleTypeOnce ScheduleType = "once"
)

// ExecutionStatus describes the outcome of a single run.
type ExecutionStatus string

const (
	ExecutionStatusRunning ExecutionStatus = "running"
	ExecutionStatusSuccess ExecutionStatus = "success"
	ExecutionStatusError   ExecutionStatus = "error"
)

// Schedule is the configuration for a scheduled prompt execution.
type Schedule struct {
	TenantID     string       `yaml:"tenant_id,omitempty"          json:"tenant_id,omitempty"`
	UserID       string       `yaml:"user_id,omitempty"            json:"user_id,omitempty"`
	ID           string       `yaml:"id"                       json:"id"`
	Name         string       `yaml:"name"                     json:"name"`
	Enabled      bool         `yaml:"enabled"                  json:"enabled"`
	Type         ScheduleType `yaml:"type"                     json:"type"`
	CronExpr     string       `yaml:"cron_expr,omitempty"      json:"cronExpr,omitempty"`
	RunAt        *time.Time   `yaml:"run_at,omitempty"         json:"runAt,omitempty"`
	Prompt       string       `yaml:"prompt"                   json:"prompt"`
	ModelID      string       `yaml:"model_id,omitempty"       json:"modelId,omitempty"`
	Provider     string       `yaml:"provider,omitempty"       json:"provider,omitempty"`
	SystemPrompt string       `yaml:"system_prompt,omitempty"  json:"systemPrompt,omitempty"`
	AllowedTools []string     `yaml:"allowed_tools,omitempty"  json:"allowedTools,omitempty"`
	// Params overrides LLM generation parameters for this schedule (nil = use model/global defaults).
	Params *storage.UsedParams `yaml:"params,omitempty"         json:"params,omitempty"`
	// TraceEnabled overrides the runner's global trace setting for this schedule.
	// nil = follow global default, true = always record trace, false = never record trace.
	TraceEnabled *bool `yaml:"trace_enabled,omitempty"  json:"traceEnabled,omitempty"`
	// RetainHistory is how many past executions to keep (0 = keep all).
	RetainHistory int        `yaml:"retain_history" json:"retainHistory"`
	CreatedAt     time.Time  `yaml:"created_at"     json:"createdAt"`
	UpdatedAt     time.Time  `yaml:"updated_at"     json:"updatedAt"`
	LastRunAt     *time.Time `yaml:"last_run_at,omitempty" json:"lastRunAt,omitempty"`
	NextRunAt     *time.Time `yaml:"next_run_at,omitempty" json:"nextRunAt,omitempty"`
}

// Execution holds the result of a single scheduled run.
type Execution struct {
	TenantID     string             `yaml:"tenant_id,omitempty"       json:"tenant_id,omitempty"`
	UserID       string             `yaml:"user_id,omitempty"         json:"user_id,omitempty"`
	ID           string             `yaml:"id"                       json:"id"`
	ScheduleID   string             `yaml:"schedule_id"              json:"scheduleId"`
	TriggeredAt  time.Time          `yaml:"triggered_at"             json:"triggeredAt"`
	CompletedAt  *time.Time         `yaml:"completed_at,omitempty"   json:"completedAt,omitempty"`
	Status       ExecutionStatus    `yaml:"status"                   json:"status"`
	Error        string             `yaml:"error,omitempty"          json:"error,omitempty"`
	Response     string             `yaml:"response,omitempty"       json:"response,omitempty"`
	Trace        []storage.LLMRound `yaml:"trace,omitempty"          json:"trace,omitempty"`
	ModelUsed    string             `yaml:"model_used,omitempty"     json:"modelUsed,omitempty"`
	ProviderUsed string             `yaml:"provider_used,omitempty"  json:"providerUsed,omitempty"`
	LLMCalls     int                `yaml:"llm_calls,omitempty"      json:"llmCalls,omitempty"`
	ToolCalls    int                `yaml:"tool_calls,omitempty"     json:"toolCalls,omitempty"`
	DurationMs   int64              `yaml:"duration_ms,omitempty"    json:"durationMs,omitempty"`
}
