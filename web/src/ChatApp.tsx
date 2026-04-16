import {
  App as AntApp,
  Avatar,
  Badge,
  Button,
  Divider,
  Empty,
  Layout,
  Select,
  Spin,
  Tag,
  Tooltip,
  Typography,
  theme,
} from 'antd'
import {
  DownOutlined,
  FileOutlined,
  FileTextOutlined,
  GithubOutlined,
  MenuFoldOutlined,
  MenuUnfoldOutlined,
  PaperClipOutlined,
  PlusOutlined,
  ReloadOutlined,
  RobotOutlined,
  SendOutlined,
  ToolOutlined,
  MoonOutlined,
  SunOutlined,
} from '@ant-design/icons'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Input } from 'antd'
import type { TextAreaRef } from 'antd/es/input/TextArea'

import type { Message, UIConfig, ToolInfo, ConversationMeta, LLMParamsOverride } from './types/chat'
import { getFirstSystemPromptName, getSortedSystemPrompts, isKnownSystemPrompt } from './types/chat'
import {
  apiListTools, apiGetUIConfig, apiGetModels, apiChat, apiUploadFile,
  apiListConversations, apiLoadConversation, apiDeleteConversation,
  apiRenameConversation, apiTogglePin, apiDeleteMessage, apiDeleteMessagesFrom,
  ChatError,
} from './api/client'
import type { ModelInfo, ModelData } from './api/client'
import { uid, MAX_FILE_SIZE, MAX_FILES_PER_MESSAGE, MAX_MESSAGE_LENGTH, isImageIcon } from './utils/helpers'
import type { UploadedFile, Role } from './types/chat'
import { Bubble } from './components/Bubble'
import { TypingIndicator } from './components/TypingIndicator'
import { ToolsDrawer } from './components/ToolsDrawer'
import { ConvItem } from './components/ConvItem'
import { LLMParamsPopover } from './components/LLMParamsPopover'

const { Sider, Content } = Layout
const { Text } = Typography
const { TextArea } = Input
const { useToken } = theme

interface ChatAppProps {
  isDark: boolean
  onToggleDark: () => void
}

