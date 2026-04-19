import './ChatPage.scss'

import {
  App as AntApp,
  Button,
  Divider,
  Empty,
  Layout,
  Modal,
  Select,
  Spin,
  Tag,
  Tooltip,
  Typography,
  theme,
} from 'antd'
import {
  ChatError,
  apiChat,
  apiCompactConversation,
  apiDeleteConversation,
  apiDeleteFile,
  apiDeleteMessage,
  apiDeleteMessagesFrom,
  apiGetModels,
  apiListConversations,
  apiLoadConversation,
  apiRenameConversation,
  apiTogglePin,
  apiUploadFile,
} from '../../api/client'
import type { ConversationMeta, LLMParamsOverride, Message, UIConfig } from '../../types/chat'
import {
  CompressOutlined,
  DownOutlined,
  FileOutlined,
  MenuFoldOutlined,
  MenuUnfoldOutlined,
  PaperClipOutlined,
  PlusOutlined,
  ReloadOutlined,
  SendOutlined,
} from '@ant-design/icons'
import { MAX_FILES_PER_MESSAGE, MAX_FILE_SIZE, MAX_MESSAGE_LENGTH, uid } from '../../utils/helpers'
import type { ModelData, ModelInfo, ProviderInfo } from '../../api/client'
import type { Role, UploadedFile } from '../../types/chat'
import { getFirstSystemPromptName, getSortedSystemPrompts, isKnownSystemPrompt } from '../../types/chat'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import promptdLogo from '../../promptd-logo.svg'

import { Bubble } from '../../components/Bubble'
import { ConvItem } from '../../components/ConvItem'
import { Input } from 'antd'
import { LLMParamsPopover } from '../../components/LLMParamsPopover'
import type { TextAreaRef } from 'antd/es/input/TextArea'
import { TypingIndicator } from '../../components/TypingIndicator'

const { Sider, Content } = Layout
const { Text } = Typography
const { TextArea } = Input
const { useToken } = theme

const CHAT_PROVIDER_STORAGE_KEY = 'promptd.chat.selectedProvider'
const CHAT_MODEL_STORAGE_KEY = 'promptd.chat.selectedModel'
const CHAT_SYSTEM_PROMPT_STORAGE_KEY = 'promptd.chat.selectedSystemPrompt'

interface ChatPageProps {
  models: ModelInfo[]
  modelData: { source?: string; count: number; updated_at?: string; refresh_interval?: string; global_params?: ModelData['global_params']; providers?: ProviderInfo[] }
  uiConfig: UIConfig
  isDark: boolean
  canCompactConversation: boolean
  siderCollapsed: boolean
  setSiderCollapsed: (collapsed: boolean) => void
  onRefreshModels: (provider?: string) => Promise<void>
  selectedConversationId?: string | null
  onConversationChange?: (id: string | null) => void
}

