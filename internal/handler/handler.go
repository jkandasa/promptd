package handler

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"math/rand"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	openai "github.com/openai/openai-go/v3"

	"promptd/internal/auth"
	"promptd/internal/chat"
	"promptd/internal/llm"
	"promptd/internal/storage"
	"promptd/internal/tools"

	"go.uber.org/zap"
)

// LLMParams holds optional generation parameters that can be set globally
// or per model in the config, and overridden per-request from the UI.
type LLMParams struct {
	Temperature *float32 `json:"temperature,omitempty" yaml:"temperature,omitempty"`
	MaxTokens   int      `json:"max_tokens,omitempty"  yaml:"max_tokens,omitempty"`
	TopP        *float32 `json:"top_p,omitempty"       yaml:"top_p,omitempty"`
	TopK        int      `json:"top_k,omitempty"       yaml:"top_k,omitempty"`
}

type ModelInfo struct {
	ID       string    `json:"id"`
	Name     string    `json:"name,omitempty"`
	Provider string    `json:"provider,omitempty"`
	Params   LLMParams `json:"params,omitempty"`
	IsManual bool      `json:"is_manual,omitempty"`
}

type ProviderFileUploadConfig struct {
	Enabled            bool
	Purpose            string
	MaxInlineTextBytes int
	PreferInlineImages bool
}

type ModelSelector struct {
	models          []ModelInfo
	selectionMethod string
	currentIndex    int
	source          string // "static" | "discovered"
	lastUpdated     time.Time
	refreshInterval time.Duration // 0 if autodiscover disabled
	mu              sync.Mutex
}

func (m *ModelSelector) selectModel(models []ModelInfo, preferredModel string) (string, string) {
	if len(models) == 0 {
		return "", ""
	}
	if preferredModel != "" {
		for _, model := range models {
			if model.ID == preferredModel {
				return model.ID, model.Name
			}
		}
	}
	switch m.selectionMethod {
	case "random":
		idx := rand.Intn(len(models))
		return models[idx].ID, models[idx].Name
	default:
		idx := m.currentIndex % len(models)
		model := models[idx]
		m.currentIndex = (m.currentIndex + 1) % len(models)
		return model.ID, model.Name
	}
}

func NewModelSelector(models []ModelInfo, selectionMethod string) *ModelSelector {
	if len(models) == 0 {
		models = []ModelInfo{{ID: "anthropic/claude-sonnet-4-6"}}
	}
	if selectionMethod == "" {
		selectionMethod = "round_robin"
	}
	return &ModelSelector{
		models:          models,
		selectionMethod: selectionMethod,
		currentIndex:    0,
		source:          "static",
		lastUpdated:     time.Now(),
	}
}

// SetRefreshInterval records the autodiscover interval so it can be surfaced to the UI.
func (m *ModelSelector) SetRefreshInterval(d time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.refreshInterval = d
}

func (m *ModelSelector) GetModel(preferredModel string) (string, string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.selectModel(m.models, preferredModel)
}

func (m *ModelSelector) GetModelFromCandidates(candidates []ModelInfo, preferredModel string) (string, string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.selectModel(candidates, preferredModel)
}

func (m *ModelSelector) GetAvailableModels() []ModelInfo {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]ModelInfo(nil), m.models...) // copy
}

func (m *ModelSelector) UpdateModels(infos []ModelInfo) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.models = infos
	m.currentIndex = 0 // reset round-robin index on update
	m.source = "discovered"
	m.lastUpdated = time.Now()
}

func (m *ModelSelector) GetSelectionMethod() string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.selectionMethod
}

// ProviderInfo summarises a configured LLM provider for the /models API response.
type ProviderInfo struct {
	Name            string `json:"name"`
	Source          string `json:"source,omitempty"`
	Count           int    `json:"count"`
	UpdatedAt       string `json:"updated_at,omitempty"`
	RefreshInterval string `json:"refresh_interval,omitempty"`
}

// ProviderEntry holds a single LLM provider's client and model list.
type ProviderEntry struct {
	Name          string
	Client        *openai.Client
	APIKey        string
	BaseURL       string
	HTTPClient    *http.Client
	ModelSelector *ModelSelector
	GlobalParams  LLMParams
	StaticModels  []ModelInfo
	AutoDiscover  bool
	FileUploads   ProviderFileUploadConfig
}

// ProviderRegistry manages multiple LLM providers and routes requests to the
// correct provider client based on model ID.
type ProviderRegistry struct {
	providers []*ProviderEntry
	byName    map[string]*ProviderEntry
	modelMap  map[string]*ProviderEntry // model ID → owning provider
	log       *zap.Logger
	mu        sync.RWMutex
}

// NewProviderRegistry creates a ProviderRegistry from a slice of entries and
// builds the initial model→provider routing table.
func NewProviderRegistry(entries []*ProviderEntry, log *zap.Logger) *ProviderRegistry {
	r := &ProviderRegistry{
		providers: entries,
		byName:    make(map[string]*ProviderEntry, len(entries)),
		modelMap:  make(map[string]*ProviderEntry),
		log:       log,
	}
	for _, e := range entries {
		r.byName[e.Name] = e
	}
	r.rebuildModelMap()
	return r
}

// rebuildModelMap rebuilds the model-ID → provider routing table.
// Must not be called while holding mu (called from NewProviderRegistry before
// the registry is shared, and from UpdateModelMap which holds mu.Lock).
func (r *ProviderRegistry) rebuildModelMap() {
	newMap := make(map[string]*ProviderEntry)
	for _, entry := range r.providers {
		for _, m := range entry.ModelSelector.GetAvailableModels() {
			if _, exists := newMap[m.ID]; !exists {
				newMap[m.ID] = entry
			}
		}
	}
	r.modelMap = newMap
}

// UpdateModelMap rebuilds the routing table — call after any model list update.
func (r *ProviderRegistry) UpdateModelMap() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.rebuildModelMap()
}

// ResolveModel returns the model ID, display name, provider name, and openai.Client to use.
// When provider is non-empty, routes to that specific provider (used by the scheduler).
func (r *ProviderRegistry) ResolveModel(preferred, provider string) (id, name, providerUsed string, client *openai.Client) {
	return r.ResolveModelWithProvider(preferred, provider)
}

// ResolveModelWithProvider is like ResolveModel but routes to a specific provider
// when provider is non-empty. This allows the same model ID to be served by
// different providers (e.g. when two providers both offer the same model).
func (r *ProviderRegistry) ResolveModelWithProvider(preferred, provider string) (id, name, providerUsed string, client *openai.Client) {
	if provider != "" {
		r.mu.RLock()
		entry, ok := r.byName[provider]
		r.mu.RUnlock()
		if ok {
			id, name = entry.ModelSelector.GetModel(preferred)
			return id, name, entry.Name, entry.Client
		}
	}
	if preferred != "" {
		r.mu.RLock()
		entry, ok := r.modelMap[preferred]
		r.mu.RUnlock()
		if ok {
			id, name = entry.ModelSelector.GetModel(preferred)
			return id, name, entry.Name, entry.Client
		}
	}
	r.mu.RLock()
	var entry *ProviderEntry
	if len(r.providers) > 0 {
		entry = r.providers[0]
	}
	r.mu.RUnlock()
	if entry != nil {
		id, name = entry.ModelSelector.GetModel("")
		return id, name, entry.Name, entry.Client
	}
	return "", "", "", nil
}

// GetModelParams returns the effective LLM params for the given model ID,
// optionally scoped to a specific provider.
func (r *ProviderRegistry) GetModelParams(modelID string) LLMParams {
	return r.GetModelParamsForProvider(modelID, "")
}

// GetModelParamsForProvider looks up model params within a specific provider first,
// then falls back to the default modelMap lookup.
func (r *ProviderRegistry) GetModelParamsForProvider(modelID, provider string) LLMParams {
	var entry *ProviderEntry
	if provider != "" {
		r.mu.RLock()
		e, ok := r.byName[provider]
		r.mu.RUnlock()
		if ok {
			entry = e
		}
	}
	if entry == nil {
		r.mu.RLock()
		e, ok := r.modelMap[modelID]
		r.mu.RUnlock()
		if !ok {
			return LLMParams{}
		}
		entry = e
	}
	for _, m := range entry.ModelSelector.GetAvailableModels() {
		if m.ID == modelID {
			return m.Params
		}
	}
	return entry.GlobalParams
}

// AllModels returns a flat list of all models across all providers, tagged with
// their provider name.
func (r *ProviderRegistry) AllModels() []ModelInfo {
	r.mu.RLock()
	entries := make([]*ProviderEntry, len(r.providers))
	copy(entries, r.providers)
	r.mu.RUnlock()
	var all []ModelInfo
	for _, entry := range entries {
		for _, m := range entry.ModelSelector.GetAvailableModels() {
			m.Provider = entry.Name
			all = append(all, m)
		}
	}
	return all
}

// ModelsByProvider returns models for a single provider, tagged with its name.
func (r *ProviderRegistry) ModelsByProvider(provider string) []ModelInfo {
	r.mu.RLock()
	entry, ok := r.byName[provider]
	r.mu.RUnlock()
	if !ok {
		return nil
	}
	models := entry.ModelSelector.GetAvailableModels()
	result := make([]ModelInfo, len(models))
	for i, m := range models {
		m.Provider = entry.Name
		result[i] = m
	}
	return result
}

// GetProviderInfos returns metadata for all providers (used by /models endpoint).
func (r *ProviderRegistry) GetProviderInfos() []ProviderInfo {
	r.mu.RLock()
	entries := make([]*ProviderEntry, len(r.providers))
	copy(entries, r.providers)
	r.mu.RUnlock()
	infos := make([]ProviderInfo, 0, len(entries))
	for _, e := range entries {
		e.ModelSelector.mu.Lock()
		info := ProviderInfo{
			Name:   e.Name,
			Source: e.ModelSelector.source,
			Count:  len(e.ModelSelector.models),
		}
		if !e.ModelSelector.lastUpdated.IsZero() {
			info.UpdatedAt = e.ModelSelector.lastUpdated.Format(time.RFC3339)
		}
		if e.ModelSelector.refreshInterval > 0 {
			info.RefreshInterval = e.ModelSelector.refreshInterval.String()
		}
		e.ModelSelector.mu.Unlock()
		infos = append(infos, info)
	}
	return infos
}

