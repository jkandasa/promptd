package llmlog

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"

	"go.uber.org/zap"
)

// maxLogBodyBytes caps the body size buffered for logging to avoid large memory allocations.
const maxLogBodyBytes = 1 << 20 // 1 MiB

// Transport is an http.RoundTripper that logs LLM request and response details at debug level.
type Transport struct {
	base http.RoundTripper
	log  *zap.Logger
}

func NewTransport(base http.RoundTripper, log *zap.Logger) *Transport {
	if base == nil {
		base = http.DefaultTransport
	}
	return &Transport{base: base, log: log}
}

func (t *Transport) RoundTrip(req *http.Request) (*http.Response, error) {
	debug := t.log.Core().Enabled(zap.DebugLevel)

	if debug {
		reqBody := readAndRestore(&req.Body)
		t.log.Debug("llm http request",
			zap.String("method", req.Method),
			zap.String("url", req.URL.String()),
			zap.Any("headers", redactHeaders(req.Header)),
			zap.String("body", reqBody),
		)
	}

	resp, err := t.base.RoundTrip(req)
	if err != nil {
		return nil, err
	}

	// Always patch: copy OpenRouter's non-standard "reasoning" field into
	// "reasoning_content" so the go-openai SDK unmarshals it correctly.
	patchReasoningField(&resp.Body)

	if debug {
		respBody := readAndRestore(&resp.Body)
		t.log.Debug("llm http response",
			zap.Int("status", resp.StatusCode),
			zap.Any("headers", redactHeaders(resp.Header)),
			zap.String("body", respBody),
		)
	}

	return resp, nil
}

// patchReasoningField reads the response body, and for every choice whose
// message has a non-empty "reasoning" field but no "reasoning_content", copies
// the value across so the go-openai SDK can unmarshal it. The body is always
// restored so downstream readers are unaffected.
func patchReasoningField(body *io.ReadCloser) {
	if *body == nil {
		return
	}
	data, err := io.ReadAll(io.LimitReader(*body, maxLogBodyBytes))
	(*body).Close()
	if err != nil || len(data) == 0 {
		*body = io.NopCloser(bytes.NewReader(data))
		return
	}

	patched := applyReasoningPatch(data)
	*body = io.NopCloser(bytes.NewReader(patched))
}

// applyReasoningPatch does the actual JSON manipulation. It is a separate
// function so it can be unit-tested without an http.Response.
func applyReasoningPatch(data []byte) []byte {
	var root map[string]json.RawMessage
	if err := json.Unmarshal(data, &root); err != nil {
		return data
	}

	choicesRaw, ok := root["choices"]
	if !ok {
		return data
	}

	var choices []map[string]json.RawMessage
	if err := json.Unmarshal(choicesRaw, &choices); err != nil {
		return data
	}

	modified := false
	for i, choice := range choices {
		msgRaw, ok := choice["message"]
		if !ok {
			continue
		}
		var msg map[string]json.RawMessage
		if err := json.Unmarshal(msgRaw, &msg); err != nil {
			continue
		}

		reasoningRaw, hasReasoning := msg["reasoning"]
		_, hasReasoningContent := msg["reasoning_content"]

		// Only patch when "reasoning" is present and "reasoning_content" is
		// absent or null/empty.
		if !hasReasoning {
			continue
		}
		var reasoningStr string
		if err := json.Unmarshal(reasoningRaw, &reasoningStr); err != nil || reasoningStr == "" {
			continue
		}
		if hasReasoningContent {
			var existing string
			if err := json.Unmarshal(msg["reasoning_content"], &existing); err == nil && existing != "" {
				continue // already populated, nothing to do
			}
		}

		msg["reasoning_content"] = reasoningRaw
		newMsgRaw, err := json.Marshal(msg)
		if err != nil {
			continue
		}
		choice["message"] = newMsgRaw
		choices[i] = choice
		modified = true
	}

	if !modified {
		return data
	}

	newChoicesRaw, err := json.Marshal(choices)
	if err != nil {
		return data
	}
	root["choices"] = newChoicesRaw
	out, err := json.Marshal(root)
	if err != nil {
		return data
	}
	return out
}

// readAndRestore reads up to maxLogBodyBytes from the body, then replaces it with
// a fresh reader that yields the full original content so callers are unaffected.
func readAndRestore(body *io.ReadCloser) string {
	if *body == nil {
		return ""
	}
	data, _ := io.ReadAll(io.LimitReader(*body, maxLogBodyBytes))
	(*body).Close()
	*body = io.NopCloser(bytes.NewReader(data))
	return string(data)
}

// redactHeaders returns a copy of the headers with sensitive values masked.
func redactHeaders(h http.Header) http.Header {
	out := h.Clone()
	if out.Get("Authorization") != "" {
		out.Set("Authorization", "Bearer ****")
	}
	if out.Get("Set-Cookie") != "" {
		out.Set("Set-Cookie", "****")
	}
	return out
}
