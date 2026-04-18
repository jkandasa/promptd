import type {
  ToolInfo, UIConfig, ConversationMeta, ConversationDetail,
  LLMParamsOverride, UploadedFile, LLMRound, UsedParams,
} from '../types/chat'

export type ChatResponse = {
  reply: string
  model: string
  provider?: string
  time_taken_ms: number
  llm_calls: number
  tool_calls: number
  files?: UploadedFile[]
  user_msg_id?: string
  assistant_msg_id?: string
  trace?: LLMRound[]
  used_params?: UsedParams
}

export class ChatError extends Error {
  model?: string
  provider?: string
  constructor(message: string, model?: string, provider?: string) {
    super(message)
    this.name = 'ChatError'
    this.model = model
    this.provider = provider
  }
}

export interface ModelInfo {
  id: string
  name?: string
  provider?: string
  source?: 'static' | 'discovered'
  is_manual?: boolean
  params?: {
    temperature?: number
    max_tokens?: number
    top_p?: number
    top_k?: number
  }
}

export interface ProviderInfo {
  name: string
  source?: string
  count: number
  updated_at?: string
  refresh_interval?: string
}

export interface ModelData {
  models: ModelInfo[]
  providers?: ProviderInfo[]
  selection_method: string
  source?: string
  count: number
  updated_at?: string
  refresh_interval?: string
  global_params?: {
    temperature?: number
    max_tokens?: number
    top_p?: number
    top_k?: number
  }
}

export async function apiListTools(): Promise<ToolInfo[]> {
  const res = await fetch('/tools')
  if (!res.ok) return []
  const data: { tools: { name: string; description: string; parameters?: any }[] } = await res.json()
  return data.tools?.map((t) => ({ name: t.name, description: t.description, parameters: t.parameters })) ?? []
}

export async function apiGetUIConfig(): Promise<UIConfig> {
  const res = await fetch('/ui-config')
  if (!res.ok) return {}
  return res.json()
}

export async function apiGetModels(provider?: string, discover = false): Promise<ModelData> {
  const params = new URLSearchParams()
  if (provider) params.set('provider', provider)
  if (discover) params.set('discover', 'true')
  const url = params.size > 0 ? `/models?${params.toString()}` : '/models'
  const res = await fetch(url)
  if (!res.ok) return { models: [], selection_method: 'auto', count: 0 }
  return res.json()
}

export async function apiChat(
  sessionId: string,
  message: string,
  files?: string[],
  model?: string,
  systemPrompt?: string,
  params?: LLMParamsOverride,
  provider?: string,
): Promise<ChatResponse> {
  const res = await fetch('/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ session_id: sessionId, message, files, model, provider: provider || undefined, system_prompt: systemPrompt, params }),
  })
  const data = await res.json()
  if (!res.ok) throw new ChatError(data.error || 'Request failed', data.model, data.provider)
  return data as ChatResponse
}

export async function apiUploadFile(file: File): Promise<UploadedFile> {
  const formData = new FormData()
  formData.append('file', file)
  const res = await fetch('/upload', { method: 'POST', body: formData })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'Upload failed')
  return data as UploadedFile
}

export async function apiListConversations(): Promise<ConversationMeta[]> {
  const res = await fetch('/conversations')
  if (!res.ok) return []
  return res.json()
}

export async function apiLoadConversation(id: string): Promise<ConversationDetail | null> {
  const res = await fetch(`/conversations/${id}`)
  if (!res.ok) return null
  return res.json()
}

export async function apiDeleteConversation(id: string): Promise<void> {
  await fetch(`/conversations/${id}`, { method: 'DELETE' })
}

export async function apiRenameConversation(id: string, title: string): Promise<void> {
  await fetch(`/conversations/${id}/title`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title }),
  })
}

export async function apiTogglePin(id: string): Promise<boolean> {
  const res = await fetch(`/conversations/${id}/pin`, { method: 'PATCH' })
  const data = await res.json()
  return data.pinned as boolean
}

export async function apiDeleteMessage(convId: string, msgId: string): Promise<void> {
  await fetch(`/conversations/${convId}/messages/${msgId}`, { method: 'DELETE' })
}

export async function apiDeleteMessagesFrom(convId: string, msgId: string): Promise<void> {
  await fetch(`/conversations/${convId}/messages/${msgId}/after`, { method: 'DELETE' })
}