func (r *ProviderRegistry) ProviderEntry(name string) *ProviderEntry {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.byName[name]
}

type Handler struct {
	providers           *ProviderRegistry
	systemPrompts       map[string]string
	defaultSystemPrompt string
	compactConfig       CompactConversationConfig
	registry            *tools.Registry
	store               *chat.SessionStore
	storageStore        storage.Store
	authService         *auth.Service
	log                 *zap.Logger
	staticFS            fs.FS
	uiConfig            UIConfig
	uploadRoot          string
	TraceEnabled        bool
}

type UIConfig struct {
	WelcomeTitle        string                      `json:"welcomeTitle"`
	AIDisclaimer        string                      `json:"aiDisclaimer"`
	PromptSuggestions   []string                    `json:"promptSuggestions"`
	SystemPrompts       []SystemPromptInfo          `json:"systemPrompts,omitempty"`
	CompactConversation CompactConversationUIConfig `json:"compactConversation,omitempty"`
}

type CompactConversationConfig struct {
	Enabled       bool
	Provider      string
	Model         string
	DefaultPrompt string
	AfterMessages int
	AfterTokens   int
}

type CompactConversationUIConfig struct {
	Enabled       bool   `json:"enabled,omitempty"`
	DefaultPrompt string `json:"defaultPrompt,omitempty"`
	AfterMessages int    `json:"afterMessages,omitempty"`
	AfterTokens   int    `json:"afterTokens,omitempty"`
}

type compactConversationRequest struct {
	Prompt string `json:"prompt,omitempty"`
	Model  string `json:"model,omitempty"`
}

type SystemPromptInfo struct {
	Name string `json:"name"`
}

// New creates a Handler.
func New(providers *ProviderRegistry, systemPrompts map[string]string, defaultSystemPrompt string, compactConfig CompactConversationConfig, registry *tools.Registry, store *chat.SessionStore, storageStore storage.Store, authService *auth.Service, log *zap.Logger, staticFS fs.FS, uiConfig UIConfig, uploadRoot string, traceEnabled bool) *Handler {
	if err := os.MkdirAll(uploadRoot, 0755); err != nil {
		log.Fatal("failed to create upload directory", zap.String("dir", uploadRoot), zap.Error(err))
	}
	return &Handler{
		providers:           providers,
		systemPrompts:       systemPrompts,
		defaultSystemPrompt: defaultSystemPrompt,
		compactConfig:       compactConfig,
		registry:            registry,
		store:               store,
		storageStore:        storageStore,
		authService:         authService,
		log:                 log,
		staticFS:            staticFS,
		uiConfig:            uiConfig,
		uploadRoot:          uploadRoot,
		TraceEnabled:        traceEnabled,
	}
}

type chatRequest struct {
	SessionID    string                 `json:"session_id"`
	Message      string                 `json:"message"`
	Files        []storage.UploadedFile `json:"files,omitempty"`
	Model        string                 `json:"model,omitempty"`
	Provider     string                 `json:"provider,omitempty"`
	SystemPrompt string                 `json:"system_prompt,omitempty"`
	Params       LLMParams              `json:"params,omitempty"` // UI overrides; zero values ignored
}

type chatResponse struct {
	Reply          string              `json:"reply"`
	Model          string              `json:"model"`
	Provider       string              `json:"provider,omitempty"`
	TimeTaken      int64               `json:"time_taken_ms"`
	LLMCalls       int                 `json:"llm_calls"`
	ToolCalls      int                 `json:"tool_calls"`
	UserMsgID      string              `json:"user_msg_id"`
	AssistantMsgID string              `json:"assistant_msg_id"`
	Trace          []storage.LLMRound  `json:"trace,omitempty"`
	UsedParams     *storage.UsedParams `json:"used_params,omitempty"`
	CompactSummary *storage.Message    `json:"compact_summary,omitempty"`
}

type errorResponse struct {
	Error      string `json:"error"`
	Model      string `json:"model,omitempty"`
	Provider   string `json:"provider,omitempty"`
	ErrorMsgID string `json:"error_msg_id,omitempty"`
}

func requestPrincipal(r *http.Request) *auth.Principal {
	return auth.PrincipalFromContext(r.Context())
}

func requestScope(r *http.Request) storage.Scope {
	principal := requestPrincipal(r)
	if principal == nil {
		return storage.Scope{}
	}
	return storage.Scope{TenantID: principal.Scope.TenantID, UserID: principal.Scope.UserID}
}

func (h *Handler) uploadDir(scope storage.Scope) string {
	return filepath.Join(h.uploadRoot, "tenants", scope.TenantID, "users", scope.UserID, "uploads")
}

func (h *Handler) uploadPath(scope storage.Scope, fileID string) string {
	return filepath.Join(h.uploadDir(scope), fileID)
}

func (h *Handler) promptNamesForPolicy(policy auth.EffectivePolicy) []SystemPromptInfo {
	filtered := make([]SystemPromptInfo, 0, len(h.uiConfig.SystemPrompts))
	for _, info := range h.uiConfig.SystemPrompts {
		if policy.AllowPrompt(info.Name) {
			filtered = append(filtered, info)
		}
	}
	return filtered
}

func stripConversationTrace(conv *storage.Conversation) *storage.Conversation {
	copyConv := *conv
	copyConv.Messages = make([]storage.Message, len(conv.Messages))
	copy(copyConv.Messages, conv.Messages)
	for i := range copyConv.Messages {
		copyConv.Messages[i].Trace = nil
	}
	return &copyConv
}

func filterHistoryMessages(history []storage.Message) []storage.Message {
	lastUserIdx := -1
	for i := len(history) - 1; i >= 0; i-- {
		if history[i].Role == llm.RoleUser {
			lastUserIdx = i
			break
		}
	}
	filtered := make([]storage.Message, 0, len(history))
	for i, msg := range history {
		if i >= lastUserIdx {
			filtered = append(filtered, msg)
			continue
		}
		switch msg.Role {
		case llm.RoleUser:
			filtered = append(filtered, msg)
		case llm.RoleAssistant:
			if msg.Content != "" {
				filtered = append(filtered, msg)
			}
		}
	}
	return filtered
}

func (h *Handler) buildMessages(scope storage.Scope, session *chat.Session, _ []storage.UploadedFile) []llm.Message {
	var messages []llm.Message
	conv := session.Snapshot()
	promptName := session.SystemPrompt()
	if prompt := h.systemPrompts[promptName]; prompt != "" {
		messages = append(messages, llm.Message{Role: llm.RoleSystem, Content: prompt})
	}
	if summary := h.compactionSummaryMessage(conv); summary != nil {
		messages = append(messages, llm.Message{Role: llm.RoleSystem, Content: "Conversation summary so far:\n" + summary.Content})
	}
	for _, msg := range filterHistoryMessages(h.messagesAfterCompaction(conv)) {
		if msg.Role == storage.MessageRoleError || msg.CompactSummary {
			continue
		}
		traceMsg := llm.Message{
			Role:       msg.Role,
			Content:    msg.Content,
			ToolCallID: msg.ToolCallID,
			Name:       msg.Name,
		}
		if msg.Role == llm.RoleUser && len(msg.Files) > 0 {
			traceMsg.Content = h.buildAttachmentText(scope, msg.Content, msg.Files)
		}
		for _, tc := range msg.InlineToolCalls {
			traceMsg.ToolCalls = append(traceMsg.ToolCalls, llm.ToolCall{
				ID:       tc.ID,
				Type:     llm.ToolTypeFunction,
				Function: llm.FunctionCall{Name: tc.Name, Arguments: tc.Arguments},
			})
		}
		messages = append(messages, traceMsg)
	}
	return messages
}

func (h *Handler) messagesAfterCompaction(conv storage.Conversation) []storage.Message {
	if conv.CompactedThroughMessageID == "" {
		return filterCompactionMessages(conv.Messages)
	}
	msgs := make([]storage.Message, 0, len(conv.Messages))
	seenCutoff := false
	for _, msg := range conv.Messages {
		if msg.CompactSummary || msg.ID == conv.CompactSummaryMessageID {
			continue
		}
		if seenCutoff {
			msgs = append(msgs, msg)
		}
		if msg.ID == conv.CompactedThroughMessageID {
			seenCutoff = true
		}
	}
	if !seenCutoff {
		return filterCompactionMessages(conv.Messages)
	}
	return msgs
}

func filterCompactionMessages(msgs []storage.Message) []storage.Message {
	filtered := make([]storage.Message, 0, len(msgs))
	for _, msg := range msgs {
		if msg.CompactSummary {
			continue
		}
		filtered = append(filtered, msg)
	}
	return filtered
}

func (h *Handler) compactionSummaryMessage(conv storage.Conversation) *storage.Message {
	if conv.CompactSummaryMessageID == "" {
		return nil
	}
	for i := range conv.Messages {
		if conv.Messages[i].ID == conv.CompactSummaryMessageID || conv.Messages[i].CompactSummary {
			return &conv.Messages[i]
		}
	}
	return nil
}

func countUserMessages(msgs []storage.Message) int {
	count := 0
	for _, msg := range msgs {
		if msg.CompactSummary {
			continue
		}
		if msg.Role == llm.RoleUser {
			count++
		}
	}
	return count
}

func estimateMessageTokens(msgs []storage.Message) int {
	total := 0
	for _, msg := range msgs {
		if msg.CompactSummary {
			continue
		}
		content := strings.TrimSpace(msg.Content)
		if content != "" {
			total += 4 + (len([]rune(content)) / 4)
		}
		total += 6
		if msg.Role == llm.RoleUser && len(msg.Files) > 0 {
			for _, file := range msg.Files {
				total += 8 + (len([]rune(file.Filename)) / 4)
			}
		}
	}
	return total
}

