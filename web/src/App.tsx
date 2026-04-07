import { useEffect, useRef, useState, useCallback } from 'react'
import {
  Button,
  Input,
  Layout,
  Typography,
  Avatar,
  Tooltip,
  Badge,
  Drawer,
  List,
  Tag,
  Empty,
  Spin,
  App as AntApp,
  ConfigProvider,
  theme,
  message as antdMessage,
} from 'antd'
import type { TextAreaRef } from 'antd/es/input/TextArea'
import {
  SendOutlined,
  PlusOutlined,
  RobotOutlined,
  UserOutlined,
  ToolOutlined,
  ReloadOutlined,
  GithubOutlined,
  CopyOutlined,
  CheckOutlined,
  DownOutlined,
  SunOutlined,
  MoonOutlined,
} from '@ant-design/icons'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter'
import { vscDarkPlus } from 'react-syntax-highlighter/dist/esm/styles/prism'

const { Content } = Layout
const { Text } = Typography
const { TextArea } = Input
const { useToken } = theme

// ── Types ──────────────────────────────────────────────────────────────────

type Role = 'user' | 'assistant' | 'error'

interface Message {
  id: string
  role: Role
  content: string
  ts: Date
  timeTaken?: number
  llmCalls?: number
  toolCalls?: number
}

interface ToolInfo {
  name: string
  description: string
  serverName?: string
}

interface MCPServer {
  url: string
  tools: string[]
  name?: string
}

type MCPServersResponse = {
  servers: MCPServer[]
}

interface UIConfig {
  welcomeTitle?: string
  aiDisclaimer?: string
  promptSuggestions?: string[]
}

async function apiListTools(): Promise<ToolInfo[]> {
  const res = await fetch('/mcp')
  if (!res.ok) return []
  const data: MCPServersResponse = await res.json()
  return data.servers?.flatMap((s) => s.tools.map((t) => ({ 
    name: t, 
    description: t,
    serverName: s.name || s.url 
  }))) ?? []
}

async function apiGetUIConfig(): Promise<UIConfig> {
  const res = await fetch('/ui-config')
  return res.json()
}

// ── API helpers ────────────────────────────────────────────────────────────

type ChatResponse = {
  reply: string
  time_taken_ms: number
  llm_calls: number
  tool_calls: number
}

async function apiChat(sessionId: string, message: string): Promise<ChatResponse> {
  const res = await fetch('/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ session_id: sessionId, message }),
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'Request failed')
  return data as ChatResponse
}

async function apiReset(sessionId: string): Promise<void> {
  await fetch('/reset', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ session_id: sessionId }),
  })
}

// ── Utilities ──────────────────────────────────────────────────────────────

function uid(): string {
  return crypto.randomUUID()
}

function fmt(d: Date): string {
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

// ── Markdown code block renderer ───────────────────────────────────────────

function CodeBlock({ language, code }: { language?: string; code: string }) {
  const { token } = useToken()
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(code)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      antdMessage.error('Failed to copy')
    }
  }

  return (
    <div style={{ position: 'relative', margin: '8px 0', borderRadius: 8, overflow: 'hidden' }}>
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          padding: '6px 12px',
          background: token.colorBgLayout,
          borderBottom: `1px solid ${token.colorBorderSecondary}`,
        }}
      >
        <Text style={{ fontSize: 12, color: token.colorTextSecondary }}>
          {language || 'code'}
        </Text>
        <Button
          type="text"
          size="small"
          icon={copied ? <CheckOutlined style={{ color: token.colorSuccess }} /> : <CopyOutlined />}
          onClick={handleCopy}
          style={{ fontSize: 12 }}
        >
          {copied ? 'Copied' : 'Copy'}
        </Button>
      </div>
      <SyntaxHighlighter
        language={language || 'text'}
        style={vscDarkPlus}
        customStyle={{ margin: 0, borderRadius: 0, fontSize: 13 }}
        wrapLongLines
      >
        {code}
      </SyntaxHighlighter>
    </div>
  )
}

// ── Bubble component ───────────────────────────────────────────────────────

