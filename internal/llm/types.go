package llm

const (
	RoleSystem    = "system"
	RoleUser      = "user"
	RoleAssistant = "assistant"
	RoleTool      = "tool"

	ToolTypeFunction      = "function"
	FinishReasonToolCalls = "tool_calls"
	ImageURLDetailAuto    = "auto"
)

type FunctionCall struct {
	Name      string `json:"name,omitempty"`
	Arguments string `json:"arguments,omitempty"`
}

type ToolCall struct {
	ID       string       `json:"id,omitempty"`
	Type     string       `json:"type,omitempty"`
	Function FunctionCall `json:"function,omitempty"`
}

type ImageURL struct {
	URL    string `json:"url,omitempty"`
	Detail string `json:"detail,omitempty"`
}

type MessagePart struct {
	Type     string    `json:"type,omitempty"`
	Text     string    `json:"text,omitempty"`
	ImageURL *ImageURL `json:"image_url,omitempty"`
}

type Message struct {
	Role             string        `json:"role,omitempty"`
	Content          string        `json:"content,omitempty"`
	Refusal          string        `json:"refusal,omitempty"`
	ReasoningContent string        `json:"reasoning_content,omitempty"`
	Name             string        `json:"name,omitempty"`
	ToolCallID       string        `json:"tool_call_id,omitempty"`
	ToolCalls        []ToolCall    `json:"tool_calls,omitempty"`
	MultiContent     []MessagePart `json:"-"`
}

type FunctionDefinition struct {
	Name        string `json:"name,omitempty"`
	Description string `json:"description,omitempty"`
	Parameters  any    `json:"parameters,omitempty"`
}

type Tool struct {
	Type     string              `json:"type,omitempty"`
	Function *FunctionDefinition `json:"function,omitempty"`
}

type TokenDetails struct {
	ReasoningTokens int `json:"reasoning_tokens,omitempty"`
	CachedTokens    int `json:"cached_tokens,omitempty"`
}

type Usage struct {
	PromptTokens            int           `json:"prompt_tokens,omitempty"`
	CompletionTokens        int           `json:"completion_tokens,omitempty"`
	TotalTokens             int           `json:"total_tokens,omitempty"`
	CompletionTokensDetails *TokenDetails `json:"completion_tokens_details,omitempty"`
	PromptTokensDetails     *TokenDetails `json:"prompt_tokens_details,omitempty"`
}

type ChatCompletionChoice struct {
	FinishReason string  `json:"finish_reason,omitempty"`
	Index        int64   `json:"index,omitempty"`
	Message      Message `json:"message,omitempty"`
}

type ChatCompletionResponse struct {
	ID      string                 `json:"id,omitempty"`
	Choices []ChatCompletionChoice `json:"choices,omitempty"`
	Model   string                 `json:"model,omitempty"`
	Usage   Usage                  `json:"usage,omitempty"`
}