const maxInlinedTextFileBytes = 128 * 1024

type preparedAttachment struct {
	File     storage.UploadedFile
	Mode     string
	Text     string
	ImageURL string
	FileID   string
	Note     string
}

func rawUserMessageContent(content string, files []storage.UploadedFile) string {
	if len(files) == 0 {
		return content
	}
	var prefix strings.Builder
	prefix.WriteString("Attached files:\n")
	for _, f := range files {
		fmt.Fprintf(&prefix, "- %s\n", f.Filename)
	}
	p := prefix.String()
	if strings.HasPrefix(content, p+"\nUser request: ") {
		return strings.TrimPrefix(content, p+"\nUser request: ")
	}
	if content == p || content == strings.TrimSuffix(p, "\n") {
		return ""
	}
	return content
}

func (h *Handler) buildAttachmentText(scope storage.Scope, content string, files []storage.UploadedFile) string {
	content = rawUserMessageContent(content, files)
	if len(files) == 0 {
		return content
	}
	var b strings.Builder
	b.WriteString(content)
	if content != "" {
		b.WriteString("\n\n")
	}
	b.WriteString("Attachment details:\n")
	for _, f := range files {
		fmt.Fprintf(&b, "- %s", f.Filename)
		text, note := h.readAttachmentForPrompt(scope, f)
		switch {
		case text != "":
			fmt.Fprintf(&b, "\n  Inlined contents:\n%s\n", indentText(text, "  "))
		case note != "":
			fmt.Fprintf(&b, " (%s)\n", note)
		default:
			b.WriteString("\n")
		}
	}
	return strings.TrimSpace(b.String())
}

func (h *Handler) readAttachmentForPrompt(scope storage.Scope, file storage.UploadedFile) (string, string) {
	data, err := h.readUploadedFile(scope, file)
	if err != nil {
		return "", "attachment could not be read by the server"
	}
	if isImageFile(file.Filename, data) {
		return "", "image attached separately"
	}
	if !isTextLikeFile(file.Filename, data) {
		return "", "binary attachment metadata only"
	}
	if len(data) > maxInlinedTextFileBytes {
		data = data[:maxInlinedTextFileBytes]
		return string(data) + "\n[truncated]", ""
	}
	return string(data), ""
}

func providerRefFor(file storage.UploadedFile, provider string) *storage.ProviderFileRef {
	for i := range file.ProviderRefs {
		if file.ProviderRefs[i].Provider == provider {
			ref := file.ProviderRefs[i]
			return &ref
		}
	}
	return nil
}

func upsertProviderRef(file storage.UploadedFile, provider, fileID string) storage.UploadedFile {
	for i := range file.ProviderRefs {
		if file.ProviderRefs[i].Provider == provider {
			file.ProviderRefs[i].FileID = fileID
			file.ProviderRefs[i].UploadedAt = time.Now().UnixMilli()
			return file
		}
	}
	file.ProviderRefs = append(file.ProviderRefs, storage.ProviderFileRef{Provider: provider, FileID: fileID, UploadedAt: time.Now().UnixMilli()})
	return file
}

func detectFileContentType(file storage.UploadedFile, data []byte) string {
	if strings.TrimSpace(file.ContentType) != "" {
		return file.ContentType
	}
	contentType := http.DetectContentType(data)
	if strings.HasPrefix(contentType, "application/octet-stream") {
		if imageContentType := imageContentTypeFromName(file.Filename); imageContentType != "" {
			return imageContentType
		}
	}
	return contentType
}