function Bubble({ msg }: { msg: Message }) {
  const { token } = useToken()
  const isUser = msg.role === 'user'
  const isError = msg.role === 'error'
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(msg.content)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      antdMessage.error('Failed to copy')
    }
  }

  const bubbleStyle: React.CSSProperties = isUser
    ? {
        background: token.colorPrimary,
        color: '#fff',
        borderRadius: '18px 18px 4px 18px',
        padding: '10px 16px',
        maxWidth: '72%',
        whiteSpace: 'pre-wrap',
        wordBreak: 'break-word',
        lineHeight: 1.5,
        fontSize: 14,
        boxShadow: token.boxShadow,
      }
    : isError
    ? {
        background: token.colorErrorBg,
        color: token.colorError,
        border: `1px solid ${token.colorErrorBorder}`,
        borderRadius: 8,
        padding: '8px 14px',
        maxWidth: '80%',
        fontSize: 13,
        lineHeight: 1.5,
      }
    : {
        background: token.colorBgContainer,
        color: token.colorText,
        border: `1px solid ${token.colorBorderSecondary}`,
        borderRadius: '18px 18px 18px 4px',
        padding: '10px 16px',
        maxWidth: '72%',
        wordBreak: 'break-word',
        lineHeight: 1.5,
        fontSize: 14,
        boxShadow: token.boxShadow,
      }

  return (
    <div
      className="bubble-enter"
      style={{
        display: 'flex',
        flexDirection: isUser ? 'row-reverse' : 'row',
        alignItems: 'flex-end',
        gap: 10,
        padding: '4px 0',
      }}
    >
      {!isUser && !isError && (
        <Avatar
          size={32}
          icon={<RobotOutlined />}
          style={{ background: token.colorPrimary, flexShrink: 0, marginBottom: 2 }}
        />
      )}
      {isUser && (
        <Avatar
          size={32}
          icon={<UserOutlined />}
          style={{ background: token.colorTextSecondary, flexShrink: 0, marginBottom: 2 }}
        />
      )}
      {isError && (
        <Avatar
          size={32}
          icon={<RobotOutlined />}
          style={{ background: token.colorError, flexShrink: 0, marginBottom: 2 }}
        />
      )}

      <div style={{ display: 'flex', flexDirection: 'column', alignItems: isUser ? 'flex-end' : 'flex-start', gap: 3 }}>
        <div
          className="bubble-content"
          style={{ ...bubbleStyle, position: 'relative' }}
          onMouseEnter={!isUser && !isError ? (e) => {
            const btn = (e.currentTarget as HTMLElement).querySelector('.copy-btn') as HTMLElement | null
            if (btn) btn.style.opacity = '1'
          } : undefined}
          onMouseLeave={!isUser && !isError ? (e) => {
            const btn = (e.currentTarget as HTMLElement).querySelector('.copy-btn') as HTMLElement | null
            if (btn) btn.style.opacity = '0'
          } : undefined}
        >
          {!isUser && !isError ? (
            <ReactMarkdown
              remarkPlugins={[remarkGfm]}
              components={{
                code({ className, children, ...props }) {
                  const match = /language-(\w+)/.exec(className || '')
                  const codeStr = String(children).replace(/\n$/, '')
                  if (match) {
                    return <CodeBlock language={match[1]} code={codeStr} />
                  }
                  return (
                    <code
                      style={{
                        background: token.colorFillSecondary,
                        padding: '2px 6px',
                        borderRadius: 4,
                        fontSize: '0.9em',
                        fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
                      }}
                      {...props}
                    >
                      {children}
                    </code>
                  )
                },
                pre({ children }) {
                  return <>{children}</>
                },
                p({ children }) {
                  return <p style={{ margin: '0.5em 0' }}>{children}</p>
                },
                ul({ children }) {
                  return <ul style={{ margin: '0.5em 0', paddingLeft: '1.5em' }}>{children}</ul>
                },
                ol({ children }) {
                  return <ol style={{ margin: '0.5em 0', paddingLeft: '1.5em' }}>{children}</ol>
                },
                li({ children }) {
                  return <li style={{ margin: '0.25em 0' }}>{children}</li>
                },
                blockquote({ children }) {
                  return (
                    <blockquote
                      style={{
                        margin: '0.5em 0',
                        paddingLeft: '1em',
                        borderLeft: `3px solid ${token.colorPrimary}`,
                        color: token.colorTextSecondary,
                      }}
                    >
                      {children}
                    </blockquote>
                  )
                },
                table({ children }) {
                  return (
                    <div style={{ overflowX: 'auto', margin: '0.5em 0' }}>
                      <table
                        style={{
                          borderCollapse: 'collapse',
                          width: '100%',
                          fontSize: 13,
                        }}
                      >
                        {children}
                      </table>
                    </div>
                  )
                },
                th({ children }) {
                  return (
                    <th
                      style={{
                        border: `1px solid ${token.colorBorder}`,
                        padding: '6px 10px',
                        background: token.colorFillSecondary,
                        fontWeight: 600,
                        textAlign: 'left',
                      }}
                    >
                      {children}
                    </th>
                  )
                },
                td({ children }) {
                  return (
                    <td
                      style={{
                        border: `1px solid ${token.colorBorder}`,
                        padding: '6px 10px',
                      }}
                    >
                      {children}
                    </td>
                  )
                },
                a({ href, children }) {
                  return (
                    <a
                      href={href}
                      target="_blank"
                      rel="noopener noreferrer"
                      style={{ color: token.colorPrimary }}
                    >
                      {children}
                    </a>
                  )
                },
                h1({ children }) {
                  return <h1 style={{ margin: '0.75em 0 0.4em', fontSize: '1.3em', fontWeight: 700 }}>{children}</h1>
                },
                h2({ children }) {
                  return <h2 style={{ margin: '0.7em 0 0.35em', fontSize: '1.15em', fontWeight: 600 }}>{children}</h2>
                },
                h3({ children }) {
                  return <h3 style={{ margin: '0.6em 0 0.3em', fontSize: '1.05em', fontWeight: 600 }}>{children}</h3>
                },
                hr() {
                  return <hr style={{ border: 'none', borderTop: `1px solid ${token.colorBorder}`, margin: '0.75em 0' }} />
                },
              }}
            >
              {msg.content}
            </ReactMarkdown>
          ) : (
            msg.content
          )}
          {!isUser && !isError && (
            <Button
              className="copy-btn"
              type="text"
              size="small"
              icon={copied ? <CheckOutlined style={{ color: token.colorSuccess }} /> : <CopyOutlined />}
              onClick={handleCopy}
              style={{
                position: 'absolute',
                top: 4,
                right: 4,
                opacity: 0,
                transition: 'opacity 0.15s ease',
                fontSize: 12,
                padding: '2px 6px',
                height: 'auto',
                color: token.colorTextSecondary,
              }}
            />
          )}
        </div>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          <Text type="secondary" style={{ fontSize: 10 }}>
            {fmt(msg.ts)}
          </Text>
          {msg.timeTaken !== undefined && (
            <Text type="secondary" style={{ fontSize: 10 }}>
              {msg.timeTaken < 1000 ? `${msg.timeTaken}ms` : `${(msg.timeTaken / 1000).toFixed(1)}s`}
            </Text>
          )}
          {msg.llmCalls !== undefined && (
            <Text type="secondary" style={{ fontSize: 10 }}>
              {msg.llmCalls} LLM call{msg.llmCalls !== 1 ? 's' : ''}
            </Text>
          )}
          {msg.toolCalls !== undefined && msg.toolCalls > 0 && (
            <Text type="secondary" style={{ fontSize: 10 }}>
              {msg.toolCalls} tool call{msg.toolCalls !== 1 ? 's' : ''}
            </Text>
          )}
        </div>
      </div>
    </div>
  )
}

