package handler

import (
	"encoding/json"
	"net/http"

	"chatbot/internal/tools"

	"go.uber.org/zap"
)

// ToolsHandler manages dynamic tool registration/unregistration endpoints.
type ToolsHandler struct {
	registry *tools.Registry
	monitor  *tools.Monitor
	log      *zap.Logger
}

func NewToolsHandler(registry *tools.Registry, monitor *tools.Monitor, log *zap.Logger) *ToolsHandler {
	return &ToolsHandler{registry: registry, monitor: monitor, log: log}
}

type registerRequest struct {
	URL string `json:"url"`
}

type toolInfo struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

type listResponse struct {
	Tools []toolInfo `json:"tools"`
}

// Register handles POST /tools/register.
// Works for both single-tool and multi-tool servers — all tools at the URL
// are fetched via /describe and registered in one call.
func (h *ToolsHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.URL == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "url is required"})
		return
	}

	remoteTools, err := tools.NewRemoteTools(req.URL)
	if err != nil {
		h.log.Warn("tool registration failed", zap.String("url", req.URL), zap.Error(err))
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: err.Error()})
		return
	}

	registered := make([]toolInfo, 0, len(remoteTools))
	for _, t := range remoteTools {
		h.registry.Register(t)
		h.monitor.Track(t.Name(), req.URL)
		h.log.Info("tool registered dynamically",
			zap.String("name", t.Name()),
			zap.String("url", req.URL),
		)
		registered = append(registered, toolInfo{Name: t.Name(), Description: t.Description()})
	}

	writeJSON(w, http.StatusOK, listResponse{Tools: registered})
}

// Unregister handles DELETE /tools/unregister.
// Removes all tools hosted at the given URL (handles multi-tool servers).
func (h *ToolsHandler) Unregister(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.URL == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "url is required"})
		return
	}

	names := h.monitor.NamesByURL(req.URL)
	if len(names) == 0 {
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "no tools registered at that URL"})
		return
	}

	for _, name := range names {
		h.registry.Remove(name)
		h.log.Info("tool unregistered", zap.String("name", name), zap.String("url", req.URL))
	}
	h.monitor.UntrackByURL(req.URL)

	w.WriteHeader(http.StatusNoContent)
}

// List handles GET /tools — returns all currently registered tools.
func (h *ToolsHandler) List(w http.ResponseWriter, r *http.Request) {
	names := h.registry.Names()
	infos := make([]toolInfo, 0, len(names))
	for _, name := range names {
		if t, ok := h.registry.Get(name); ok {
			infos = append(infos, toolInfo{Name: t.Name(), Description: t.Description()})
		}
	}
	writeJSON(w, http.StatusOK, listResponse{Tools: infos})
}
