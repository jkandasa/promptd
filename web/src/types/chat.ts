// Domain types shared across the app

export type Role = 'user' | 'assistant' | 'error'

export interface UploadedFile {
  id: string
  filename: string
  size: number
  url: string
  created_at: number
}

export interface TraceToolCall {
  id: string
  name: string
  args: string
}

export interface TraceMessage {
  role: string
  content?: string
  refusal?: string
  reasoning_content?: string
  name?: string
  tool_call_id?: string
  tool_calls?: TraceToolCall[]
}

export interface ToolResult {
  name: string
  args: string
  result: string
  duration_ms: number
}

export interface TraceToolDef {
  name: string
  description: string
}

export interface TokenUsage {
  prompt_tokens: number
  completion_tokens: number
  total_tokens: number
  reasoning_tokens?: number
  cached_tokens?: number
}

export interface LLMRound {
  request: TraceMessage[]
  response: TraceMessage
  llm_duration_ms: number
  tool_results?: ToolResult[]
  available_tools?: (TraceToolDef & { parameters?: any })[]
  usage?: TokenUsage
}

export interface LLMParamsOverride {
  temperature?: number
  max_tokens?: number
  top_p?: number
  top_k?: number
}

export interface UsedParams {
  temperature?: number
  max_tokens?: number
  top_p?: number
  top_k?: number
}

export interface Message {
  id: string
  role: Role
  content: string
  compactSummary?: boolean
  ts: Date
  timeTaken?: number
  llmCalls?: number
  toolCalls?: number
  model?: string
  provider?: string
  files?: UploadedFile[]
  msgId?: string
  trace?: LLMRound[]
  usedParams?: UsedParams
}

export interface ToolInfo {
  name: string
  description: string
  parameters?: any
}

export interface SystemPrompt {
  name: string
}

export interface UIConfig {
  welcomeTitle?: string
  aiDisclaimer?: string
  promptSuggestions?: string[]
  systemPrompts?: SystemPrompt[]
  compactConversation?: {
    enabled?: boolean
    defaultPrompt?: string
    afterMessages?: number
    afterTokens?: number
  }
}

export interface ConversationMeta {
  id: string
  title: string
  model: string
  provider?: string
  system_prompt?: string
  params?: LLMParamsOverride
  pinned?: boolean
  compacted_through_message_id?: string
  compact_summary_message_id?: string
  created_at: string
  updated_at: string
}

export interface StorageMessage {
  id: string
  role: string
  content: string
  sent_at: string
  compact_summary?: boolean
  files?: UploadedFile[]
  model?: string
  provider?: string
  time_taken_ms?: number
  llm_calls?: number
  tool_calls?: number
  trace?: LLMRound[]
  used_params?: UsedParams
}

export interface ConversationDetail extends ConversationMeta {
  messages: StorageMessage[]
}

export function getFirstSystemPromptName(cfg: UIConfig): string {
  return getSortedSystemPrompts(cfg)[0]?.name || ''
}

export function getSortedSystemPrompts(cfg: UIConfig): SystemPrompt[] {
  return [...(cfg.systemPrompts || [])].sort((a, b) => a.name.localeCompare(b.name))
}

export function isKnownSystemPrompt(cfg: UIConfig, name?: string): boolean {
  if (!name) return false
  return getSortedSystemPrompts(cfg).some((prompt) => prompt.name === name)
}
