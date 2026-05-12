package app

import (
	"net/http"
	"strings"
)

const (
	corsAllowMethods  = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
	corsAllowHeaders  = "Authorization, Content-Type"
	corsExposeHeaders = "Content-Disposition"
)

func WithCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := strings.TrimSpace(r.Header.Get("Origin"))
		if origin == "" {
			next.ServeHTTP(w, r)
			return
		}

		headers := w.Header()
		headers.Set("Access-Control-Allow-Origin", origin)
		headers.Set("Access-Control-Allow-Credentials", "true")
		headers.Set("Access-Control-Allow-Methods", corsAllowMethods)
		headers.Set("Access-Control-Expose-Headers", corsExposeHeaders)
		headers.Add("Vary", "Origin")

		requestHeaders := strings.TrimSpace(r.Header.Get("Access-Control-Request-Headers"))
		if requestHeaders == "" {
			requestHeaders = corsAllowHeaders
		}
		headers.Set("Access-Control-Allow-Headers", requestHeaders)

		if r.Method == http.MethodOptions {
			headers.Set("Access-Control-Max-Age", "600")
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}