func fileSHA256(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func isImageAttachment(file storage.UploadedFile, data []byte) bool {
	contentType := detectFileContentType(file, data)
	return strings.HasPrefix(contentType, "image/") || isImageFile(file.Filename, data)
}

func isTextAttachment(file storage.UploadedFile, data []byte) bool {
	contentType := detectFileContentType(file, data)
	return strings.HasPrefix(contentType, "text/") || isTextLikeFile(file.Filename, data)
}

func (h *Handler) uploadFileToProvider(ctx context.Context, entry *ProviderEntry, file storage.UploadedFile, data []byte) (storage.UploadedFile, string, error) {
	if entry == nil || !entry.FileUploads.Enabled {
		return file, "", fmt.Errorf("provider file uploads disabled")
	}
	if ref := providerRefFor(file, entry.Name); ref != nil && ref.FileID != "" {
		return file, ref.FileID, nil
	}
	uploaded, err := entry.Client.Files.New(ctx, openai.FileNewParams{File: bytes.NewReader(data), Purpose: openai.FilePurpose(entry.FileUploads.Purpose)})
	if err != nil {
		return file, "", err
	}
	file = upsertProviderRef(file, entry.Name, uploaded.ID)
	return file, uploaded.ID, nil
}

func (h *Handler) prepareAttachment(ctx context.Context, scope storage.Scope, entry *ProviderEntry, file storage.UploadedFile) (preparedAttachment, error) {
	data, err := h.readUploadedFile(scope, file)
	if err != nil {
		return preparedAttachment{File: file, Mode: "metadata_only", Note: "attachment could not be read by the server"}, nil
	}
	file.ContentType = detectFileContentType(file, data)
	if file.SHA256 == "" {
		file.SHA256 = fileSHA256(data)
	}
	maxInline := maxInlinedTextFileBytes
	if entry != nil && entry.FileUploads.MaxInlineTextBytes > 0 {
		maxInline = entry.FileUploads.MaxInlineTextBytes
	}
	if isTextAttachment(file, data) && len(data) <= maxInline {
		return preparedAttachment{File: file, Mode: "inline_text", Text: string(data)}, nil
	}
	if entry != nil && entry.FileUploads.Enabled {
		updatedFile, fileID, uploadErr := h.uploadFileToProvider(ctx, entry, file, data)
		if uploadErr == nil {
			return preparedAttachment{File: updatedFile, Mode: "uploaded_reference", FileID: fileID}, nil
		}
		h.log.Warn("provider file upload failed; falling back", zap.String("provider", entry.Name), zap.String("filename", file.Filename), zap.Error(uploadErr))
		file = updatedFile
	}
	if isImageAttachment(file, data) {
		if entry != nil && entry.FileUploads.PreferInlineImages {
			if imageURL, ok := h.inlineImageDataURL(scope, file); ok {
				return preparedAttachment{File: file, Mode: "inline_image", ImageURL: imageURL, Note: "uploaded file reference unavailable; sent as inline image"}, nil
			}
		}
		note := fmt.Sprintf("image attachment metadata only (%s, %d bytes)", file.ContentType, file.Size)
		if file.ContentType == "" {
			note = fmt.Sprintf("image attachment metadata only (%d bytes)", file.Size)
		}
		if entry != nil && !entry.FileUploads.Enabled {
			note += "; provider file uploads are disabled"
		}
		if entry != nil && entry.FileUploads.Enabled && !entry.FileUploads.PreferInlineImages {
			note += "; inline image fallback disabled"
		}
		return preparedAttachment{File: file, Mode: "metadata_only", Note: note}, nil
	}
	if isTextAttachment(file, data) {
		if len(data) > maxInline {
			return preparedAttachment{File: file, Mode: "inline_text", Text: string(data[:maxInline]) + "\n[truncated after upload fallback]", Note: "uploaded file reference unavailable; text was truncated"}, nil
		}
		return preparedAttachment{File: file, Mode: "inline_text", Text: string(data), Note: "uploaded file reference unavailable; sent as inline text"}, nil
	}
	note := fmt.Sprintf("binary attachment metadata only (%s, %d bytes)", file.ContentType, file.Size)
	if file.ContentType == "" {
		note = fmt.Sprintf("binary attachment metadata only (%d bytes)", file.Size)
	}
	return preparedAttachment{File: file, Mode: "metadata_only", Note: note}, nil
}

func contentPartsToText(content string, attachments []preparedAttachment) string {
	var b strings.Builder
	content = strings.TrimSpace(content)
	if content != "" {
		b.WriteString(content)
	}
	if len(attachments) > 0 {
		if b.Len() > 0 {
			b.WriteString("\n\n")
		}
		b.WriteString("Attachment details:\n")
		for _, attachment := range attachments {
			fmt.Fprintf(&b, "- %s", attachment.File.Filename)
			switch attachment.Mode {
			case "inline_text":
				fmt.Fprintf(&b, "\n  Inlined contents:\n%s\n", indentText(attachment.Text, "  "))
			case "uploaded_reference":
				fmt.Fprintf(&b, " (provider file id: %s)\n", attachment.FileID)
			default:
				if attachment.Note != "" {
					fmt.Fprintf(&b, " (%s)\n", attachment.Note)
				} else {
					b.WriteString("\n")
				}
			}
		}
	}
	return strings.TrimSpace(b.String())
}

func sanitizeAssistantMessage(msg llm.Message) llm.Message {
	msg.Content = strings.TrimLeft(msg.Content, "\n")
	msg.Refusal = strings.TrimLeft(msg.Refusal, "\n")
	msg.ReasoningContent = strings.TrimLeft(msg.ReasoningContent, "\n")
	return msg
}

func (h *Handler) buildUserMessageParts(ctx context.Context, scope storage.Scope, entry *ProviderEntry, msg storage.Message, session *chat.Session) ([]map[string]any, llm.Message, error) {
	content := rawUserMessageContent(msg.Content, msg.Files)
	parts := make([]map[string]any, 0, len(msg.Files)+1)
	prepared := make([]preparedAttachment, 0, len(msg.Files))
	updatedFiles := make([]storage.UploadedFile, len(msg.Files))
	if content != "" {
		parts = append(parts, map[string]any{"type": "text", "text": content})
	}
	for i, file := range msg.Files {
		attachment, err := h.prepareAttachment(ctx, scope, entry, file)
		if err != nil {
			return nil, llm.Message{}, err
		}
		prepared = append(prepared, attachment)
		updatedFiles[i] = attachment.File
		switch attachment.Mode {
		case "inline_text":
			parts = append(parts, map[string]any{"type": "text", "text": fmt.Sprintf("Attached file %q:\n%s", attachment.File.Filename, attachment.Text)})
		case "inline_image":
			parts = append(parts,
				map[string]any{"type": "text", "text": fmt.Sprintf("Attached image %q.", attachment.File.Filename)},
				map[string]any{"type": "image_url", "image_url": map[string]any{"url": attachment.ImageURL, "detail": llm.ImageURLDetailAuto}},
			)
		case "uploaded_reference":
			parts = append(parts, map[string]any{"type": "file", "file": map[string]any{"file_id": attachment.FileID}})
		default:
			parts = append(parts, map[string]any{"type": "text", "text": fmt.Sprintf("Attached file %q: %s", attachment.File.Filename, attachment.Note)})
		}
	}
	if len(msg.Files) > 0 {
		session.UpdateMessageFiles(msg.ID, updatedFiles)
	}
	traceMsg := llm.Message{Role: llm.RoleUser, Content: contentPartsToText(content, prepared)}
	return parts, traceMsg, nil
}

func storageMessageToRawMap(msg storage.Message) map[string]any {
	out := map[string]any{"role": msg.Role}
	if msg.Content != "" {
		out["content"] = msg.Content
	}
	if msg.Name != "" {
		out["name"] = msg.Name
	}
	if msg.ToolCallID != "" {
		out["tool_call_id"] = msg.ToolCallID
	}
	if len(msg.InlineToolCalls) > 0 {
		calls := make([]map[string]any, 0, len(msg.InlineToolCalls))
		for _, tc := range msg.InlineToolCalls {
			calls = append(calls, map[string]any{
				"id":       tc.ID,
				"type":     llm.ToolTypeFunction,
				"function": map[string]any{"name": tc.Name, "arguments": tc.Arguments},
			})
		}
		out["tool_calls"] = calls
	}
	return out
}

func (h *Handler) buildChatCompletionRequest(ctx context.Context, scope storage.Scope, session *chat.Session, entry *ProviderEntry, model string, modelParams LLMParams, tools []llm.Tool) (map[string]any, []llm.Message, error) {
	conv := session.Snapshot()
	rawMessages := make([]map[string]any, 0)
	traceMessages := make([]llm.Message, 0)
	promptName := session.SystemPrompt()
	if prompt := h.systemPrompts[promptName]; prompt != "" {
		rawMessages = append(rawMessages, map[string]any{"role": llm.RoleSystem, "content": prompt})
		traceMessages = append(traceMessages, llm.Message{Role: llm.RoleSystem, Content: prompt})
	}
	if summary := h.compactionSummaryMessage(conv); summary != nil {
		summaryContent := "Conversation summary so far:\n" + summary.Content
		rawMessages = append(rawMessages, map[string]any{"role": llm.RoleSystem, "content": summaryContent})
		traceMessages = append(traceMessages, llm.Message{Role: llm.RoleSystem, Content: summaryContent})
	}
	for _, msg := range filterHistoryMessages(h.messagesAfterCompaction(conv)) {
		if msg.Role == storage.MessageRoleError || msg.CompactSummary {
			continue
		}
		if msg.Role == llm.RoleUser && len(msg.Files) > 0 {
			parts, traceMsg, err := h.buildUserMessageParts(ctx, scope, entry, msg, session)
			if err != nil {
				return nil, nil, err
			}
			rawMessages = append(rawMessages, map[string]any{"role": llm.RoleUser, "content": parts})
			traceMessages = append(traceMessages, traceMsg)
			continue
		}
		rawMessages = append(rawMessages, storageMessageToRawMap(msg))
		traceMsg := llm.Message{Role: msg.Role, Content: msg.Content, Name: msg.Name, ToolCallID: msg.ToolCallID}
		for _, tc := range msg.InlineToolCalls {
			traceMsg.ToolCalls = append(traceMsg.ToolCalls, llm.ToolCall{ID: tc.ID, Type: llm.ToolTypeFunction, Function: llm.FunctionCall{Name: tc.Name, Arguments: tc.Arguments}})
		}
		traceMessages = append(traceMessages, traceMsg)
	}
	body := map[string]any{"model": model, "messages": rawMessages}
	if modelParams.Temperature != nil {
		body["temperature"] = *modelParams.Temperature
	}
	if modelParams.MaxTokens != 0 {
		body["max_tokens"] = modelParams.MaxTokens
	}
	if modelParams.TopP != nil {
		body["top_p"] = *modelParams.TopP
	}
	if modelParams.TopK != 0 {
		body["top_k"] = modelParams.TopK
	}
	if len(tools) > 0 {
		body["tools"] = tools
	}
	return body, traceMessages, nil
}

func (h *Handler) inlineImageDataURL(scope storage.Scope, file storage.UploadedFile) (string, bool) {
	data, err := h.readUploadedFile(scope, file)
	if err != nil || !isImageAttachment(file, data) {
		return "", false
	}
	contentType := detectFileContentType(file, data)
	if !strings.HasPrefix(contentType, "image/") {
		contentType = imageContentTypeFromName(file.Filename)
	}
	if contentType == "" {
		contentType = "image/png"
	}
	return "data:" + contentType + ";base64," + base64.StdEncoding.EncodeToString(data), true
}

func (h *Handler) readUploadedFile(scope storage.Scope, file storage.UploadedFile) ([]byte, error) {
	filePath := h.uploadPath(scope, file.ID)
	uploadDir := h.uploadDir(scope)
	if !isUnderDir(filePath, uploadDir) {
		return nil, fmt.Errorf("forbidden path")
	}
	return os.ReadFile(filePath)
}

func collectFiles(messages []storage.Message) []storage.UploadedFile {
	if len(messages) == 0 {
		return nil
	}
	files := make([]storage.UploadedFile, 0)
	seen := make(map[string]struct{})
	for _, msg := range messages {
		for _, file := range msg.Files {
			if file.ID == "" {
				continue
			}
			if _, ok := seen[file.ID]; ok {
				continue
			}
			seen[file.ID] = struct{}{}
			files = append(files, file)
		}
	}
	return files
}

func filesForDeletedSuffix(messages []storage.Message, msgID string) ([]storage.UploadedFile, error) {
	for i, msg := range messages {
		if msg.ID == msgID {
			return collectFiles(messages[i:]), nil
		}
	}
	return nil, storage.ErrNotFound
}

func fileIDsSet(files []storage.UploadedFile) map[string]struct{} {
	ids := make(map[string]struct{}, len(files))
	for _, file := range files {
		if file.ID != "" {
			ids[file.ID] = struct{}{}
		}
	}
	return ids
}

func excludeFiles(files []storage.UploadedFile, stillReferenced []storage.UploadedFile) []storage.UploadedFile {
	if len(files) == 0 {
		return nil
	}
	keep := fileIDsSet(stillReferenced)
	filtered := make([]storage.UploadedFile, 0, len(files))
	for _, file := range files {
		if _, ok := keep[file.ID]; ok {
			continue
		}
		filtered = append(filtered, file)
	}
	return filtered
}

func (h *Handler) removeUploadedFiles(files []storage.UploadedFile) {
	for _, file := range files {
		if file.ID == "" {
			continue
		}
		filePath := h.uploadPath(storage.Scope{TenantID: file.TenantID, UserID: file.UserID}, file.ID)
		uploadDir := h.uploadDir(storage.Scope{TenantID: file.TenantID, UserID: file.UserID})
		if !isUnderDir(filePath, uploadDir) {
			h.log.Warn("refused to delete attachment outside upload dir", zap.String("file_id", file.ID), zap.String("path", filePath))
			continue
		}
		if err := os.Remove(filePath); err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			h.log.Warn("failed to delete attachment file", zap.String("file_id", file.ID), zap.String("filename", file.Filename), zap.Error(err))
		}
	}
}

func isImageFile(filename string, data []byte) bool {
	return strings.HasPrefix(http.DetectContentType(data), "image/") || imageContentTypeFromName(filename) != ""
}

func imageContentTypeFromName(filename string) string {
	switch strings.ToLower(filepath.Ext(filename)) {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".gif":
		return "image/gif"
	case ".webp":
		return "image/webp"
	case ".bmp":
		return "image/bmp"
	case ".svg":
		return "image/svg+xml"
	default:
		return ""
	}
}

func isTextLikeFile(filename string, data []byte) bool {
	contentType := strings.ToLower(http.DetectContentType(data))
	if strings.HasPrefix(contentType, "text/") {
		return true
	}
	switch strings.ToLower(filepath.Ext(filename)) {
	case ".txt", ".md", ".markdown", ".json", ".yaml", ".yml", ".xml", ".csv", ".tsv", ".log", ".html", ".css", ".js", ".jsx", ".ts", ".tsx", ".py", ".go", ".java", ".rb", ".php", ".rs", ".c", ".cc", ".cpp", ".h", ".hpp", ".sh", ".sql":
		return true
	default:
		return strings.Contains(contentType, "json") || strings.Contains(contentType, "xml") || strings.Contains(contentType, "javascript")
	}
}

func indentText(text, prefix string) string {
	lines := strings.Split(text, "\n")
	for i := range lines {
		lines[i] = prefix + lines[i]
	}
	return strings.Join(lines, "\n")
}