// ── Typing indicator ───────────────────────────────────────────────────────

function TypingIndicator() {
  const { token } = useToken()
  return (
    <div className="typing-indicator" style={{ display: 'flex', alignItems: 'flex-end', gap: 10 }}>
      <Avatar
        size={32}
        icon={<RobotOutlined />}
        style={{ background: token.colorPrimary, flexShrink: 0 }}
      />
      <div
        style={{
          background: token.colorBgContainer,
          border: `1px solid ${token.colorBorderSecondary}`,
          borderRadius: '18px 18px 18px 4px',
          padding: '12px 16px',
          display: 'flex',
          gap: 5,
          alignItems: 'center',
        }}
      >
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="typing-dot"
            style={{ animationDelay: `${i * 0.18}s` }}
          />
        ))}
      </div>
    </div>
  )
}

// ── Tools Drawer ───────────────────────────────────────────────────────────

function ToolsDrawer({
  open,
  onClose,
  tools,
  loading,
  onRefresh,
}: {
  open: boolean
  onClose: () => void
  tools: ToolInfo[]
  loading: boolean
  onRefresh: () => void
}) {
  const { token } = useToken()
  return (
    <Drawer
      title={
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <ToolOutlined style={{ color: token.colorPrimary }} />
          <span>Active Tools</span>
          <Badge count={tools.length} style={{ marginLeft: 4 }} />
        </div>
      }
      placement="right"
      width={360}
      open={open}
      onClose={onClose}
      extra={
        <Tooltip title="Refresh">
          <Button icon={<ReloadOutlined />} type="text" onClick={onRefresh} loading={loading} size="small" />
        </Tooltip>
      }
    >
      {loading ? (
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 40 }}>
          <Spin />
        </div>
      ) : tools.length === 0 ? (
        <Empty description="No tools registered" image={Empty.PRESENTED_IMAGE_SIMPLE} />
      ) : (
        <List
          dataSource={tools}
          renderItem={(t) => (
            <List.Item style={{ padding: '12px 0', alignItems: 'flex-start' }}>
              <List.Item.Meta
                avatar={
                  <Avatar
                    icon={<ToolOutlined />}
                    size="small"
                    style={{ background: token.colorPrimary, marginTop: 2 }}
                  />
                }
                title={
                  <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap', alignItems: 'center' }}>
                    <Tag color="blue" style={{ fontFamily: 'monospace', marginBottom: 4 }}>
                      {t.name}
                    </Tag>
                    {t.serverName && (
                      <Tag color="purple" style={{ marginBottom: 4 }}>
                        {t.serverName}
                      </Tag>
                    )}
                  </div>
                }
                description={
                  <Text type="secondary" style={{ fontSize: 13, lineHeight: 1.5 }}>
                    {t.description}
                  </Text>
                }
              />
            </List.Item>
          )}
        />
      )}
    </Drawer>
  )
}