export function ChatApp({ isDark, onToggleDark }: ChatAppProps) {
  const { token } = useToken()
  const { message: antMessage } = AntApp.useApp()

  const [sessionId, setSessionId] = useState(() => {
    const stored = sessionStorage.getItem('chatSessionId')
    if (stored) return stored
    const id = uid()
    sessionStorage.setItem('chatSessionId', id)
    return id
  })
  const [messages, setMessages] = useState<Message[]>([])
  const messagesRef = useRef<Message[]>([])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const loadingRef = useRef(false)
  const [models, setModels] = useState<ModelInfo[]>([])
  const [modelData, setModelData] = useState<{ source?: string; count: number; updated_at?: string; refresh_interval?: string; global_params?: ModelData['global_params'] }>({ count: 0 })
  const [selectedModel, setSelectedModel] = useState<string>('auto')
  const [selectedSystemPrompt, setSelectedSystemPrompt] = useState<string>('')
  const [llmParams, setLlmParams] = useState<LLMParamsOverride>({})
  const llmParamsRef = useRef<LLMParamsOverride>({})
  const pendingParamsRef = useRef<LLMParamsOverride | null>(null)

  const [toolsOpen, setToolsOpen] = useState(false)
  const [tools, setTools] = useState<ToolInfo[]>([])
  const [toolsLoading, setToolsLoading] = useState(false)
  const [uiConfig, setUIConfig] = useState<UIConfig>({})
  const [uploadedFiles, setUploadedFiles] = useState<UploadedFile[]>([])
  const [uploading, setUploading] = useState(false)

  const [siderCollapsed, setSiderCollapsed] = useState(false)
  const [conversations, setConversations] = useState<ConversationMeta[]>([])
  const [convsLoading, setConvsLoading] = useState(false)
  const [editingConvId, setEditingConvId] = useState<string | null>(null)
  const [editingTitle, setEditingTitle] = useState('')

  const appName = uiConfig.appName || 'Chatbot'
  const appIcon = uiConfig.appIcon

  const bottomRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<TextAreaRef>(null)
  const contentRef = useRef<HTMLDivElement>(null)
  const [showScrollBtn, setShowScrollBtn] = useState(false)

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

  useEffect(() => {
    let cancelled = false
    apiGetUIConfig().then((cfg) => {
      if (cancelled) return
      setUIConfig(cfg)
      setSelectedSystemPrompt((prev) => prev || getFirstSystemPromptName(cfg))
    }).catch(() => {})
    apiGetModels().then((data) => {
      if (cancelled) return
      const tagged = data.models.map((m) => ({ ...m, source: (data.source ?? 'static') as 'static' | 'discovered' }))
      setModels(tagged)
      setModelData({ source: data.source, count: data.count, updated_at: data.updated_at, refresh_interval: data.refresh_interval, global_params: data.global_params })
    }).catch(() => {})
    apiListTools().then((list) => {
      if (cancelled) return
      setTools(list)
    }).catch(() => {})
    return () => { cancelled = true }
  }, [])

  useEffect(() => {
    document.title = appName
    if (!isImageIcon(appIcon)) return
    const link = document.querySelector("link[rel='icon']") || document.createElement('link')
    link.setAttribute('rel', 'icon')
    link.setAttribute('href', appIcon || '')
    if (!link.parentNode) document.head.appendChild(link)
  }, [appIcon, appName])

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
    const id = uid()
    sessionStorage.setItem('chatSessionId', id)
    setSessionId(id)
    setMessages([])
    setInput('')
    setUploadedFiles([])
    const nextPrompt = getFirstSystemPromptName(uiConfig)
    setSelectedSystemPrompt(nextPrompt)
    selectedSystemPromptRef.current = nextPrompt
  }, [uiConfig.systemPrompts])

  const handleLoadConversation = useCallback(async (id: string, silent = false) => {
    const detail = await apiLoadConversation(id)
    if (!detail) {
      if (!silent) antMessage.error('Failed to load conversation')
      return
    }
    sessionStorage.setItem('chatSessionId', id)
    setSessionId(id)
    setInput('')
    setUploadedFiles([])
    const uiMsgs: Message[] = detail.messages
      .filter((m) => m.role === 'user' || m.role === 'assistant')
      .map((m) => ({
        id: uid(),
        role: m.role as Role,
        content: m.content,
        ts: m.sent_at ? new Date(m.sent_at) : new Date(detail.updated_at),
        model: m.model,
        timeTaken: m.time_taken_ms,
        llmCalls: m.llm_calls,
        toolCalls: m.tool_calls,
        msgId: m.id,
        trace: m.trace,
        usedParams: m.used_params,
      }))
    setMessages(uiMsgs)
    const next = detail.model || 'auto'
    if (detail.params && Object.keys(detail.params).length > 0) {
      pendingParamsRef.current = detail.params
    } else {
      pendingParamsRef.current = null
    }
    setSelectedModel(next)
    selectedModelRef.current = next
    const nextPrompt = isKnownSystemPrompt(uiConfig, detail.system_prompt)
      ? detail.system_prompt || ''
      : getFirstSystemPromptName(uiConfig)
    setSelectedSystemPrompt(nextPrompt)
    selectedSystemPromptRef.current = nextPrompt
  }, [antMessage, uiConfig.systemPrompts])

  useEffect(() => {
    void handleLoadConversation(sessionId, true)
  }, [handleLoadConversation, sessionId])

  const handleDeleteConversation = useCallback(async (id: string) => {
    await apiDeleteConversation(id)
    if (id === sessionId) handleNewChat()
    refreshConversations()
  }, [sessionId, handleNewChat, refreshConversations])

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

  const fetchTools = useCallback(async () => {
    setToolsLoading(true)
    try {
      const list = await apiListTools()
      setTools(list)
    } catch {
      antMessage.error('Could not load tools')
    } finally {
      setToolsLoading(false)
    }
  }, [antMessage])

  const handleOpenTools = useCallback(() => {
    setToolsOpen(true)
    fetchTools()
  }, [fetchTools])

  useEffect(() => { messagesRef.current = messages }, [messages])

  const selectedModelRef = useRef(selectedModel)
  useEffect(() => { selectedModelRef.current = selectedModel }, [selectedModel])

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
    if (selectedModel === 'auto') {
      setLlmParams(globalDefaults)
      llmParamsRef.current = globalDefaults
      return
    }
    const m = models.find((m) => m.id === selectedModel)
    const p: LLMParamsOverride = { ...globalDefaults }
    if (m?.params) {
      if (m.params.temperature != null) p.temperature = m.params.temperature
      if (m.params.max_tokens)          p.max_tokens  = m.params.max_tokens
      if (m.params.top_p != null)       p.top_p       = m.params.top_p
      if (m.params.top_k)               p.top_k       = m.params.top_k
    }
    setLlmParams(p)
    llmParamsRef.current = p
  }, [selectedModel, models, modelData.global_params])

  const selectedSystemPromptRef = useRef(selectedSystemPrompt)
  useEffect(() => { selectedSystemPromptRef.current = selectedSystemPrompt }, [selectedSystemPrompt])
  useEffect(() => { llmParamsRef.current = llmParams }, [llmParams])

  const uploadedFilesRef = useRef(uploadedFiles)
  useEffect(() => { uploadedFilesRef.current = uploadedFiles }, [uploadedFiles])

  const sessionIdRef = useRef(sessionId)
  useEffect(() => { sessionIdRef.current = sessionId }, [sessionId])

  const send = useCallback(async (overrideText?: string) => {
    if (loadingRef.current) return
    const text = (overrideText ?? input).trim()
    if (!text && uploadedFilesRef.current.length === 0) return

    const files = uploadedFilesRef.current
    const currentSessionId = sessionIdRef.current
    setInput('')
    const userMsg: Message = { id: uid(), role: 'user', content: text, ts: new Date(), files }
    setMessages((prev) => [...prev, userMsg])
    setUploadedFiles([])
    setLoading(true)
    loadingRef.current = true

    try {
      const fileUrls = files.map((f) => f.url)
      const modelId = selectedModelRef.current
      const modelToSend = modelId === 'auto' ? undefined : modelId
      const systemPromptToSend = selectedSystemPromptRef.current || undefined
      const response = await apiChat(currentSessionId, text, fileUrls, modelToSend, systemPromptToSend, llmParamsRef.current)
      if (response.user_msg_id) {
        setMessages((prev) => prev.map((m) => m.id === userMsg.id ? { ...m, msgId: response.user_msg_id } : m))
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
        files: response.files,
        msgId: response.assistant_msg_id,
        trace: response.trace,
        usedParams: response.used_params,
      }
      setMessages((prev) => [...prev, assistantMsg])
      refreshConversations()
    } catch (err) {
      const serverModel = err instanceof ChatError ? err.model : undefined
      const requestedModel = selectedModelRef.current
      const errorModel = serverModel || requestedModel || 'unknown'
      const errMsg: Message = {
        id: uid(),
        role: 'error',
        content: err instanceof Error ? err.message : 'Something went wrong',
        ts: new Date(),
        model: errorModel,
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
  }, [input, refreshConversations])

  const handleDeleteMessage = useCallback((id: string) => {
    setMessages((prev) => {
      const msg = prev.find((m) => m.id === id)
      if (msg?.msgId) {
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

  const modelOptions = useMemo(() => [
    { label: 'Auto', value: 'auto', source: 'static' as const, is_manual: false },
    ...models.map((m) => ({ label: m.name || m.id, value: m.id, source: m.source ?? 'static' as const, is_manual: m.is_manual ?? false })),
  ], [models])

  const configDefaults = useMemo<LLMParamsOverride>(() => {
    const gp = modelData.global_params
    const d: LLMParamsOverride = {}
    if (gp) {
      if (gp.temperature != null) d.temperature = gp.temperature
      if (gp.max_tokens)          d.max_tokens  = gp.max_tokens
      if (gp.top_p != null)       d.top_p       = gp.top_p
      if (gp.top_k)               d.top_k       = gp.top_k
    }
    if (selectedModel !== 'auto') {
      const m = models.find((m) => m.id === selectedModel)
      if (m?.params) {
        if (m.params.temperature != null) d.temperature = m.params.temperature
        if (m.params.max_tokens)          d.max_tokens  = m.params.max_tokens
        if (m.params.top_p != null)       d.top_p       = m.params.top_p
        if (m.params.top_k)               d.top_k       = m.params.top_k
      }
    }
    return d
  }, [selectedModel, models, modelData.global_params])

  const systemPromptOptions = useMemo(() => [
    ...getSortedSystemPrompts(uiConfig).map((prompt) => ({
      label: prompt.name,
      value: prompt.name,
    })),
  ], [uiConfig.systemPrompts])

  const charCount = input.length
  const showCharCount = charCount > MAX_MESSAGE_LENGTH * 0.8

  return (
    <Layout style={{ height: '100vh', background: token.colorBgLayout }}>
      {/* ── Sidebar ── */}
      <Sider
        collapsible
        collapsed={siderCollapsed}
        onCollapse={setSiderCollapsed}
        collapsedWidth={0}
        trigger={null}
        width={260}
        style={{
          background: token.colorBgContainer,
          borderRight: `1px solid ${token.colorBorderSecondary}`,
          overflow: 'hidden',
          display: 'flex',
          flexDirection: 'column',
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
          <div style={{ padding: '12px 12px 8px' }}>
            <Button
              type="primary"
              icon={<PlusOutlined />}
              block
              onClick={handleNewChat}
              style={{ borderRadius: 8 }}
            >
              New Chat
            </Button>
          </div>

          <div style={{ flex: 1, overflowY: 'auto', padding: '0 8px 8px' }}>
            {convsLoading ? (
              <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 24 }}>
                <Spin size="small" />
              </div>
            ) : conversations.length === 0 ? (
              <Empty
                image={Empty.PRESENTED_IMAGE_SIMPLE}
                description={<Text type="secondary" style={{ fontSize: 12 }}>No past conversations</Text>}
                style={{ marginTop: 24 }}
              />
            ) : (
              <>
                {conversations.some((c) => c.pinned) && (
                  <>
                    <Divider plain style={{ fontSize: 11, color: token.colorTextTertiary, margin: '8px 0 4px' }}>Pinned</Divider>
                    {conversations.filter((c) => c.pinned).map((conv) => (
                      <ConvItem
                        key={conv.id}
                        conv={conv}
                        isActive={conv.id === sessionId}
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
                    {conversations.some((c) => !c.pinned) && (
                      <Divider plain style={{ fontSize: 11, color: token.colorTextTertiary, margin: '8px 0 4px' }}>Recent</Divider>
                    )}
                  </>
                )}
                {conversations.filter((c) => !c.pinned).map((conv) => (
                  <ConvItem
                    key={conv.id}
                    conv={conv}
                    isActive={conv.id === sessionId}
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

      {/* ── Main area ── */}
      <Layout style={{ display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {/* ── Header ── */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            padding: '0 20px',
            background: token.colorBgContainer,
            borderBottom: `1px solid ${token.colorBorderSecondary}`,
            height: 56,
            flexShrink: 0,
            position: 'sticky',
            top: 0,
            zIndex: 10,
            boxShadow: token.boxShadow,
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <Button
              type="text"
              icon={siderCollapsed ? <MenuUnfoldOutlined /> : <MenuFoldOutlined />}
              onClick={() => setSiderCollapsed(!siderCollapsed)}
              aria-label={siderCollapsed ? 'Open sidebar' : 'Close sidebar'}
              style={{ color: token.colorTextSecondary }}
            />
            <Avatar
              aria-hidden="true"
              src={isImageIcon(appIcon) ? appIcon : undefined}
              icon={!appIcon ? <RobotOutlined /> : undefined}
              style={{
                background: !appIcon ? token.colorPrimary : isImageIcon(appIcon) ? token.colorFillSecondary : token.colorBgContainer,
                color: !appIcon ? '#fff' : token.colorText,
                fontSize: appIcon && !isImageIcon(appIcon) ? 18 : undefined,
                border: isImageIcon(appIcon) ? `1px solid ${token.colorBorderSecondary}` : undefined,
              }}
              size={36}
            >
              {appIcon && !isImageIcon(appIcon) ? appIcon : null}
            </Avatar>
            <div>
              <Text strong style={{ fontSize: 15, display: 'block', lineHeight: 1.2 }}>
                {appName}
              </Text>
              <Text type="secondary" style={{ fontSize: 11 }}>
                AI Assistant
              </Text>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <Tooltip title={isDark ? 'Light mode' : 'Dark mode'}>
              <Button
                icon={isDark ? <SunOutlined /> : <MoonOutlined />}
                onClick={onToggleDark}
                type="text"
                aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
                style={{ color: token.colorTextSecondary }}
              />
            </Tooltip>
            <Tooltip title="Active tools">
              <Badge count={tools.length} size="small">
                <Button
                  icon={<ToolOutlined />}
                  onClick={handleOpenTools}
                  type="text"
                  aria-label="View active tools"
                  style={{ color: token.colorTextSecondary }}
                />
              </Badge>
            </Tooltip>
            <Tooltip title="GitHub (opens in new tab)">
              <Button
                icon={<GithubOutlined />}
                href="https://github.com/anomalyco/chatbot"
                target="_blank"
                rel="noopener noreferrer"
                type="text"
                aria-label="View source on GitHub (opens in new tab)"
                style={{ color: token.colorTextSecondary }}
              />
            </Tooltip>
          </div>
        </div>

        {/* ── Messages ── */}
        <Content
          ref={contentRef}
          style={{
            flex: 1,
            overflowY: 'auto',
            padding: '20px 0',
            display: 'flex',
            flexDirection: 'column',
            position: 'relative',
          }}
        >
          <div
            aria-live="polite"
            aria-label="Chat messages"
            role="log"
            style={{
              width: '100%',
              maxWidth: 'min(92%, 1800px)',
              margin: '0 auto',
              padding: '0 16px',
              display: 'flex',
              flexDirection: 'column',
              gap: 4,
              flex: 1,
            }}
          >
            {messages.length === 0 && !loading && (
              <div
                style={{
                  flex: 1,
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 20,
                  color: token.colorTextSecondary,
                  paddingBottom: 60,
                }}
              >
                <Avatar
                  aria-hidden="true"
                  icon={<RobotOutlined />}
                  size={64}
                  style={{ background: token.colorPrimary, opacity: 0.85 }}
                />
                <div style={{ textAlign: 'center' }}>
                  <Text style={{ fontSize: 18, display: 'block', fontWeight: 600, color: token.colorText }}>
                    {uiConfig.welcomeTitle || 'How can I help you today?'}
                  </Text>
                </div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, justifyContent: 'center', marginTop: 4 }}>
                  {(uiConfig.promptSuggestions || ['Explain how this works', 'Help me write code', 'Summarize the key points', 'What are best practices?']).map((prompt) => (
                    <Tag
                      key={prompt}
                      className="prompt-chip"
                      tabIndex={loading ? -1 : 0}
                      role="button"
                      aria-disabled={loading}
                      style={{
                        padding: '6px 14px',
                        fontSize: 13,
                        cursor: loading ? 'not-allowed' : 'pointer',
                        borderRadius: 16,
                        border: `1px solid ${token.colorBorder}`,
                        background: token.colorBgContainer,
                        color: loading ? token.colorTextDisabled : token.colorText,
                        opacity: loading ? 0.5 : 1,
                      }}
                      onClick={() => { if (!loading) send(prompt) }}
                      onKeyDown={(e) => {
                        if (!loading && (e.key === 'Enter' || e.key === ' ')) {
                          e.preventDefault()
                          send(prompt)
                        }
                      }}
                    >
                      {prompt}
                    </Tag>
                  ))}
                </div>
              </div>
            )}

            {messages.map((msg) => (
              <Bubble key={msg.id} msg={msg} onDelete={handleDeleteMessage} onEdit={handleEditMessage} />
            ))}

            {loading && <TypingIndicator />}

            <div ref={bottomRef} />
          </div>

          {showScrollBtn && (
            <Button
              type="primary"
              shape="circle"
              icon={<DownOutlined />}
              onClick={scrollToBottom}
              aria-label="Scroll to bottom"
              style={{
                position: 'fixed',
                bottom: 100,
                right: 32,
                width: 40,
                height: 40,
                boxShadow: token.boxShadow,
                zIndex: 100,
              }}
            />
          )}
        </Content>

        {/* ── Input Footer ── */}
        <div
          style={{
            padding: '12px 16px 16px',
            background: token.colorBgContainer,
            borderTop: `1px solid ${token.colorBorderSecondary}`,
            flexShrink: 0,
          }}
        >
          <div style={{ maxWidth: 'min(92%, 1800px)', margin: '0 auto' }}>
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 4 }}>
              <div style={{ position: 'relative' }}>
                <TextArea
                  ref={inputRef}
                  value={input}
                  onChange={handleInputChange}
                  onKeyDown={handleKeyDown}
                  placeholder="Type a message…"
                  autoSize={{ minRows: 2, maxRows: 6 }}
                  disabled={loading || uploading}
                  aria-label="Message input"
                  style={{
                    borderRadius: 12,
                    resize: 'none',
                    fontSize: 15,
                    padding: '12px 16px',
                    paddingBottom: 48,
                  }}
                />
                <div
                  style={{
                    position: 'absolute',
                    bottom: 6,
                    left: 8,
                    right: 54,
                    display: 'flex',
                    alignItems: 'center',
                    gap: 4,
                    pointerEvents: loading || uploading ? 'none' : 'auto',
                    opacity: loading || uploading ? 0.5 : 1,
                  }}
                >
                  <Tooltip title={uploading ? 'Uploading...' : 'Attach file'}>
                    <Button
                      type="text"
                      size="small"
                      icon={<PaperClipOutlined />}
                      onClick={() => document.getElementById('file-upload')?.click()}
                      disabled={loading || uploading}
                      aria-label={uploading ? 'Uploading file…' : 'Attach file'}
                      style={{
                        height: 28,
                        width: 28,
                        borderRadius: 6,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        color: token.colorTextSecondary,
                      }}
                    />
                  </Tooltip>
                  {systemPromptOptions.length > 0 && (
                    <Select
                      value={selectedSystemPrompt}
                      onChange={(v) => { setSelectedSystemPrompt(v); selectedSystemPromptRef.current = v }}
                      size="small"
                      aria-label="Select system prompt"
                      options={systemPromptOptions}
                      disabled={loading}
                      variant="borderless"
                      popupMatchSelectWidth={false}
                      placement="topLeft"
                      showSearch
                      optionFilterProp={['label', 'value'] as unknown as string}
                      prefix={<FileTextOutlined style={{ color: token.colorTextSecondary, fontSize: 13 }} />}
                      optionRender={(opt) => (
                        <div style={{ display: 'flex', flexDirection: 'column', padding: '2px 0' }}>
                          <span style={{ fontWeight: 500, fontSize: 13, lineHeight: 1.4 }}>{opt.label}</span>
                          {opt.value && (
                            <span style={{ fontSize: 11, color: token.colorTextTertiary, lineHeight: 1.3 }}>{String(opt.value)}</span>
                          )}
                        </div>
                      )}
                      style={{ flex: 1, minWidth: 0 }}
                    />
                  )}
                  {models.length > 0 && (
                    <Tooltip title={
                      modelData.source === 'discovered'
                        ? `Discovered — ${modelData.count} models${modelData.updated_at ? ` · refreshed ${new Date(modelData.updated_at).toLocaleTimeString()}` : ''}${modelData.refresh_interval ? ` · every ${modelData.refresh_interval}` : ''}`
                        : `Static — ${modelData.count} model${modelData.count !== 1 ? 's' : ''} from config`
                    }>
                      <Select
                        value={selectedModel}
                        onChange={(v) => { setSelectedModel(v); selectedModelRef.current = v }}
                        size="small"
                        aria-label="Select AI model"
                        options={modelOptions}
                        disabled={loading}
                        variant="borderless"
                        popupMatchSelectWidth={false}
                        placement="topLeft"
                        showSearch
                        optionFilterProp={['label', 'value'] as unknown as string}
                        prefix={
                          <span style={{ display: 'flex', alignItems: 'center', gap: 3 }}>
                            <RobotOutlined style={{ color: token.colorTextSecondary, fontSize: 13 }} />
                            {modelData.source === 'discovered' && (
                              <span style={{
                                fontSize: 9,
                                fontWeight: 700,
                                lineHeight: 1,
                                padding: '1px 3px',
                                borderRadius: 3,
                                background: token.colorSuccessBg,
                                color: token.colorSuccess,
                                letterSpacing: 0.3,
                              }}>DISC</span>
                            )}
                          </span>
                        }
                        optionRender={(opt) => (
                          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 6, padding: '2px 0' }}>
                            <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                              <span style={{ fontWeight: 500, fontSize: 13, lineHeight: 1.4 }}>{opt.label}</span>
                              {opt.value !== 'auto' && (
                                <span style={{ fontSize: 11, color: token.colorTextTertiary, lineHeight: 1.3, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{opt.value}</span>
                              )}
                            </div>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 3, flexShrink: 0 }}>
                              {opt.data.is_manual && (
                                <span style={{
                                  fontSize: 9, fontWeight: 700, lineHeight: 1,
                                  padding: '1px 4px', borderRadius: 3,
                                  background: token.colorInfoBg, color: token.colorInfo,
                                  letterSpacing: 0.3,
                                }}>M</span>
                              )}
                              {!opt.data.is_manual && opt.data.source === 'discovered' ? (
                                <span style={{
                                  fontSize: 9, fontWeight: 700, lineHeight: 1,
                                  padding: '1px 4px', borderRadius: 3,
                                  background: token.colorSuccessBg, color: token.colorSuccess,
                                  letterSpacing: 0.3,
                                }}>DISC</span>
                              ) : !opt.data.is_manual && opt.value !== 'auto' ? (
                                <span style={{
                                  fontSize: 9, fontWeight: 600, lineHeight: 1,
                                  padding: '1px 4px', borderRadius: 3,
                                  background: token.colorFillSecondary, color: token.colorTextTertiary,
                                  letterSpacing: 0.3,
                                }}>CFG</span>
                              ) : null}
                            </div>
                          </div>
                        )}
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
                        onClick={async () => {
                          const data = await apiGetModels()
                          const tagged = data.models.map((m) => ({ ...m, source: (data.source ?? 'static') as 'static' | 'discovered' }))
                          setModels(tagged)
                          setModelData({ source: data.source, count: data.count, updated_at: data.updated_at, refresh_interval: data.refresh_interval, global_params: data.global_params })
                        }}
                        disabled={loading}
                        style={{ height: 28, width: 28, padding: 0, color: token.colorTextSecondary, flexShrink: 0 }}
                      />
                    </Tooltip>
                  )}
                  <LLMParamsPopover
                    params={llmParams}
                    configDefaults={configDefaults}
                    onChange={(p) => { setLlmParams(p); llmParamsRef.current = p }}
                    disabled={loading}
                  />
                </div>
                <div style={{ position: 'absolute', bottom: 6, right: 8 }}>
                  <Tooltip title="Send">
                    <Button
                      type="primary"
                      icon={<SendOutlined />}
                      onClick={() => send()}
                      disabled={(!input.trim() && uploadedFiles.length === 0) || loading}
                      aria-label="Send message"
                      style={{
                        height: 34,
                        width: 34,
                        borderRadius: 10,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                      }}
                    />
                  </Tooltip>
                </div>
              </div>
              {showCharCount && (
                <Text
                  type={charCount >= MAX_MESSAGE_LENGTH ? 'danger' : 'secondary'}
                  style={{ fontSize: 11, textAlign: 'right' }}
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
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 8, maxWidth: 'min(92%, 1800px)', margin: '8px auto 0' }}>
              {uploadedFiles.map((file) => (
                <Tag
                  key={file.id}
                  closable
                  onClose={() => setUploadedFiles((prev) => prev.filter((f) => f.id !== file.id))}
                  style={{ display: 'flex', alignItems: 'center', gap: 4 }}
                >
                  <FileOutlined /> {file.filename} ({(file.size / 1024).toFixed(0)} KB)
                </Tag>
              ))}
            </div>
          )}
          <div style={{ textAlign: 'center', marginTop: 8 }}>
            <Text type="secondary" style={{ fontSize: 11 }}>
              {uiConfig.aiDisclaimer || 'AI can make mistakes. Verify important info.'}
            </Text>
          </div>
        </div>

        <ToolsDrawer
          open={toolsOpen}
          onClose={() => setToolsOpen(false)}
          tools={tools}
          loading={toolsLoading}
          onRefresh={fetchTools}
        />
      </Layout>
    </Layout>
  )
}
