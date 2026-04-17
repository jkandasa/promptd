package handler

import (
	"net/http"

	"promptd/internal/mcp"

	"go.uber.org/zap"
)

type MCPToolsHandler struct {
	manager *mcp.Manager
	log     *zap.Logger
}

func NewMCPToolsHandler(manager *mcp.Manager, log *zap.Logger) *MCPToolsHandler {
	return &MCPToolsHandler{manager: manager, log: log}
}

type mcpServerInfo struct {
	URL   string   `json:"url"`
	Tools []string `json:"tools"`
}

type mcpListResponse struct {
	Servers []mcpServerInfo `json:"servers"`
}

func (h *MCPToolsHandler) List(w http.ResponseWriter, r *http.Request) {
	servers := h.manager.List()
	result := make([]mcpServerInfo, 0, len(servers))
	for url, tools := range servers {
		result = append(result, mcpServerInfo{URL: url, Tools: tools})
	}
	writeJSON(w, http.StatusOK, mcpListResponse{Servers: result})
}