// ── Main App ───────────────────────────────────────────────────────────────

interface ChatAppProps {
  isDark: boolean
  onToggleDark: () => void
}

function ChatApp({ isDark, onToggleDark }: ChatAppProps) {
  const { token } = useToken()
  const { message: antMessage } = AntApp.useApp()

  const [sessionId] = useState(uid)
  const [messages, setMessages] = useState<Message[]>([])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)

  const [toolsOpen, setToolsOpen] = useState(false)
  const [tools, setTools] = useState<ToolInfo[]>([])
  const [toolsLoading, setToolsLoading] = useState(false)
  const [uiConfig, setUIConfig] = useState<UIConfig>({})

  const bottomRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<TextAreaRef>(null)
  const contentRef = useRef<HTMLDivElement>(null)
  const [showScrollBtn, setShowScrollBtn] = useState(false)

  // Scroll to bottom whenever messages change
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, loading])

  // Track scroll position for scroll-to-bottom button
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

  // Load UI config on mount
  useEffect(() => {
    apiGetUIConfig().then(setUIConfig).catch(() => {})
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

  const handleOpenTools = () => {
    setToolsOpen(true)
    fetchTools()
  }

  const send = useCallback(async (overrideText?: string) => {
    const text = (overrideText ?? input).trim()
    if (!text || loading) return

    setInput('')
    const userMsg: Message = { id: uid(), role: 'user', content: text, ts: new Date() }
    setMessages((prev) => [...prev, userMsg])
    setLoading(true)

    try {
      const response = await apiChat(sessionId, text)
      const assistantMsg: Message = { id: uid(), role: 'assistant', content: response.reply, ts: new Date(), timeTaken: response.time_taken_ms, llmCalls: response.llm_calls, toolCalls: response.tool_calls }
      setMessages((prev) => [...prev, assistantMsg])
    } catch (err) {
      const errMsg: Message = {
        id: uid(),
        role: 'error',
        content: err instanceof Error ? err.message : 'Something went wrong',
        ts: new Date(),
      }
      setMessages((prev) => [...prev, errMsg])
    } finally {
      setLoading(false)
    }
  }, [input, loading, sessionId])

  const handleReset = useCallback(async () => {
    await apiReset(sessionId)
    setMessages([])
    antMessage.success('Conversation cleared')
  }, [sessionId, antMessage])

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      send()
    }
  }

  const scrollToBottom = () => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }

  return (
    <Layout style={{ height: '100vh', background: token.colorBgLayout }}>
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
          <Avatar
            icon={<RobotOutlined />}
            style={{ background: token.colorPrimary }}
            size={36}
          />
          <div>
            <Text strong style={{ fontSize: 15, display: 'block', lineHeight: 1.2 }}>
              Chatbot
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
              style={{ color: token.colorTextSecondary }}
            />
          </Tooltip>
          <Tooltip title="Active tools">
            <Badge count={tools.length} size="small">
              <Button
                icon={<ToolOutlined />}
                onClick={handleOpenTools}
                type="text"
                style={{ color: token.colorTextSecondary }}
              />
            </Badge>
          </Tooltip>
          <Tooltip title="New conversation">
            <Button
              icon={<PlusOutlined />}
              onClick={handleReset}
              type="text"
              style={{ color: token.colorTextSecondary }}
            />
          </Tooltip>
          <Tooltip title="GitHub">
            <Button
              icon={<GithubOutlined />}
              href="https://github.com/anomalyco/chatbot"
              target="_blank"
              type="text"
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
          style={{
            width: '100%',
            maxWidth: 900,
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
                    style={{
                      padding: '6px 14px',
                      fontSize: 13,
                      cursor: 'pointer',
                      borderRadius: 16,
                      border: `1px solid ${token.colorBorder}`,
                      background: token.colorBgContainer,
                      color: token.colorText,
                    }}
                    onClick={() => {
                      setInput(prompt)
                      setTimeout(() => send(prompt), 0)
                    }}
                  >
                    {prompt}
                  </Tag>
                ))}
              </div>
            </div>
          )}

          {messages.map((msg) => (
            <Bubble key={msg.id} msg={msg} />
          ))}

          {loading && <TypingIndicator />}

          <div ref={bottomRef} />
        </div>

        {/* Scroll-to-bottom button */}
        {showScrollBtn && (
          <Button
            type="primary"
            shape="circle"
            icon={<DownOutlined />}
            onClick={scrollToBottom}
            style={{
              position: 'absolute',
              bottom: 16,
              right: 24,
              width: 40,
              height: 40,
              boxShadow: token.boxShadow,
              zIndex: 5,
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
        <div
          style={{
            maxWidth: 900,
            margin: '0 auto',
            display: 'flex',
            gap: 10,
            alignItems: 'center',
          }}
        >
          <TextArea
            ref={inputRef}
            value={input}
            onChange={(e) => {
              if (e.target.value.length <= 4000) {
                setInput(e.target.value)
              }
            }}
            onKeyDown={handleKeyDown}
            placeholder="Type a message… (Enter to send, Shift+Enter for newline)"
            autoSize={{ minRows: 2, maxRows: 6 }}
            disabled={loading}
            autoFocus
            style={{
              flex: 1,
              borderRadius: 12,
              resize: 'none',
              fontSize: 15,
              padding: '12px 16px',
            }}
          />
          <Tooltip title="Send">
            <Button
              type="primary"
              icon={<SendOutlined />}
              onClick={() => send()}
              disabled={!input.trim()}
              style={{
                height: 42,
                width: 42,
                borderRadius: 12,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                flexShrink: 0,
              }}
            />
          </Tooltip>
        </div>
        <div style={{ textAlign: 'center', marginTop: 8 }}>
          <Text type="secondary" style={{ fontSize: 11 }}>
            {uiConfig.aiDisclaimer || 'AI can make mistakes. Verify important info.'}
          </Text>
        </div>
      </div>

      {/* ── Tools Drawer ── */}
      <ToolsDrawer
        open={toolsOpen}
        onClose={() => setToolsOpen(false)}
        tools={tools}
        loading={toolsLoading}
        onRefresh={fetchTools}
      />
    </Layout>
  )
}

// ── Root with ConfigProvider ───────────────────────────────────────────────

export default function App() {
  const [isDark, setIsDark] = useState(false)

  return (
    <ConfigProvider
      theme={{
        algorithm: isDark ? theme.darkAlgorithm : theme.defaultAlgorithm,
        token: {
          colorPrimary: '#5b21b6',
          borderRadius: 8,
          fontFamily: "'Open Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
        },
      }}
    >
      <AntApp>
        <ChatApp isDark={isDark} onToggleDark={() => setIsDark(!isDark)} />
      </AntApp>
    </ConfigProvider>
  )
}