export function ChatPage({ models, modelData, uiConfig, isDark, canCompactConversation, siderCollapsed, setSiderCollapsed, onRefreshModels, selectedConversationId, onConversationChange }: ChatPageProps) {
  const { token } = useToken()
  const { message: antMessage } = AntApp.useApp()
  const initialStoredProvider = typeof window !== 'undefined' ? window.localStorage.getItem(CHAT_PROVIDER_STORAGE_KEY) ?? '' : ''
  const initialStoredModel = typeof window !== 'undefined' ? window.localStorage.getItem(CHAT_MODEL_STORAGE_KEY) ?? '' : ''
  const initialStoredSystemPrompt = typeof window !== 'undefined' ? window.localStorage.getItem(CHAT_SYSTEM_PROMPT_STORAGE_KEY) ?? '' : ''

  const [sessionId, setSessionId] = useState<string | null>(selectedConversationId ?? null)
  const [messages, setMessages] = useState<Message[]>([])
  const messagesRef = useRef<Message[]>([])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const loadingRef = useRef(false)
  const [selectedModel, setSelectedModel] = useState<string>(initialStoredModel)
  const [selectedProvider, setSelectedProvider] = useState<string>(initialStoredProvider)
  const [providerModels, setProviderModels] = useState<ModelInfo[]>([])
  const [loadingProviderModels, setLoadingProviderModels] = useState(false)
  const [selectedSystemPrompt, setSelectedSystemPrompt] = useState<string>(initialStoredSystemPrompt)
  const [llmParams, setLlmParams] = useState<LLMParamsOverride>({})
  const llmParamsRef = useRef<LLMParamsOverride>({})
  const pendingParamsRef = useRef<LLMParamsOverride | null>(null)

  const [uploadedFiles, setUploadedFiles] = useState<UploadedFile[]>([])
  const [uploading, setUploading] = useState(false)
  const [compactModalOpen, setCompactModalOpen] = useState(false)
  const [compactPrompt, setCompactPrompt] = useState(uiConfig.compactConversation?.defaultPrompt ?? '')
  const [compactModel, setCompactModel] = useState('')
  const [compacting, setCompacting] = useState(false)

  const [conversations, setConversations] = useState<ConversationMeta[]>([])
  const [convsLoading, setConvsLoading] = useState(false)
  const [loadingConversation, setLoadingConversation] = useState(false)
  const [conversationSearch, setConversationSearch] = useState('')
  const [editingConvId, setEditingConvId] = useState<string | null>(null)
  const [editingTitle, setEditingTitle] = useState('')

  useEffect(() => {
    setCompactPrompt(uiConfig.compactConversation?.defaultPrompt ?? '')
  }, [uiConfig.compactConversation?.defaultPrompt])

  const bottomRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<TextAreaRef>(null)
  const contentRef = useRef<HTMLDivElement>(null)
  const [showScrollBtn, setShowScrollBtn] = useState(false)
  const conversationLoadSeqRef = useRef(0)
  const loadingConversationIdRef = useRef<string | null>(null)
  const loadedConversationIdRef = useRef<string | null>(null)
  const uploadedFilesRef = useRef(uploadedFiles)

  const discardUploadedFiles = useCallback((files: UploadedFile[]) => {
    if (files.length === 0) return
    for (const file of files) {
      void apiDeleteFile(file.id).catch(() => {})
    }
  }, [])

  const lastMsgId = messages.length > 0 ? messages[messages.length - 1].id : null
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [lastMsgId, loading])

  useEffect(() => {
    const el = contentRef.current
    if (!el) return
    const onScroll = () => {
      const threshold = 200
      setShowScrollBtn(el.scrollHeight - el.scrollTop - el.clientHeight > threshold)
    }
    el.addEventListener('scroll', onScroll, { passive: true })
    return () => el.removeEventListener('scroll', onScroll)
  }, [])

  const refreshConversations = useCallback(async () => {
    setConvsLoading(true)
    try {
      const list = await apiListConversations()
      setConversations(list ?? [])
    } catch {
      // silently ignore
    } finally {
      setConvsLoading(false)
    }
  }, [])

  useEffect(() => {
    refreshConversations()
  }, [refreshConversations])

  const handleNewChat = useCallback(() => {
    discardUploadedFiles(uploadedFilesRef.current)
    setLoadingConversation(false)
    loadingConversationIdRef.current = null
    loadedConversationIdRef.current = null
    onConversationChange?.(null)
  }, [discardUploadedFiles, onConversationChange])

  const handleLoadConversation = useCallback(async (id: string, silent = false, navigateToConversation = true) => {
    loadingConversationIdRef.current = id
    setSessionId(id)
    if (navigateToConversation) onConversationChange?.(id)
    setLoadingConversation(true)
    setInput('')
    discardUploadedFiles(uploadedFilesRef.current)
    setUploadedFiles([])
    setMessages([])

    const requestSeq = ++conversationLoadSeqRef.current
    try {
      const detail = await apiLoadConversation(id)
      if (conversationLoadSeqRef.current !== requestSeq) return
      if (!detail) {
        if (!silent) antMessage.error('Failed to load conversation')
        return
      }
      const uiMsgs: Message[] = detail.messages
        .filter((m) => m.role === 'user' || m.role === 'assistant' || m.role === 'error')
        .map((m) => ({
          id: uid(),
          role: m.role as Role,
          content: m.content,
          files: m.files,
          ts: m.sent_at ? new Date(m.sent_at) : new Date(detail.updated_at),
          provider: m.provider,
          model: m.model,
          timeTaken: m.time_taken_ms,
          llmCalls: m.llm_calls,
          toolCalls: m.tool_calls,
          msgId: m.id,
          trace: m.trace,
          usedParams: m.used_params,
          compactSummary: m.compact_summary,
        }))
      setMessages(uiMsgs)
      const nextProvider = detail.provider || ''
      const nextModel = nextProvider ? detail.model || '' : ''
      if (detail.params && Object.keys(detail.params).length > 0) {
        pendingParamsRef.current = detail.params
      } else {
        pendingParamsRef.current = null
      }
      setSelectedModel(nextModel)
      selectedModelRef.current = nextModel
      setSelectedProvider(nextProvider)
      selectedProviderRef.current = nextProvider
      const nextPrompt = detail.system_prompt || getFirstSystemPromptName(uiConfig)
      setSelectedSystemPrompt(nextPrompt)
      selectedSystemPromptRef.current = nextPrompt
      loadedConversationIdRef.current = id
    } finally {
      if (conversationLoadSeqRef.current === requestSeq) {
        loadingConversationIdRef.current = null
        setLoadingConversation(false)
      }
    }
  }, [antMessage, discardUploadedFiles, onConversationChange, uiConfig])

  const handleDeleteConversation = useCallback(async (id: string) => {
    await apiDeleteConversation(id)
    if (id === sessionIdRef.current) handleNewChat()
    refreshConversations()
  }, [handleNewChat, refreshConversations])

  const handleRenameConversation = useCallback(async (id: string, title: string) => {
    await apiRenameConversation(id, title)
    setConversations((prev) => prev.map((c) => c.id === id ? { ...c, title } : c))
  }, [])

  const handleTogglePin = useCallback(async (id: string) => {
    const pinned = await apiTogglePin(id)
    setConversations((prev) => {
      const updated = prev.map((c) => c.id === id ? { ...c, pinned } : c)
      return [
        ...updated.filter((c) => c.pinned),
        ...updated.filter((c) => !c.pinned),
      ]
    })
  }, [])

  const upsertCompactSummaryMessage = useCallback((summary: {
    id: string
    content: string
    sent_at: string
    compact_summary?: boolean
    model?: string
    provider?: string
    time_taken_ms?: number
    llm_calls?: number
    tool_calls?: number
    trace?: Message['trace']
  }) => {
    const nextMessage: Message = {
      id: uid(),
      role: 'assistant',
      compactSummary: true,
      content: summary.content,
      ts: summary.sent_at ? new Date(summary.sent_at) : new Date(),
      provider: summary.provider,
      model: summary.model,
      timeTaken: summary.time_taken_ms,
      llmCalls: summary.llm_calls,
      toolCalls: summary.tool_calls,
      msgId: summary.id,
      trace: summary.trace,
    }
    setMessages((prev) => {
      const withoutExisting = prev.filter((msg) => !msg.compactSummary)
      return [...withoutExisting, nextMessage]
    })
  }, [])

  const handleCompactConversation = useCallback(async () => {
    if (!sessionIdRef.current) return
    setCompacting(true)
    try {
      const summary = await apiCompactConversation(sessionIdRef.current, compactPrompt, compactModel)
      upsertCompactSummaryMessage(summary)
      setCompactModalOpen(false)
      refreshConversations()
    } catch (err) {
      antMessage.error(err instanceof Error ? err.message : 'Failed to compact conversation')
    } finally {
      setCompacting(false)
    }
  }, [antMessage, compactModel, compactPrompt, refreshConversations, upsertCompactSummaryMessage])

  useEffect(() => { messagesRef.current = messages }, [messages])

  const selectedModelRef = useRef(selectedModel)
  useEffect(() => { selectedModelRef.current = selectedModel }, [selectedModel])
  useEffect(() => {
    if (typeof window === 'undefined') return
    if (selectedModel) window.localStorage.setItem(CHAT_MODEL_STORAGE_KEY, selectedModel)
    else window.localStorage.removeItem(CHAT_MODEL_STORAGE_KEY)
  }, [selectedModel])

  const selectedProviderRef = useRef(selectedProvider)
  useEffect(() => { selectedProviderRef.current = selectedProvider }, [selectedProvider])
  useEffect(() => {
    if (typeof window === 'undefined') return
    if (selectedProvider) window.localStorage.setItem(CHAT_PROVIDER_STORAGE_KEY, selectedProvider)
    else window.localStorage.removeItem(CHAT_PROVIDER_STORAGE_KEY)
  }, [selectedProvider])

  const isMultiProvider = (modelData.providers?.length ?? 0) > 1
  const singleProvider = !isMultiProvider && (modelData.providers?.length ?? 0) === 1 ? modelData.providers?.[0]?.name ?? '' : ''
  const effectiveProvider = selectedProvider || singleProvider

  useEffect(() => {
    if (pendingParamsRef.current !== null) {
      const p = pendingParamsRef.current
      pendingParamsRef.current = null
      setLlmParams(p)
      llmParamsRef.current = p
      return
    }
    const gp = modelData.global_params
    const globalDefaults: LLMParamsOverride = {}
    if (gp) {
      if (gp.temperature != null) globalDefaults.temperature = gp.temperature
      if (gp.max_tokens)          globalDefaults.max_tokens  = gp.max_tokens
      if (gp.top_p != null)       globalDefaults.top_p       = gp.top_p
      if (gp.top_k)               globalDefaults.top_k       = gp.top_k
    }
    if (!selectedModel) {
      setLlmParams(globalDefaults)
      llmParamsRef.current = globalDefaults
      return
    }
    const candidateModels = effectiveProvider ? providerModels : []
    const m = candidateModels.find((m) => m.id === selectedModel)
    const p: LLMParamsOverride = { ...globalDefaults }
    if (m?.params) {
      if (m.params.temperature != null) p.temperature = m.params.temperature
      if (m.params.max_tokens)          p.max_tokens  = m.params.max_tokens
      if (m.params.top_p != null)       p.top_p       = m.params.top_p
      if (m.params.top_k)               p.top_k       = m.params.top_k
    }
    setLlmParams(p)
    llmParamsRef.current = p
  }, [selectedModel, effectiveProvider, providerModels, modelData.global_params])

  const selectedSystemPromptRef = useRef(selectedSystemPrompt)
  useEffect(() => { selectedSystemPromptRef.current = selectedSystemPrompt }, [selectedSystemPrompt])
  useEffect(() => {
    if (typeof window === 'undefined') return
    if (selectedSystemPrompt) window.localStorage.setItem(CHAT_SYSTEM_PROMPT_STORAGE_KEY, selectedSystemPrompt)
    else window.localStorage.removeItem(CHAT_SYSTEM_PROMPT_STORAGE_KEY)
  }, [selectedSystemPrompt])
  useEffect(() => { llmParamsRef.current = llmParams }, [llmParams])

  useEffect(() => { uploadedFilesRef.current = uploadedFiles }, [uploadedFiles])

  const sessionIdRef = useRef(sessionId)
  useEffect(() => { sessionIdRef.current = sessionId }, [sessionId])

  const resetDraftConversation = useCallback(() => {
    discardUploadedFiles(uploadedFilesRef.current)
    setSessionId(null)
    setMessages([])
    setInput('')
    setUploadedFiles([])
    pendingParamsRef.current = null
    loadingConversationIdRef.current = null
    loadedConversationIdRef.current = null
    const nextPrompt = selectedSystemPromptRef.current || getFirstSystemPromptName(uiConfig)
    setSelectedSystemPrompt(nextPrompt)
    selectedSystemPromptRef.current = nextPrompt
  }, [discardUploadedFiles, uiConfig])

  const removeUploadedFile = useCallback((fileId: string) => {
    setUploadedFiles((prev) => {
      const removed = prev.find((f) => f.id === fileId)
      const next = prev.filter((f) => f.id !== fileId)
      if (removed) {
        void apiDeleteFile(removed.id).catch(() => {})
      }
      return next
    })
  }, [])

  useEffect(() => {
    if (!selectedConversationId) {
      conversationLoadSeqRef.current += 1
      setLoadingConversation(false)
      resetDraftConversation()
      return
    }
    if (selectedConversationId === loadingConversationIdRef.current || selectedConversationId === loadedConversationIdRef.current) {
      setSessionId(selectedConversationId)
      return
    }
    setSessionId(selectedConversationId)
    void handleLoadConversation(selectedConversationId, true, false)
  }, [handleLoadConversation, resetDraftConversation, selectedConversationId])

  const send = useCallback(async (overrideText?: string) => {
    if (loadingRef.current) return
    if (!selectedSystemPromptRef.current) return
    const text = (overrideText ?? input).trim()
    if (!text && uploadedFilesRef.current.length === 0) return

    const files = uploadedFilesRef.current
    const currentSessionId = sessionIdRef.current || uid()
    if (!sessionIdRef.current) {
      setSessionId(currentSessionId)
      onConversationChange?.(currentSessionId)
    }
    setInput('')
    const userMsg: Message = { id: uid(), role: 'user', content: text, ts: new Date(), files }
    setMessages((prev) => [...prev, userMsg])
    setUploadedFiles([])
    setLoading(true)
    loadingRef.current = true

    try {
      const modelId = selectedModelRef.current
      const modelToSend = modelId || undefined
      const systemPromptToSend = selectedSystemPromptRef.current || undefined
      const providerToSend = selectedProviderRef.current || singleProvider || undefined
      const response = await apiChat(currentSessionId, text, files, modelToSend, systemPromptToSend, llmParamsRef.current, providerToSend)
      if (response.user_msg_id) {
        setMessages((prev) => prev.map((m) => m.id === userMsg.id ? { ...m, msgId: response.user_msg_id } : m))
      }
      if (response.compact_summary) {
        upsertCompactSummaryMessage(response.compact_summary)
      }
      const assistantMsg: Message = {
        id: uid(),
        role: 'assistant',
        content: response.reply,
        ts: new Date(),
        timeTaken: response.time_taken_ms,
        llmCalls: response.llm_calls,
        toolCalls: response.tool_calls,
        model: response.model,
        provider: response.provider,
        files: response.files,
        msgId: response.assistant_msg_id,
        trace: response.trace,
        usedParams: response.used_params,
      }
      setMessages((prev) => [...prev, assistantMsg])
      refreshConversations()
    } catch (err) {
      const serverModel = err instanceof ChatError ? err.model : undefined
      const serverProvider = err instanceof ChatError ? err.provider : undefined
      const requestedModel = selectedModelRef.current
      const requestedProvider = selectedProviderRef.current || singleProvider
      const errorModel = serverModel || requestedModel || 'unknown'
      const errMsg: Message = {
        id: uid(),
        role: 'error',
        content: err instanceof Error ? err.message : 'Something went wrong',
        ts: new Date(),
        model: errorModel,
        provider: serverProvider || requestedProvider || undefined,
        msgId: err instanceof ChatError ? err.errorMsgId : undefined,
      }
      setMessages((prev) => [...prev, errMsg])
    } finally {
      setLoading(false)
      loadingRef.current = false
      setTimeout(() => {
        const el = inputRef.current?.resizableTextArea?.textArea
        el?.focus()
      }, 0)
    }
  }, [input, onConversationChange, refreshConversations, singleProvider, upsertCompactSummaryMessage])

  const handleDeleteMessage = useCallback((id: string) => {
    setMessages((prev) => {
      const msg = prev.find((m) => m.id === id)
      if (msg?.msgId && sessionIdRef.current) {
        apiDeleteMessage(sessionIdRef.current, msg.msgId).catch(() => {})
      }
      return prev.filter((m) => m.id !== id)
    })
  }, [])

  const handleEditMessage = useCallback(async (id: string, newContent: string) => {
    const prev = messagesRef.current
    const idx = prev.findIndex((m) => m.id === id)
    if (idx < 0) return
    const msg = prev[idx]
    const convId = sessionIdRef.current
    if (!convId) return
    if (msg.msgId) {
      apiDeleteMessagesFrom(convId, msg.msgId).catch(() => {})
    }
    const truncated = prev.slice(0, idx)
    setMessages(truncated)
    messagesRef.current = truncated
    send(newContent)
  }, [send])

  const handleKeyDown = useCallback((e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey && !uploading) {
      e.preventDefault()
      send()
    }
  }, [send, uploading])

  const handleInputChange = useCallback((e: React.ChangeEvent<HTMLTextAreaElement>) => {
    if (e.target.value.length <= MAX_MESSAGE_LENGTH) {
      setInput(e.target.value)
    }
  }, [])

  const scrollToBottom = () => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }

  const refreshCurrentProviderModels = useCallback(async () => {
    await onRefreshModels(effectiveProvider || undefined)
    if (!effectiveProvider) return
    const data = await apiGetModels(effectiveProvider)
    const tagged = data.models.map((m) => ({ ...m, source: (m.source ?? data.source ?? 'static') as 'static' | 'discovered' }))
    setProviderModels(tagged)
  }, [effectiveProvider, onRefreshModels])

  useEffect(() => {
    if (!effectiveProvider) {
      setProviderModels([])
      setLoadingProviderModels(false)
      return
    }

    let cancelled = false
    setLoadingProviderModels(true)
    void apiGetModels(effectiveProvider).then((data) => {
      if (cancelled) return
      const tagged = data.models.map((m) => ({ ...m, source: (m.source ?? data.source ?? 'static') as 'static' | 'discovered' }))
      setProviderModels(tagged)
    }).catch(() => {
      if (cancelled) return
      setProviderModels([])
    }).finally(() => {
      if (!cancelled) setLoadingProviderModels(false)
    })

    return () => { cancelled = true }
  }, [effectiveProvider])

  const availableModels = useMemo(() => effectiveProvider ? providerModels : [], [effectiveProvider, providerModels])

  const filterSelectOption = (input: string, option?: { label?: unknown; value?: unknown; data?: { searchText?: string } }) => {
    if (!input) return true
    const haystack = option?.data?.searchText ?? `${option?.label ?? ''} ${option?.value ?? ''}`
    return String(haystack).toLowerCase().includes(input.toLowerCase())
  }

  const providerOptions = useMemo(() => [
    { label: 'Auto', value: '', searchText: 'auto server default all providers' },
    ...(modelData.providers?.map(p => ({ label: p.name, value: p.name, searchText: `${p.name} provider` })) ?? []),
  ], [modelData.providers])

  const modelOptions = useMemo(() => [
    {
      label: 'Auto',
      value: '',
      source: 'static' as const,
      is_manual: false,
      params: undefined,
      provider: undefined,
      searchText: 'auto server default default model',
    },
    ...[...availableModels]
      .sort((a, b) => (a.name || a.id).localeCompare(b.name || b.id))
      .map((m) => ({
        label: m.name || m.id,
        value: m.id,
        source: m.source ?? 'static' as const,
        is_manual: m.is_manual ?? false,
        params: m.params,
        provider: m.provider,
        searchText: `${m.name || m.id} ${m.id} ${m.provider ?? ''}`,
      })),
  ], [availableModels])

  useEffect(() => {
    if (!effectiveProvider) {
      if (!selectedModel) return
      setSelectedModel('')
      selectedModelRef.current = ''
      return
    }
    if (!selectedModel) return
    if (availableModels.some((m) => m.id === selectedModel)) return
    setSelectedModel('')
    selectedModelRef.current = ''
  }, [availableModels, effectiveProvider, selectedModel])

  const configDefaults = useMemo<LLMParamsOverride>(() => {
    const gp = modelData.global_params
    const d: LLMParamsOverride = {}
    if (gp) {
      if (gp.temperature != null) d.temperature = gp.temperature
      if (gp.max_tokens)          d.max_tokens  = gp.max_tokens
      if (gp.top_p != null)       d.top_p       = gp.top_p
      if (gp.top_k)               d.top_k       = gp.top_k
    }
    if (selectedModel) {
      const m = availableModels.find((m) => m.id === selectedModel)
      if (m?.params) {
        if (m.params.temperature != null) d.temperature = m.params.temperature
        if (m.params.max_tokens)          d.max_tokens  = m.params.max_tokens
        if (m.params.top_p != null)       d.top_p       = m.params.top_p
        if (m.params.top_k)               d.top_k       = m.params.top_k
      }
    }
    return d
  }, [selectedModel, availableModels, modelData.global_params])

  const systemPromptOptions = useMemo(() => [
    ...getSortedSystemPrompts(uiConfig).map((prompt) => ({
      label: prompt.name,
      value: prompt.name,
    })),
  ], [uiConfig])
  useEffect(() => {
    if (selectedConversationId) return
    if (selectedSystemPrompt && isKnownSystemPrompt(uiConfig, selectedSystemPrompt)) return
    const nextPrompt = getFirstSystemPromptName(uiConfig)
    if (!nextPrompt) return
    setSelectedSystemPrompt(nextPrompt)
    selectedSystemPromptRef.current = nextPrompt
  }, [selectedConversationId, selectedSystemPrompt, uiConfig])
  const hasSelectedSystemPrompt = selectedSystemPrompt !== ''
  const compactModelOptions = useMemo(() => ([
    { label: 'Auto', value: '' },
    ...models.map((model) => ({
      label: model.provider ? `${model.provider} · ${model.name || model.id}` : (model.name || model.id),
      value: model.id,
    })),
  ]), [models])

  const charCount = input.length
  const showCharCount = charCount > MAX_MESSAGE_LENGTH * 0.8
  const conversationQuery = conversationSearch.trim().toLowerCase()
  const filteredConversations = useMemo(() => {
    if (!conversationQuery) return conversations
    return conversations.filter((conv) => {
      const title = (conv.title || 'Untitled').toLowerCase()
      const model = (conv.model || '').toLowerCase()
      const provider = (conv.provider || '').toLowerCase()
      return title.includes(conversationQuery) || model.includes(conversationQuery) || provider.includes(conversationQuery)
    })
  }, [conversationQuery, conversations])
  const pinnedConversations = filteredConversations.filter((c) => c.pinned)
  const recentConversations = filteredConversations.filter((c) => !c.pinned)

  return (
    <Layout className="page">
      {/* ── Sidebar ── */}
      <Sider
        collapsible
        collapsed={siderCollapsed}
        onCollapse={setSiderCollapsed}
        collapsedWidth={0}
        trigger={null}
        width={260}
        className="sider"
        style={{
          background: token.colorBgContainer,
          borderRight: `1px solid ${token.colorBorderSecondary}`,
        }}
        >
          <div className="sider-content">
            <div className="sider-header">
              <div className="sider-actions">
                <Button type="primary" icon={<PlusOutlined />} block onClick={handleNewChat}>
                  New Chat
                </Button>
                <Tooltip title="Hide chat history">
                  <Button
                    type="text"
                    icon={<MenuFoldOutlined />}
                    onClick={() => setSiderCollapsed(true)}
                    aria-label="Hide chat history"
                  />
                </Tooltip>
              </div>
              <Input.Search
                value={conversationSearch}
                onChange={(e) => setConversationSearch(e.target.value)}
                placeholder="Search chats..."
                allowClear
                size="small"
                className="conversation-search"
              />
            </div>

            <div className="sider-list">
              {convsLoading ? (
                <div className="spin-center"><Spin size="small" /></div>
              ) : conversations.length === 0 ? (
              <Empty
                image={Empty.PRESENTED_IMAGE_SIMPLE}
                description={<Text type="secondary" style={{ fontSize: 12 }}>No past conversations</Text>}
                style={{ marginTop: 24 }}
                />
              ) : filteredConversations.length === 0 ? (
                <Empty
                  image={Empty.PRESENTED_IMAGE_SIMPLE}
                  description={<Text type="secondary" style={{ fontSize: 12 }}>No chats match your search</Text>}
                  style={{ marginTop: 24 }}
                />
              ) : (
                <>
                 {pinnedConversations.length > 0 && (
                   <>
                     <Divider plain style={{ fontSize: 11, color: token.colorTextTertiary, margin: '8px 0 4px' }}>Pinned</Divider>
                     {pinnedConversations.map((conv) => (
                        <ConvItem
                          key={conv.id}
                          conv={conv}
                          isActive={conv.id === sessionId}
                          isDark={isDark}
                         editingConvId={editingConvId}
                         editingTitle={editingTitle}
                         token={token}
                        onLoad={handleLoadConversation}
                        onStartEdit={(id, title) => { setEditingConvId(id); setEditingTitle(title) }}
                        onConfirmEdit={() => {
                          if (editingConvId) handleRenameConversation(editingConvId, editingTitle.trim() || 'Untitled')
                          setEditingConvId(null)
                        }}
                        onCancelEdit={() => setEditingConvId(null)}
                        onEditTitleChange={setEditingTitle}
                        onTogglePin={handleTogglePin}
                         onDelete={handleDeleteConversation}
                       />
                     ))}
                     {recentConversations.length > 0 && (
                       <Divider plain style={{ fontSize: 11, color: token.colorTextTertiary, margin: '8px 0 4px' }}>Recent</Divider>
                     )}
                   </>
                 )}
                 {recentConversations.map((conv) => (
                    <ConvItem
                      key={conv.id}
                      conv={conv}
                      isActive={conv.id === sessionId}
                      isDark={isDark}
                     editingConvId={editingConvId}
                     editingTitle={editingTitle}
                     token={token}
                    onLoad={handleLoadConversation}
                    onStartEdit={(id, title) => { setEditingConvId(id); setEditingTitle(title) }}
                    onConfirmEdit={() => {
                      if (editingConvId) handleRenameConversation(editingConvId, editingTitle.trim() || 'Untitled')
                      setEditingConvId(null)
                    }}
                    onCancelEdit={() => setEditingConvId(null)}
                    onEditTitleChange={setEditingTitle}
                    onTogglePin={handleTogglePin}
                    onDelete={handleDeleteConversation}
                  />
                ))}
              </>
            )}
          </div>
        </div>
      </Sider>

      {/* ── Chat content ── */}
      <Layout className="chat-col">
        {siderCollapsed && (
          <div className="history-toggle-rail">
            <Tooltip title="Show chat history">
              <Button
                className="history-toggle-btn"
                type="default"
                icon={<MenuUnfoldOutlined />}
                onClick={() => setSiderCollapsed(false)}
                aria-label="Show chat history"
                style={{ color: isDark ? '#fff' : token.colorText }}
              >
                History
              </Button>
            </Tooltip>
          </div>
        )}
        {/* ── Messages ── */}
        <Content ref={contentRef} className="messages">
          <div aria-live="polite" aria-label="Chat messages" role="log" className="message-log">
            {loadingConversation && (
              <div className="conversation-loading-state">
                <Spin size="large" />
                <Text type="secondary">Loading conversation...</Text>
              </div>
            )}

            {messages.length === 0 && !loading && !loadingConversation && (
              <div
                className="empty-state"
                style={{
                  background: isDark
                    ? 'radial-gradient(ellipse 80% 50% at 50% 10%, rgba(91,33,182,0.12) 0%, transparent 100%)'
                    : 'radial-gradient(ellipse 80% 50% at 50% 10%, rgba(91,33,182,0.07) 0%, transparent 100%)',
                }}
              >
                {/* Hero */}
                <div className="hero">
                  <img
                    aria-hidden="true"
                    className="hero-logo"
                    src={promptdLogo}
                    alt=""
                  />
                  <div className="hero-text">
                    <Text className="hero-title" style={{ color: token.colorText }}>
                      {uiConfig.welcomeTitle || 'How can I help you today?'}
                    </Text>
                    <Text type="secondary" className="hero-subtitle">
                      Promptd · AI Assistant
                    </Text>
                    <Text type="secondary" className="hero-description">
                      Start with a prompt below or type your own request. Ask for debugging, code changes, summaries, or planning help.
                    </Text>
                  </div>
                </div>

                {/* Prompt suggestions */}
                <div className="prompt-grid">
                  {(uiConfig.promptSuggestions || ['Explain how this works', 'Help me write code', 'Summarize the key points', 'What are best practices?']).map((prompt) => (
                    <button
                      key={prompt}
                      className="prompt-chip"
                      tabIndex={loading || !hasSelectedSystemPrompt ? -1 : 0}
                      disabled={loading || !hasSelectedSystemPrompt}
                      style={{
                        cursor: loading || !hasSelectedSystemPrompt ? 'not-allowed' : 'pointer',
                        border: `1px solid ${token.colorBorderSecondary}`,
                        background: token.colorBgElevated,
                        color: loading || !hasSelectedSystemPrompt ? token.colorTextDisabled : token.colorText,
                        opacity: loading || !hasSelectedSystemPrompt ? 0.5 : 1,
                      }}
                      onClick={() => { if (!loading && hasSelectedSystemPrompt) send(prompt) }}
                    >
                      <span className="prompt-chip-label">{prompt}</span>
                    </button>
                  ))}
                </div>
              </div>
            )}

            {!loadingConversation && messages.map((msg) => (
              <Bubble key={msg.id} msg={msg} onDelete={handleDeleteMessage} onEdit={handleEditMessage} />
            ))}

            {loading && !loadingConversation && <TypingIndicator />}

            <div ref={bottomRef} />
          </div>

          {showScrollBtn && (
            <Button
              type="primary"
              shape="circle"
              icon={<DownOutlined />}
              onClick={scrollToBottom}
              aria-label="Scroll to bottom"
              style={{ position: 'fixed', bottom: 100, right: 32, width: 40, height: 40, boxShadow: token.boxShadow, zIndex: 100 }}
            />
          )}
        </Content>

        {/* ── Input Footer ── */}
        <div
          className="input-footer"
          style={{ background: token.colorBgContainer, borderTop: `1px solid ${token.colorBorderSecondary}` }}
        >
          <div className="input-inner">
            <div className="input-wrap">
              <div className="input-relative">
                <TextArea
                  ref={inputRef}
                  value={input}
                  onChange={handleInputChange}
                  onKeyDown={handleKeyDown}
                  placeholder="Type a message…"
                  autoSize={{ minRows: 2, maxRows: 6 }}
                  disabled={loading || uploading || loadingConversation}
                  aria-label="Message input"
                  style={{ borderRadius: 12, resize: 'none', fontSize: 15, padding: '12px 50px 48px 16px' }}
                />
                <div
                  className="input-toolbar"
                  style={{ right: uiConfig.compactConversation?.enabled && canCompactConversation && (sessionId || messages.length > 0) ? 96 : 54, pointerEvents: loading || uploading || loadingConversation ? 'none' : 'auto', opacity: loading || uploading || loadingConversation ? 0.5 : 1 }}
                >
                  <Tooltip title={uploading ? 'Uploading...' : 'Attach file'}>
                    <Button
                      type="text"
                      size="small"
                      icon={<PaperClipOutlined />}
                      onClick={() => document.getElementById('file-upload')?.click()}
                        disabled={loading || uploading || loadingConversation}
                      aria-label={uploading ? 'Uploading file…' : 'Attach file'}
                      style={{ height: 28, width: 28, borderRadius: 6, display: 'flex', alignItems: 'center', justifyContent: 'center', color: token.colorTextSecondary }}
                    />
                  </Tooltip>
                  {systemPromptOptions.length > 0 && (
                    <Select
                      className="toolbar-select"
                      value={selectedSystemPrompt}
                      onChange={(v) => { setSelectedSystemPrompt(v); selectedSystemPromptRef.current = v }}
                      size="small"
                      aria-label="Select system prompt"
                      options={systemPromptOptions}
                      disabled={loading || loadingConversation}
                      status={hasSelectedSystemPrompt ? undefined : 'error'}
                      variant="borderless"
                      placement="topLeft"
                      showSearch={{ filterOption: filterSelectOption }}
                      placeholder="System prompt is required"
                      style={{ flex: 1, minWidth: 0 }}
                    />
                  )}
                  <Select
                    className="toolbar-select"
                    value={selectedProvider}
                    onChange={(v: string) => {
                      setSelectedProvider(v)
                      selectedProviderRef.current = v
                      setSelectedModel('')
                      selectedModelRef.current = ''
                    }}
                    size="small"
                    aria-label="Select provider"
                    variant="borderless"
                    showSearch={{ filterOption: filterSelectOption }}
                    placement="topLeft"
                    options={providerOptions}
                    disabled={loading || loadingConversation}
                    style={{ flex: '0 0 168px', width: 168 }}
                  />
                  {models.length > 0 && (
                    <Tooltip title={
                      modelData.source === 'discovered'
                        ? `Discovered — ${modelData.count} models${modelData.updated_at ? ` · refreshed ${new Date(modelData.updated_at).toLocaleTimeString()}` : ''}${modelData.refresh_interval ? ` · every ${modelData.refresh_interval}` : ''}`
                        : `Static — ${modelData.count} model${modelData.count !== 1 ? 's' : ''} from config`
                    }>
                      <Select
                        className="toolbar-select"
                        key={`chat-model-${effectiveProvider || 'auto'}`}
                        value={selectedModel}
                        onChange={(v) => { setSelectedModel(v); selectedModelRef.current = v }}
                        size="small"
                        aria-label="Select AI model"
                        options={modelOptions}
                        disabled={loading || loadingConversation || !effectiveProvider || loadingProviderModels}
                        variant="borderless"
                        showSearch={{ filterOption: filterSelectOption }}
                        placement="topLeft"
                        optionRender={(opt) => {
                          const p = opt.data.params as ModelInfo['params']
                          const paramHints = p ? [
                            p.temperature != null && `T=${p.temperature}`,
                            p.top_p        != null && `P=${p.top_p}`,
                            p.top_k        != null && `K=${p.top_k}`,
                            p.max_tokens              && `max=${p.max_tokens}`,
                          ].filter(Boolean) : []
                          return (
                            <div className="model-option">
                              <div className="model-option-left">
                                <span className="model-option-name">{opt.label}</span>
                                {opt.value !== '' && (
                                    <span className="model-option-sub" style={{ color: token.colorTextTertiary }}>
                                    {isMultiProvider && !selectedProvider && (opt.data.provider as string | undefined) && (
                                      <span className="provider-label" style={{ color: token.colorTextSecondary }}>
                                        {opt.data.provider as string} ·
                                      </span>
                                    )}
                                    {opt.value as string}
                                    {paramHints.length > 0 && (
                                      <span style={{ marginLeft: 6, color: token.colorPrimary, fontFamily: 'monospace' }}>
                                        {paramHints.join(' ')}
                                      </span>
                                    )}
                                  </span>
                                )}
                              </div>
                              <div className="model-option-right">
                                {opt.data.is_manual ? (
                                  <Tooltip title="Manually configured model">
                                    <span className="pill-md" style={{ background: token.colorInfoBg, color: token.colorInfo }}>manual</span>
                                  </Tooltip>
                                ) : opt.data.source === 'discovered' ? (
                                  <Tooltip title="Auto-discovered from provider">
                                    <span className="pill-md" style={{ background: token.colorSuccessBg, color: token.colorSuccess }}>disc</span>
                                  </Tooltip>
                                ) : opt.value !== '' ? (
                                  <Tooltip title="Configured in server config">
                                    <span className="pill-cfg" style={{ background: token.colorFillSecondary, color: token.colorTextTertiary }}>cfg</span>
                                  </Tooltip>
                                ) : null}
                              </div>
                            </div>
                          )
                        }}
                        style={{ flex: 1, minWidth: 0 }}
                      />
                    </Tooltip>
                  )}
                  {modelData.source === 'discovered' && (
                    <Tooltip title="Refresh model list now">
                      <Button
                        type="text"
                        size="small"
                        icon={<ReloadOutlined />}
                        onClick={() => { void refreshCurrentProviderModels() }}
                        disabled={loading || loadingConversation || loadingProviderModels}
                        style={{ height: 28, width: 28, padding: 0, color: token.colorTextSecondary, flexShrink: 0 }}
                      />
                    </Tooltip>
                  )}
                  <LLMParamsPopover
                    params={llmParams}
                    configDefaults={configDefaults}
                    onChange={(p) => { setLlmParams(p); llmParamsRef.current = p }}
                    disabled={loading || loadingConversation}
                  />
                </div>
                <div className="input-send">
                  {uiConfig.compactConversation?.enabled && canCompactConversation && (sessionId || messages.length > 0) && (
                    <Tooltip title="Compact conversation">
                      <Button
                        icon={<CompressOutlined />}
                        onClick={() => setCompactModalOpen(true)}
                        disabled={loading || loadingConversation || compacting}
                        aria-label="Compact conversation"
                        style={{ height: 34, width: 34, borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                      />
                    </Tooltip>
                  )}
                  <Tooltip title="Send">
                    <Button
                      type="primary"
                      icon={<SendOutlined />}
                      onClick={() => send()}
                      disabled={(!input.trim() && uploadedFiles.length === 0) || loading || !hasSelectedSystemPrompt}
                      aria-label="Send message"
                      style={{ height: 34, width: 34, borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                    />
                  </Tooltip>
                </div>
              </div>
              {showCharCount && (
                <Text
                  type={charCount >= MAX_MESSAGE_LENGTH ? 'danger' : 'secondary'}
                  className="char-count"
                >
                  {charCount} / {MAX_MESSAGE_LENGTH}
                </Text>
              )}
            </div>

            <input
              id="file-upload"
              type="file"
              multiple
              style={{ display: 'none' }}
              onChange={async (e) => {
                const files = e.target.files
                if (!files || files.length === 0) return

                const currentCount = uploadedFilesRef.current.length
                const incoming = Array.from(files)
                if (currentCount + incoming.length > MAX_FILES_PER_MESSAGE) {
                  antMessage.error(`You can attach at most ${MAX_FILES_PER_MESSAGE} files per message`)
                  e.target.value = ''
                  return
                }

                const oversized = incoming.filter((f) => f.size > MAX_FILE_SIZE)
                if (oversized.length > 0) {
                  antMessage.error(`${oversized.map((f) => f.name).join(', ')} exceed${oversized.length === 1 ? 's' : ''} the 10 MB limit`)
                  e.target.value = ''
                  return
                }

                setUploading(true)
                try {
                  const results = await Promise.allSettled(incoming.map((f) => apiUploadFile(f)))
                  const succeeded: UploadedFile[] = []
                  const failed: string[] = []
                  results.forEach((r, i) => {
                    if (r.status === 'fulfilled') succeeded.push(r.value)
                    else failed.push(incoming[i].name)
                  })
                  if (succeeded.length > 0) setUploadedFiles((prev) => [...prev, ...succeeded])
                  if (failed.length > 0) antMessage.error(`Failed to upload: ${failed.join(', ')}`)
                } finally {
                  setUploading(false)
                  e.target.value = ''
                }
              }}
            />
          </div>
          {uploadedFiles.length > 0 && (
            <div className="files-row">
              {uploadedFiles.map((file) => (
                  <Tag
                    key={file.id}
                    closable
                    onClose={() => removeUploadedFile(file.id)}
                    style={{ display: 'flex', alignItems: 'center', gap: 4 }}
                  >
                  <FileOutlined /> {file.filename} ({(file.size / 1024).toFixed(0)} KB)
                </Tag>
              ))}
            </div>
          )}
          <div className="disclaimer">
            <Text type="secondary" style={{ fontSize: 11 }}>
              {uiConfig.aiDisclaimer || 'AI can make mistakes. Verify important info.'}
            </Text>
          </div>
        </div>
      </Layout>
      <Modal
        open={compactModalOpen}
        title="Compact Conversation"
        onCancel={() => setCompactModalOpen(false)}
        onOk={() => { void handleCompactConversation() }}
        okText="Compact"
        confirmLoading={compacting}
        okButtonProps={{ disabled: !compactPrompt.trim() }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <Text>Prompt</Text>
          <TextArea
            value={compactPrompt}
            onChange={(e) => setCompactPrompt(e.target.value)}
            autoSize={{ minRows: 4, maxRows: 10 }}
            placeholder="Compaction prompt"
          />
          <Text>Model</Text>
          <Select
            value={compactModel}
            onChange={setCompactModel}
            options={compactModelOptions}
            showSearch={{ filterOption: filterSelectOption }}
          />
        </div>
      </Modal>
    </Layout>
  )
}