// filterHistory strips intermediate tool-call scaffolding from completed prior
// turns, keeping only user messages and assistant messages that have text
// content. Tool-call-only assistant messages (no content) and tool-result
// messages from already-completed turns waste tokens and are not needed for
// future LLM calls — the final assistant text reply already summarises them.
//
// Messages from the last user message onward are left untouched because they
// belong to the currently active tool-call loop and must remain intact for the
// OpenAI API contract.
func filterHistory(history []llm.Message) []llm.Message {
	// Find the index of the last user message. Everything from there onward is
	// the active turn and must not be touched.
	lastUserIdx := -1
	for i := len(history) - 1; i >= 0; i-- {
		if history[i].Role == llm.RoleUser {
			lastUserIdx = i
			break
		}
	}

	filtered := make([]llm.Message, 0, len(history))
	for i, msg := range history {
		if i >= lastUserIdx {
			// Active turn — keep everything as-is.
			filtered = append(filtered, msg)
			continue
		}
		// Prior turns: keep only user messages and assistant messages that
		// carry actual text content. Drop pure tool-call assistant messages
		// (content == "" and ToolCalls set) and all tool-result messages.
		switch msg.Role {
		case llm.RoleUser:
			filtered = append(filtered, msg)
		case llm.RoleAssistant:
			if msg.Content != "" {
				filtered = append(filtered, msg)
			}
			// else: pure tool-call request — drop it
			// llm.RoleTool: drop entirely
		}
	}
	return filtered
}

func (h *Handler) hasSystemPrompt(promptName string) bool {
	if promptName == "" {
		return false
	}
	_, ok := h.systemPrompts[promptName]
	return ok
}

func (h *Handler) requireAllowedSystemPrompt(principal *auth.Principal, promptName string) error {
	if promptName == "" {
		return fmt.Errorf("system prompt is required")
	}
	if !h.hasSystemPrompt(promptName) {
		return fmt.Errorf("invalid system prompt")
	}
	if !principal.Policy.AllowPrompt(promptName) {
		return fmt.Errorf("system prompt not allowed")
	}
	return nil
}

// traceUsage converts an llm.Usage to our storage.TokenUsage, including
// reasoning and cached-prompt token breakdowns when the provider returns them.
func traceUsage(u llm.Usage) *storage.TokenUsage {
	tu := &storage.TokenUsage{
		PromptTokens:     u.PromptTokens,
		CompletionTokens: u.CompletionTokens,
		TotalTokens:      u.TotalTokens,
	}
	if u.CompletionTokensDetails != nil {
		tu.ReasoningTokens = u.CompletionTokensDetails.ReasoningTokens
	}
	if u.PromptTokensDetails != nil {
		tu.CachedTokens = u.PromptTokensDetails.CachedTokens
	}
	return tu
}

// maxToolIterations caps the tool-call loop to prevent infinite loops from
// misbehaving or adversarially-prompted models.
const maxToolIterations = 20

// runLLM sends the current session to the LLM and handles any tool calls in a loop
// until the model returns a final text response. It does NOT append the final
// assistant message to the session — the caller must do that (so it can attach metadata).
// Returns the reply text, the final assistant message, model used, LLM call count,
// tool call count, the full trace of all LLM round-trips, the effective params used,
// and any error.
func (h *Handler) runLLM(ctx context.Context, principal *auth.Principal, sessionID string, session *chat.Session, preferredModel, provider string, reqParams LLMParams, currentFiles []storage.UploadedFile) (string, llm.Message, string, string, int, int, []storage.LLMRound, *storage.UsedParams, error) {
	llmCalls := 0
	toolCalls := 0
	var trace []storage.LLMRound
	scope := storage.Scope{TenantID: principal.Scope.TenantID, UserID: principal.Scope.UserID}
	if preferredModel != "" && provider != "" && !principal.Policy.AllowModel(provider, preferredModel) {
		return "", llm.Message{}, preferredModel, provider, llmCalls, toolCalls, trace, nil, fmt.Errorf("model %q is not allowed", preferredModel)
	}
	model, _, providerUsed, llmClient := h.resolveAllowedModel(principal, preferredModel, provider)
	providerEntry := h.providers.ProviderEntry(providerUsed)
	if model == "" || providerUsed == "" || llmClient == nil || providerEntry == nil {
		return "", llm.Message{}, preferredModel, provider, llmCalls, toolCalls, trace, nil, fmt.Errorf("no allowed model available")
	}
	if !principal.Policy.AllowModel(providerUsed, model) {
		return "", llm.Message{}, model, providerUsed, llmCalls, toolCalls, trace, nil, fmt.Errorf("model %q from provider %q is not allowed", model, providerUsed)
	}

	// Resolve effective params: model-config defaults, overridden by UI request.
	modelParams := h.providers.GetModelParamsForProvider(model, provider)
	// UI request params override model-config params.
	if reqParams.Temperature != nil {
		modelParams.Temperature = reqParams.Temperature
	}
	if reqParams.MaxTokens != 0 {
		modelParams.MaxTokens = reqParams.MaxTokens
	}
	if reqParams.TopP != nil {
		modelParams.TopP = reqParams.TopP
	}
	if reqParams.TopK != 0 {
		modelParams.TopK = reqParams.TopK
	}

	// Build the UsedParams record from the effective (merged) params.
	// Only include fields that are actually set so the UI can distinguish
	// "explicitly set to X" from "not set / provider default".
	var usedParams *storage.UsedParams
	if modelParams.Temperature != nil || modelParams.MaxTokens != 0 || modelParams.TopP != nil || modelParams.TopK != 0 {
		usedParams = &storage.UsedParams{
			Temperature: modelParams.Temperature,
			MaxTokens:   modelParams.MaxTokens,
			TopP:        modelParams.TopP,
			TopK:        modelParams.TopK,
		}
	}

	for {
		if llmCalls >= maxToolIterations {
			return "", llm.Message{}, model, providerUsed, llmCalls, toolCalls, trace, usedParams, fmt.Errorf("exceeded max tool call iterations (%d)", maxToolIterations)
		}
		llmCalls++
		allowedTools := []llm.Tool(nil)
		if h.registry != nil && !h.registry.Empty() {
			toolNames := principal.Policy.FilterAllowedToolNames(h.registry.Names())
			if len(toolNames) > 0 {
				allowedTools = h.registry.OpenAIToolsByNames(toolNames)
			}
		}
		requestBody, requestMsgs, err := h.buildChatCompletionRequest(ctx, scope, session, providerEntry, model, modelParams, allowedTools)
		if err != nil {
			return "", llm.Message{}, model, providerUsed, llmCalls, toolCalls, trace, usedParams, fmt.Errorf("build chat request: %w", err)
		}

		// Snapshot available tools for the trace before the API call.
		var availableTools []storage.TraceToolDef
		for _, t := range allowedTools {
			availableTools = append(availableTools, storage.ToolDefFromOpenAI(t))
		}

		h.log.Debug("llm request",
			zap.String("session_id", sessionID),
			zap.String("model", model),
			zap.Any("messages", requestMsgs),
		)

		llmStart := time.Now()
		resp, err := createRawChatCompletion(ctx, providerEntry, requestBody)
		llmDurationMs := time.Since(llmStart).Milliseconds()
		if err != nil {
			return "", llm.Message{}, model, providerUsed, llmCalls, toolCalls, trace, usedParams, fmt.Errorf("LLM error: %w", err)
		}

		if len(resp.Choices) == 0 {
			return "", llm.Message{}, model, providerUsed, llmCalls, toolCalls, trace, usedParams, fmt.Errorf("LLM returned no choices")
		}
		choice := resp.Choices[0]
		choice.Message = sanitizeAssistantMessage(choice.Message)

		h.log.Debug("llm response",
			zap.String("session_id", sessionID),
			zap.String("finish_reason", string(choice.FinishReason)),
			zap.Int("prompt_tokens", resp.Usage.PromptTokens),
			zap.Int("completion_tokens", resp.Usage.CompletionTokens),
			zap.String("reply", choice.Message.Content),
			zap.Int64("llm_duration_ms", llmDurationMs),
		)

		// No tool calls — we have the final answer. Record the round and return.
		if choice.FinishReason != llm.FinishReasonToolCalls {
			if choice.Message.Content == "" {
				return "", llm.Message{}, model, providerUsed, llmCalls, toolCalls, trace, usedParams, fmt.Errorf("model returned an empty response (finish_reason: %q) — the model may not support tool calling", choice.FinishReason)
			}
			if h.TraceEnabled {
				trace = append(trace, storage.LLMRound{
					Request:        storage.ToTraceMessages(requestMsgs),
					Response:       storage.ToTraceMessage(choice.Message),
					LLMDurationMs:  llmDurationMs,
					AvailableTools: availableTools,
					Usage:          traceUsage(resp.Usage),
				})
			}

			return choice.Message.Content, choice.Message, model, providerUsed, llmCalls, toolCalls, trace, usedParams, nil
		}

		// Append the assistant message that contains the tool call requests.
		session.AddMessage(choice.Message)

		// Execute each requested tool, timing each one individually.
		round := storage.LLMRound{
			Request:        storage.ToTraceMessages(requestMsgs),
			Response:       storage.ToTraceMessage(choice.Message),
			LLMDurationMs:  llmDurationMs,
			AvailableTools: availableTools,
			Usage:          traceUsage(resp.Usage),
		}
		for _, tc := range choice.Message.ToolCalls {
			toolCalls++
			toolStart := time.Now()
			result, toolErr := h.executeTool(ctx, principal, tc)
			toolDurationMs := time.Since(toolStart).Milliseconds()
			h.log.Debug("tool executed",
				zap.String("tool", tc.Function.Name),
				zap.String("args", tc.Function.Arguments),
				zap.String("result", result),
				zap.Int64("tool_duration_ms", toolDurationMs),
			)
			round.ToolResults = append(round.ToolResults, storage.ToolResult{
				Name:       tc.Function.Name,
				Args:       tc.Function.Arguments,
				Result:     result,
				DurationMs: toolDurationMs,
			})
			session.AddMessage(llm.Message{
				Role:       llm.RoleTool,
				ToolCallID: tc.ID,
				Content:    result,
				Name:       tc.Function.Name,
			})
			if toolErr != nil {
				h.log.Warn("tool error", zap.String("tool", tc.Function.Name), zap.Error(toolErr))
			}
		}
		if h.TraceEnabled {
			trace = append(trace, round)
		}
		currentFiles = nil
		// Loop: send tool results back to the LLM.
	}
}

