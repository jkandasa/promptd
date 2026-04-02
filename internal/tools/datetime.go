package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"time"
)

// DateTimeTool returns the current date and time for a given timezone.
type DateTimeTool struct{}

func (DateTimeTool) Name() string { return "get_current_datetime" }

func (DateTimeTool) Description() string {
	return "Returns the current date and time. Optionally accepts an IANA timezone name (e.g. America/New_York, Asia/Kolkata). Defaults to UTC."
}

func (DateTimeTool) Parameters() any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"timezone": map[string]any{
				"type":        "string",
				"description": "IANA timezone name, e.g. America/New_York. Defaults to UTC.",
			},
		},
		"required": []string{},
	}
}

func (DateTimeTool) Execute(_ context.Context, args json.RawMessage) (string, error) {
	var params struct {
		Timezone string `json:"timezone"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return "", fmt.Errorf("invalid arguments: %w", err)
	}

	loc := time.UTC
	if params.Timezone != "" {
		var err error
		loc, err = time.LoadLocation(params.Timezone)
		if err != nil {
			return "", fmt.Errorf("unknown timezone %q: %w", params.Timezone, err)
		}
	}

	now := time.Now().In(loc)
	return fmt.Sprintf("%s (timezone: %s)", now.Format("2006-01-02 15:04:05 MST"), loc.String()), nil
}
