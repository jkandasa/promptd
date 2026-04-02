package llmlog

import (
	"bytes"
	"io"
	"net/http"

	"go.uber.org/zap"
)

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

	// Log response
	respBody := readAndRestore(&resp.Body)
	t.log.Debug("llm http response",
		zap.Int("status", resp.StatusCode),
		zap.Any("headers", resp.Header),
		zap.String("body", respBody),
	)

	return resp, nil
}

// readAndRestore reads the body, then replaces it with a fresh reader so callers are unaffected.
func readAndRestore(body *io.ReadCloser) string {
	if *body == nil {
		return ""
	}
	data, _ := io.ReadAll(*body)
	(*body).Close()
	*body = io.NopCloser(bytes.NewReader(data))
	return string(data)
}

// redactHeaders returns a copy of the headers with Authorization value masked.
func redactHeaders(h http.Header) http.Header {
	out := h.Clone()
	if out.Get("Authorization") != "" {
		out.Set("Authorization", "Bearer ****")
	}
	return out
}