func (h *Handler) resolveAllowedModel(principal *auth.Principal, preferredModel, provider string) (string, string, string, *openai.Client) {
	if preferredModel != "" {
		return h.providers.ResolveModelWithProvider(preferredModel, provider)
	}

	h.providers.mu.RLock()
	defer h.providers.mu.RUnlock()

	if provider != "" {
		entry, ok := h.providers.byName[provider]
		if !ok {
			return "", "", "", nil
		}
		allowed := make([]ModelInfo, 0)
		for _, candidate := range entry.ModelSelector.GetAvailableModels() {
			if principal.Policy.AllowModel(entry.Name, candidate.ID) {
				allowed = append(allowed, candidate)
			}
		}
		model, name := entry.ModelSelector.GetModelFromCandidates(allowed, "")
		return model, name, entry.Name, entry.Client
	}

	for _, entry := range h.providers.providers {
		allowed := make([]ModelInfo, 0)
		for _, candidate := range entry.ModelSelector.GetAvailableModels() {
			if principal.Policy.AllowModel(entry.Name, candidate.ID) {
				allowed = append(allowed, candidate)
			}
		}
		if len(allowed) == 0 {
			continue
		}
		model, name := entry.ModelSelector.GetModelFromCandidates(allowed, "")
		return model, name, entry.Name, entry.Client
	}

	return "", "", "", nil
}

func (h *Handler) compactionPrompt(override string) string {
	prompt := strings.TrimSpace(override)
	if prompt != "" {
		return prompt
	}
	prompt = strings.TrimSpace(h.compactConfig.DefaultPrompt)
	if prompt != "" {
		return prompt
	}
	return "Summarize the conversation so far. Preserve user goals, decisions, constraints, file references, and unresolved issues. Omit repetition and casual filler."
}

func compactableMessages(conv storage.Conversation, excludeTrailingUser bool) ([]storage.Message, string) {
	msgs := filterCompactionMessages(conv.Messages)
	if conv.CompactedThroughMessageID != "" {
		seenCutoff := false
		filtered := make([]storage.Message, 0, len(msgs))
		for _, msg := range msgs {
			if seenCutoff {
				filtered = append(filtered, msg)
			}
			if msg.ID == conv.CompactedThroughMessageID {
				seenCutoff = true
			}
		}
		if seenCutoff {
			msgs = filtered
		}
	}
	if excludeTrailingUser && len(msgs) > 0 && msgs[len(msgs)-1].Role == llm.RoleUser {
		msgs = msgs[:len(msgs)-1]
	}
	if len(msgs) == 0 {
		return nil, ""
	}
	return msgs, msgs[len(msgs)-1].ID
}

func formatCompactionTranscript(msgs []storage.Message) string {
	var b strings.Builder
	for _, msg := range msgs {
		role := strings.ToUpper(msg.Role)
		if role == strings.ToUpper(storage.MessageRoleError) {
			role = "ERROR"
		}
		b.WriteString(role)
		b.WriteString(":\n")
		b.WriteString(strings.TrimSpace(msg.Content))
		if len(msg.Files) > 0 {
			b.WriteString("\nAttachments:")
			for _, file := range msg.Files {
				b.WriteString("\n- ")
				b.WriteString(file.Filename)
			}
		}
		b.WriteString("\n\n")
	}
	return strings.TrimSpace(b.String())
}

func (h *Handler) maybeAutoCompact(ctx context.Context, principal *auth.Principal, session *chat.Session) *storage.Message {
	if !h.compactConfig.Enabled || (h.compactConfig.AfterMessages <= 0 && h.compactConfig.AfterTokens <= 0) {
		return nil
	}
	conv := session.Snapshot()
	msgs, _ := compactableMessages(conv, true)
	userMessageCount := countUserMessages(msgs)
	estimatedTokens := estimateMessageTokens(msgs)
	hitMessageThreshold := h.compactConfig.AfterMessages > 0 && userMessageCount >= h.compactConfig.AfterMessages
	hitTokenThreshold := h.compactConfig.AfterTokens > 0 && estimatedTokens >= h.compactConfig.AfterTokens
	if !hitMessageThreshold && !hitTokenThreshold {
		return nil
	}
	msg, err := h.compactConversation(ctx, principal, session, "", "", true)
	if err != nil {
		h.log.Warn("auto compaction skipped", zap.String("session_id", session.ID()), zap.Error(err))
		return nil
	}
	return msg
}

func (h *Handler) compactConversation(ctx context.Context, principal *auth.Principal, session *chat.Session, promptOverride, modelOverride string, excludeTrailingUser bool) (*storage.Message, error) {
	conv := session.Snapshot()
	msgs, compactedThroughID := compactableMessages(conv, excludeTrailingUser)
	if len(msgs) == 0 || compactedThroughID == "" {
		return nil, fmt.Errorf("no messages available to compact")
	}
	prompt := h.compactionPrompt(promptOverride)
	providerPreference := strings.TrimSpace(h.compactConfig.Provider)
	modelPreference := strings.TrimSpace(modelOverride)
	if modelPreference == "" {
		modelPreference = strings.TrimSpace(h.compactConfig.Model)
	}
	modelID, _, providerUsed, client := h.resolveAllowedModel(principal, modelPreference, providerPreference)
	if modelID != "" && providerUsed != "" && !principal.Policy.AllowModel(providerUsed, modelID) {
		modelID, _, providerUsed, client = h.resolveAllowedModel(principal, "", providerPreference)
	}
	if modelID == "" || providerUsed == "" || client == nil {
		modelID, _, providerUsed, client = h.resolveAllowedModel(principal, "", "")
	}
	if modelID == "" || providerUsed == "" || client == nil {
		return nil, fmt.Errorf("no allowed model available for compaction")
	}
	providerEntry := h.providers.ProviderEntry(providerUsed)
	requestMessages := []llm.Message{{
		Role:    llm.RoleSystem,
		Content: prompt,
	}}
	if summary := h.compactionSummaryMessage(conv); summary != nil && strings.TrimSpace(summary.Content) != "" {
		requestMessages = append(requestMessages, llm.Message{
			Role:    llm.RoleUser,
			Content: "Existing summary:\n" + strings.TrimSpace(summary.Content),
		})
	}
	requestMessages = append(requestMessages, llm.Message{
		Role:    llm.RoleUser,
		Content: "New conversation content to merge into the rolling summary:\n\n" + formatCompactionTranscript(msgs),
	})
	started := time.Now()
	resp, err := createRawChatCompletion(ctx, providerEntry, map[string]any{"model": modelID, "messages": requestMessages})
	if err != nil {
		return nil, fmt.Errorf("compact conversation: %w", err)
	}
	if len(resp.Choices) == 0 {
		return nil, fmt.Errorf("compact conversation returned no choices")
	}
	responseMsg := sanitizeAssistantMessage(resp.Choices[0].Message)
	content := strings.TrimSpace(responseMsg.Content)
	if content == "" {
		return nil, fmt.Errorf("compact conversation returned empty summary")
	}
	trace := []storage.LLMRound{{
		Request:       storage.ToTraceMessages(requestMessages),
		Response:      storage.ToTraceMessage(responseMsg),
		LLMDurationMs: time.Since(started).Milliseconds(),
		Usage:         traceUsage(resp.Usage),
	}}
	msgID := session.SetCompactionSummary(content, prompt, modelID, providerUsed, compactedThroughID, time.Since(started).Milliseconds(), 1, trace)
	updated := session.Snapshot()
	for i := range updated.Messages {
		if updated.Messages[i].ID == msgID {
			return &updated.Messages[i], nil
		}
	}
	return nil, fmt.Errorf("failed to persist compact summary")
}

func (h *Handler) executeTool(ctx context.Context, principal *auth.Principal, tc llm.ToolCall) (string, error) {
	if principal != nil && !principal.Policy.AllowTool(tc.Function.Name) {
		return fmt.Sprintf("tool %q is not allowed", tc.Function.Name), nil
	}
	tool, ok := h.registry.Get(tc.Function.Name)
	if !ok {
		return fmt.Sprintf("tool %q not found", tc.Function.Name), nil
	}
	args := tc.Function.Arguments
	if args == "" {
		args = "{}"
	}
	result, err := tool.Execute(ctx, json.RawMessage(args))
	if err != nil {
		return fmt.Sprintf("error: %v", err), err
	}
	return result, nil
}

