package llmlog

import (
	"bytes"
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
	if !t.log.Core().Enabled(zap.DebugLevel) {
		return t.base.RoundTrip(req)
	}

	// Log request
	reqBody := readAndRestore(&req.Body)
	t.log.Debug("llm http request",
		zap.String("method", req.Method),
		zap.String("url", req.URL.String()),
		zap.Any("headers", redactHeaders(req.Header)),
		zap.String("body", reqBody),
	)

	resp, err := t.base.RoundTrip(req)
	if err != nil {
		return nil, err
	}

	// Log response — redact response headers the same way as request headers.
	respBody := readAndRestore(&resp.Body)
	t.log.Debug("llm http response",
		zap.Int("status", resp.StatusCode),
		zap.Any("headers", redactHeaders(resp.Header)),
		zap.String("body", respBody),
	)

	return resp, nil
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