func (h *Handler) Chat(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.Chat {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "chat not allowed"})
		return
	}
	var req chatRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request body"})
		return
	}
	if req.Message == "" && len(req.Files) == 0 {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "message or files is required"})
		return
	}
	if req.SessionID == "" {
		req.SessionID = "default"
	}

	start := time.Now()
	scope := requestScope(r)

	session := h.store.Get(scope, req.SessionID)

	// Record the user's explicit model choice before the first persist so it's
	// included in the very first save (triggered by Add below).
	if err := h.requireAllowedSystemPrompt(principal, req.SystemPrompt); err != nil {
		status := http.StatusBadRequest
		if err.Error() == "system prompt not allowed" {
			status = http.StatusForbidden
		}
		writeJSON(w, status, errorResponse{Error: err.Error()})
		return
	}
	for i := range req.Files {
		req.Files[i].TenantID = scope.TenantID
		req.Files[i].UserID = scope.UserID
	}
	session.SetModel(req.Model)
	session.SetProvider(req.Provider)
	session.SetSystemPrompt(req.SystemPrompt)
	// Persist the current UI param overrides on the conversation so they can be
	// restored when the conversation is loaded again. Nil means "use config defaults".
	var convParams *storage.UsedParams
	if req.Params.Temperature != nil || req.Params.MaxTokens != 0 || req.Params.TopP != nil || req.Params.TopK != 0 {
		convParams = &storage.UsedParams{
			Temperature: req.Params.Temperature,
			MaxTokens:   req.Params.MaxTokens,
			TopP:        req.Params.TopP,
			TopK:        req.Params.TopK,
		}
	}
	session.SetParams(convParams)
	userMsgID := session.Add(llm.RoleUser, req.Message, req.Files)
	compactSummary := h.maybeAutoCompact(r.Context(), principal, session)

	reply, finalMsg, model, providerUsed, llmCalls, toolCalls, trace, usedParams, err := h.runLLM(r.Context(), principal, req.SessionID, session, req.Model, req.Provider, req.Params, req.Files)
	if err != nil {
		h.log.Error("llm call failed", zap.String("session_id", req.SessionID), zap.Error(err))
		errorMsgID := session.AddErrorMessage(err.Error(), model, providerUsed)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error(), Model: model, Provider: providerUsed, ErrorMsgID: errorMsgID})
		return
	}

	timeTaken := time.Since(start).Milliseconds()
	assistantMsgID := session.AddFinalMessage(finalMsg, model, providerUsed, timeTaken, llmCalls, toolCalls, trace, usedParams)
	h.log.Info("chat", zap.String("session_id", req.SessionID), zap.Int("history_len", len(session.History())), zap.Int64("time_ms", timeTaken), zap.Int("llm_calls", llmCalls), zap.Int("tool_calls", toolCalls), zap.String("model", model), zap.String("provider", providerUsed))
	if !principal.Policy.Permissions.TracesRead {
		trace = nil
		if compactSummary != nil {
			compactSummary.Trace = nil
		}
	}
	writeJSON(w, http.StatusOK, chatResponse{Reply: reply, Model: model, Provider: providerUsed, TimeTaken: timeTaken, LLMCalls: llmCalls, ToolCalls: toolCalls, UserMsgID: userMsgID, AssistantMsgID: assistantMsgID, Trace: trace, UsedParams: usedParams, CompactSummary: compactSummary})
}

func (h *Handler) Reset(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.Chat {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "chat not allowed"})
		return
	}
	var req struct {
		SessionID string `json:"session_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.SessionID == "" {
		req.SessionID = "default"
	}
	h.store.Get(requestScope(r), req.SessionID).Reset()
	h.log.Info("session reset", zap.String("session_id", req.SessionID))
	w.WriteHeader(http.StatusNoContent)
}

// ServeUI is an SPA-aware static file handler.
// Known assets (anything with a real file extension) are served directly.
// All other paths fall back to index.html so client-side routing works.
func (h *Handler) ServeUI(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/")

	// Try to open the requested path in the embedded FS.
	f, err := h.staticFS.Open(path)
	if err == nil {
		f.Close()
		// File exists — serve it directly.
		http.FileServer(http.FS(h.staticFS)).ServeHTTP(w, r)
		return
	}

	// Unknown path → serve index.html (SPA fallback).
	index, err := h.staticFS.Open("index.html")
	if err != nil {
		http.Error(w, "ui not found", http.StatusNotFound)
		return
	}
	defer index.Close()

	seeker, ok := index.(io.ReadSeeker)
	if !ok {
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	http.ServeContent(w, r, "index.html", time.Time{}, seeker)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		// Headers already committed; log only.
		_ = err // caller's logger not available here — acceptable for this helper
	}
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var req struct {
		UserID   string `json:"user_id"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request body"})
		return
	}
	principal, err := h.authService.AuthenticatePassword(req.UserID, req.Password)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, errorResponse{Error: "invalid credentials"})
		return
	}
	if err := h.authService.IssueSessionCookie(w, principal); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to issue session"})
		return
	}
	writeJSON(w, http.StatusOK, h.authService.ToMeResponse(principal))
}

func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	h.authService.ClearSessionCookie(w)
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	principal, err := h.authService.AuthenticateRequest(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, errorResponse{Error: "unauthorized"})
		return
	}
	writeJSON(w, http.StatusOK, h.authService.ToMeResponse(principal))
}

func (h *Handler) UIConfig(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil {
		writeJSON(w, http.StatusUnauthorized, errorResponse{Error: "unauthorized"})
		return
	}
	cfg := h.uiConfig
	cfg.SystemPrompts = h.promptNamesForPolicy(principal.Policy)
	writeJSON(w, http.StatusOK, cfg)
}

func (h *Handler) ListModels(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil {
		writeJSON(w, http.StatusUnauthorized, errorResponse{Error: "unauthorized"})
		return
	}
	providerFilter := r.URL.Query().Get("provider")
	discover := r.URL.Query().Get("discover") == "true"
	if discover {
		h.providers.mu.RLock()
		var autoDiscoverNames []string
		for _, e := range h.providers.providers {
			if !e.AutoDiscover {
				continue
			}
			if providerFilter != "" && e.Name != providerFilter {
				continue
			}
			autoDiscoverNames = append(autoDiscoverNames, e.Name)
		}
		h.providers.mu.RUnlock()
		for _, name := range autoDiscoverNames {
			if err := h.DiscoverAndUpdateModels(r.Context(), name); err != nil {
				http.Error(w, fmt.Sprintf("discover failed for %q: %v", name, err), http.StatusInternalServerError)
				return
			}
		}
	}

	var models []ModelInfo
	if providerFilter != "" {
		models = h.providers.ModelsByProvider(providerFilter)
	} else {
		models = h.providers.AllModels()
	}
	filteredModels := make([]ModelInfo, 0, len(models))
	for _, model := range models {
		if principal.Policy.AllowModel(model.Provider, model.ID) {
			filteredModels = append(filteredModels, model)
		}
	}
	providerInfos := h.providers.GetProviderInfos()
	providerCounts := make(map[string]int)
	for _, model := range filteredModels {
		providerCounts[model.Provider]++
	}
	filteredProviders := make([]ProviderInfo, 0, len(providerInfos))
	for _, provider := range providerInfos {
		if providerCounts[provider.Name] == 0 {
			continue
		}
		provider.Count = providerCounts[provider.Name]
		filteredProviders = append(filteredProviders, provider)
	}

	sources := make(map[string]bool)
	for _, p := range providerInfos {
		if p.Source != "" {
			sources[p.Source] = true
		}
	}
	overallSource := "static"
	if len(sources) > 1 {
		overallSource = "mixed"
	} else if sources["discovered"] {
		overallSource = "discovered"
	}

	resp := map[string]any{
		"models":           filteredModels,
		"providers":        filteredProviders,
		"selection_method": "round_robin",
		"source":           overallSource,
		"count":            len(filteredModels),
		"updated_at":       time.Now().Format(time.RFC3339),
		"global_params":    LLMParams{},
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) DiscoverAndUpdateModels(ctx context.Context, providerName string) error {
	h.providers.mu.RLock()
	entry, ok := h.providers.byName[providerName]
	h.providers.mu.RUnlock()
	if !ok {
		return fmt.Errorf("unknown provider %q", providerName)
	}

	resp, err := entry.Client.Models.List(ctx)
	if err != nil {
		return fmt.Errorf("list models for provider %q: %w", providerName, err)
	}

	staticByID := make(map[string]ModelInfo, len(entry.StaticModels))
	infos := make([]ModelInfo, 0, len(entry.StaticModels)+len(resp.Data))
	for _, m := range entry.StaticModels {
		staticByID[m.ID] = m
		infos = append(infos, m)
	}
	seen := make(map[string]bool, len(entry.StaticModels)+len(resp.Data))
	for _, m := range infos {
		seen[m.ID] = true
	}
	for _, md := range resp.Data {
		if seen[md.ID] {
			continue
		}
		if sm, ok2 := staticByID[md.ID]; ok2 {
			infos = append(infos, sm)
		} else {
			infos = append(infos, ModelInfo{ID: md.ID, Provider: providerName, Params: entry.GlobalParams})
		}
		seen[md.ID] = true
	}

	entry.ModelSelector.UpdateModels(infos)
	h.providers.UpdateModelMap()
	h.log.Info("models updated from provider", zap.String("provider", providerName), zap.Int("count", len(infos)))
	return nil
}

func (h *Handler) StartAutoDiscover(ctx context.Context, providerName string, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := h.DiscoverAndUpdateModels(ctx, providerName); err != nil {
				h.log.Warn("autodiscover tick failed", zap.String("provider", providerName), zap.Error(err))
			}
		}
	}
}

// ListTools returns all registered tools with their name and description.
func (h *Handler) ListTools(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil {
		writeJSON(w, http.StatusUnauthorized, errorResponse{Error: "unauthorized"})
		return
	}
	if h.registry == nil {
		writeJSON(w, http.StatusOK, map[string]any{"tools": []any{}})
		return
	}
	allowedTools := principal.Policy.FilterAllowedToolNames(h.registry.Names())
	writeJSON(w, http.StatusOK, map[string]any{"tools": h.registry.ListByNames(allowedTools)})
}

func (h *Handler) Upload(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.Upload {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "upload not allowed"})
		return
	}
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "failed to parse form"})
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "no file uploaded"})
		return
	}
	defer file.Close()

	// Use a UUID as the stored filename to avoid path traversal and name collisions.
	// The original filename is preserved only in the response metadata.
	scope := requestScope(r)
	uploadDir := h.uploadDir(scope)
	if err := os.MkdirAll(uploadDir, 0o755); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to save file"})
		return
	}
	fileID := uuid.New().String()
	filePath := filepath.Join(uploadDir, fileID)

	data, err := io.ReadAll(file)
	if err != nil {
		h.log.Error("failed to read uploaded file", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to save file"})
		return
	}
	out, err := os.Create(filePath)
	if err != nil {
		h.log.Error("failed to create file", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to save file"})
		return
	}
	defer out.Close()

	if _, err := out.Write(data); err != nil {
		h.log.Error("failed to write file", zap.Error(err))
		if removeErr := os.Remove(filePath); removeErr != nil {
			h.log.Warn("failed to clean up partial upload", zap.String("path", filePath), zap.Error(removeErr))
		}
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to save file"})
		return
	}

	uploadedFile := storage.UploadedFile{
		ID:          fileID,
		Filename:    header.Filename,
		Size:        int64(len(data)),
		ContentType: detectFileContentType(storage.UploadedFile{Filename: header.Filename}, data),
		SHA256:      fileSHA256(data),
		URL:         "/api/files/" + fileID,
		CreatedAt:   time.Now().UnixMilli(),
		TenantID:    scope.TenantID,
		UserID:      scope.UserID,
	}

	h.log.Info("file uploaded", zap.String("filename", header.Filename), zap.String("id", fileID))
	writeJSON(w, http.StatusOK, uploadedFile)
}

func (h *Handler) ServeFile(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.Upload {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	fileID := strings.TrimPrefix(r.URL.Path, "/api/files/")
	if fileID == "" {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	scope := requestScope(r)
	uploadDir := h.uploadDir(scope)
	filePath := filepath.Join(uploadDir, fileID)
	if !isUnderDir(filePath, uploadDir) {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	http.ServeFile(w, r, filePath)
}

func (h *Handler) DeleteFile(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.Upload {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "upload not allowed"})
		return
	}
	fileID := strings.TrimPrefix(r.URL.Path, "/api/files/")
	if fileID == "" {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	scope := requestScope(r)
	uploadDir := h.uploadDir(scope)
	filePath := filepath.Join(uploadDir, fileID)
	if !isUnderDir(filePath, uploadDir) {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	if err := os.Remove(filePath); err != nil {
		h.log.Warn("failed to delete file", zap.String("file_id", fileID), zap.Error(err))
		http.Error(w, "failed to delete file", http.StatusInternalServerError)
		return
	}

	h.log.Info("file deleted", zap.String("file_id", fileID))
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// isUnderDir reports whether path is inside (or equal to) dir after cleaning both.
func isUnderDir(path, dir string) bool {
	cleanPath := filepath.Clean(path)
	cleanDir := filepath.Clean(dir)
	return strings.HasPrefix(cleanPath, cleanDir+string(os.PathSeparator)) || cleanPath == cleanDir
}

// ListConversations returns all conversations (without messages) ordered newest-first.
func (h *Handler) ListConversations(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.ConversationsRead {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "conversation access not allowed"})
		return
	}
	if h.storageStore == nil {
		writeJSON(w, http.StatusOK, []*storage.Conversation{})
		return
	}
	convs, err := h.storageStore.List(requestScope(r))
	if err != nil {
		h.log.Error("failed to list conversations", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to list conversations"})
		return
	}
	writeJSON(w, http.StatusOK, convs)
}

// GetConversation returns a single conversation including full message history.
func (h *Handler) GetConversation(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.ConversationsRead {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "conversation access not allowed"})
		return
	}
	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id"})
		return
	}
	if h.storageStore == nil {
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "not found"})
		return
	}
	conv, err := h.storageStore.Load(requestScope(r), id)
	if err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "not found"})
		} else {
			h.log.Error("failed to load conversation", zap.String("id", id), zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to load conversation"})
		}
		return
	}
	if !principal.Policy.Permissions.TracesRead {
		writeJSON(w, http.StatusOK, stripConversationTrace(conv))
		return
	}
	writeJSON(w, http.StatusOK, conv)
}

func (h *Handler) CompactConversation(w http.ResponseWriter, r *http.Request) {
	if !h.compactConfig.Enabled {
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "compact conversation disabled"})
		return
	}
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.CompactConversationWrite {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "compact conversation not allowed"})
		return
	}
	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id"})
		return
	}
	var req compactConversationRequest
	if r.Body != nil {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
			writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request body"})
			return
		}
	}
	if req.Model != "" {
		modelID, _, providerUsed, _ := h.resolveAllowedModel(principal, req.Model, "")
		if modelID == "" || providerUsed == "" || !principal.Policy.AllowModel(providerUsed, modelID) {
			writeJSON(w, http.StatusForbidden, errorResponse{Error: "compact model not allowed"})
			return
		}
	}
	session := h.store.Get(requestScope(r), id)
	msg, err := h.compactConversation(r.Context(), principal, session, req.Prompt, req.Model, false)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: err.Error()})
		return
	}
	if !principal.Policy.Permissions.TracesRead && msg != nil {
		msg.Trace = nil
	}
	writeJSON(w, http.StatusOK, msg)
}

// DeleteConversation removes a conversation from storage and evicts it from the in-memory cache.
func (h *Handler) DeleteConversation(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.ConversationsWrite {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "conversation write not allowed"})
		return
	}
	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id"})
		return
	}
	scope := requestScope(r)
	var filesToDelete []storage.UploadedFile
	if h.storageStore != nil {
		if conv, err := h.storageStore.Load(scope, id); err == nil {
			filesToDelete = collectFiles(conv.Messages)
		} else if !errors.Is(err, storage.ErrNotFound) {
			h.log.Error("failed to load conversation before delete", zap.String("id", id), zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to delete conversation"})
			return
		}
	}
	if err := h.store.Delete(scope, id); err != nil {
		h.log.Error("failed to delete conversation", zap.String("id", id), zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to delete conversation"})
		return
	}
	h.removeUploadedFiles(filesToDelete)
	h.log.Info("conversation deleted", zap.String("id", id))
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// DeleteMessage removes a single message from a conversation.
func (h *Handler) DeleteMessage(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.ConversationsWrite {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "conversation write not allowed"})
		return
	}
	convID := r.PathValue("id")
	msgID := r.PathValue("msgId")
	if convID == "" || msgID == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id or message id"})
		return
	}
	scope := requestScope(r)
	var filesToDelete []storage.UploadedFile
	if h.storageStore != nil {
		conv, err := h.storageStore.Load(scope, convID)
		if err != nil {
			if errors.Is(err, storage.ErrNotFound) {
				writeJSON(w, http.StatusNotFound, errorResponse{Error: "message not found"})
				return
			}
			h.log.Error("failed to load conversation before message delete", zap.String("conv_id", convID), zap.String("msg_id", msgID), zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to delete message"})
			return
		}
		found := false
		for _, msg := range conv.Messages {
			if msg.ID == msgID {
				filesToDelete = collectFiles([]storage.Message{msg})
				found = true
				break
			}
		}
		if !found {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "message not found"})
			return
		}
	}
	if err := h.store.DeleteMessage(scope, convID, msgID); err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "message not found"})
		} else {
			h.log.Error("failed to delete message", zap.String("conv_id", convID), zap.String("msg_id", msgID), zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to delete message"})
		}
		return
	}
	if h.storageStore != nil {
		if conv, err := h.storageStore.Load(scope, convID); err == nil {
			filesToDelete = excludeFiles(filesToDelete, collectFiles(conv.Messages))
		}
	}
	h.removeUploadedFiles(filesToDelete)
	h.log.Info("message deleted", zap.String("conv_id", convID), zap.String("msg_id", msgID))
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// DeleteMessagesFrom removes a message and all messages after it from a conversation.
// Used when a user edits a message — all subsequent turns are discarded.
func (h *Handler) DeleteMessagesFrom(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.ConversationsWrite {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "conversation write not allowed"})
		return
	}
	convID := r.PathValue("id")
	msgID := r.PathValue("msgId")
	if convID == "" || msgID == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id or message id"})
		return
	}
	scope := requestScope(r)
	var filesToDelete []storage.UploadedFile
	if h.storageStore != nil {
		conv, err := h.storageStore.Load(scope, convID)
		if err != nil {
			if errors.Is(err, storage.ErrNotFound) {
				writeJSON(w, http.StatusNotFound, errorResponse{Error: "message not found"})
				return
			}
			h.log.Error("failed to load conversation before truncation", zap.String("conv_id", convID), zap.String("msg_id", msgID), zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to truncate messages"})
			return
		}
		filesToDelete, err = filesForDeletedSuffix(conv.Messages, msgID)
		if err != nil {
			if errors.Is(err, storage.ErrNotFound) {
				writeJSON(w, http.StatusNotFound, errorResponse{Error: "message not found"})
				return
			}
			h.log.Error("failed to collect attachments for truncation", zap.String("conv_id", convID), zap.String("msg_id", msgID), zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to truncate messages"})
			return
		}
	}
	if err := h.store.DeleteMessagesFrom(scope, convID, msgID); err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "message not found"})
		} else {
			h.log.Error("failed to truncate messages", zap.String("conv_id", convID), zap.String("msg_id", msgID), zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to truncate messages"})
		}
		return
	}
	if h.storageStore != nil {
		if conv, err := h.storageStore.Load(scope, convID); err == nil {
			filesToDelete = excludeFiles(filesToDelete, collectFiles(conv.Messages))
		}
	}
	h.removeUploadedFiles(filesToDelete)
	h.log.Info("messages truncated from", zap.String("conv_id", convID), zap.String("msg_id", msgID))
	writeJSON(w, http.StatusOK, map[string]string{"status": "truncated"})
}

// RenameConversation updates the title of a conversation.
func (h *Handler) RenameConversation(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.ConversationsWrite {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "conversation write not allowed"})
		return
	}
	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id"})
		return
	}
	var body struct {
		Title string `json:"title"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request body"})
		return
	}
	if err := h.store.RenameTitle(requestScope(r), id, body.Title); err != nil {
		h.log.Error("failed to rename conversation", zap.String("id", id), zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to rename conversation"})
		return
	}
	h.log.Info("conversation renamed", zap.String("id", id), zap.String("title", body.Title))
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// TogglePinConversation flips the pinned state of a conversation.
func (h *Handler) TogglePinConversation(w http.ResponseWriter, r *http.Request) {
	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.ConversationsWrite {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "conversation write not allowed"})
		return
	}
	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id"})
		return
	}
	pinned, err := h.store.TogglePin(requestScope(r), id)
	if err != nil {
		h.log.Error("failed to toggle pin", zap.String("id", id), zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to toggle pin"})
		return
	}
	h.log.Info("conversation pin toggled", zap.String("id", id), zap.Bool("pinned", pinned))
	writeJSON(w, http.StatusOK, map[string]bool{"pinned": pinned})
}
