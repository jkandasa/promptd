import {
  App as AntApp,
  Avatar,
  Badge,
  Button,
  Collapse,
  ConfigProvider,
  Divider,
  Drawer,
  Empty,
  Input,
  Layout,
  List,
  Modal,
  Popconfirm,
  Select,
  Spin,
  Table,
  Tag,
  Timeline,
  Tooltip,
  Typography,
  theme,
} from 'antd'
import {
  CheckCircleOutlined,
  CheckOutlined,
  CopyOutlined,
  DeleteOutlined,
  DownOutlined,
  EditOutlined,
  FileOutlined,
  FileTextOutlined,
  GithubOutlined,
  MenuFoldOutlined,
  MenuUnfoldOutlined,
  MessageOutlined,
  MoonOutlined,
  PaperClipOutlined,
  PlusOutlined,
  PushpinFilled,
  PushpinOutlined,
  ReloadOutlined,
  RobotOutlined,
  SendOutlined,
  SunOutlined,
  ToolOutlined,
  UserOutlined,
} from '@ant-design/icons'
import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react'

import ReactMarkdown from 'react-markdown'
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter'
import type { TextAreaRef } from 'antd/es/input/TextArea'
import remarkGfm from 'remark-gfm'
import { vscDarkPlus } from 'react-syntax-highlighter/dist/esm/styles/prism'

const { Content, Sider } = Layout
const { Text } = Typography
const { TextArea } = Input
const { useToken } = theme

// ── Types ──────────────────────────────────────────────────────────────────

type Role = 'user' | 'assistant' | 'error'

interface UploadedFile {
  id: string
  filename: string
  size: number
  url: string
  created_at: number
}

// ── LLM Trace types ────────────────────────────────────────────────────────

interface TraceToolCall {
  id: string
  name: string
  args: string
}

interface TraceMessage {
  role: string
  content?: string
  refusal?: string
  reasoning_content?: string
  name?: string
  tool_call_id?: string
  tool_calls?: TraceToolCall[]
}

interface ToolResult {
  name: string
  args: string
  result: string
  duration_ms: number
}

interface TraceToolDef {
  name: string
  description: string
}

interface TokenUsage {
  prompt_tokens: number
  completion_tokens: number
  total_tokens: number
  reasoning_tokens?: number
  cached_tokens?: number
}

interface LLMRound {
  request: TraceMessage[]
  response: TraceMessage
  llm_duration_ms: number
  tool_results?: ToolResult[]
  available_tools?: TraceToolDef[]
  usage?: TokenUsage
}

// ── Message ────────────────────────────────────────────────────────────────

interface Message {
  id: string
  role: Role
  content: string
  ts: Date
  timeTaken?: number
  llmCalls?: number
  toolCalls?: number
  model?: string
  files?: UploadedFile[]
  msgId?: string  // persisted storage ID (undefined for error messages or pre-persistence)
  trace?: LLMRound[]
}

interface ToolInfo {
  name: string
  description: string
}

interface UIConfig {
  appName?: string
  appIcon?: string
  welcomeTitle?: string
  aiDisclaimer?: string
  promptSuggestions?: string[]
  systemPrompts?: SystemPrompt[]
}

interface SystemPrompt {
  name: string
}

interface ConversationMeta {
  id: string
  title: string
  model: string
  system_prompt?: string
  pinned?: boolean
  created_at: string
  updated_at: string
}

interface StorageMessage {
  id: string
  role: string
  content: string
  sent_at: string
  model?: string
  time_taken_ms?: number
  llm_calls?: number
  tool_calls?: number
  trace?: LLMRound[]
}

interface ConversationDetail extends ConversationMeta {
  messages: StorageMessage[]
}

function getFirstSystemPromptName(cfg: UIConfig): string {
  return getSortedSystemPrompts(cfg)[0]?.name || ''
}

function getSortedSystemPrompts(cfg: UIConfig): SystemPrompt[] {
  return [...(cfg.systemPrompts || [])].sort((a, b) => {
    return a.name.localeCompare(b.name)
  })
}

function isKnownSystemPrompt(cfg: UIConfig, name?: string): boolean {
  if (!name) return false
  return getSortedSystemPrompts(cfg).some((prompt) => prompt.name === name)
}

function isImageIcon(icon?: string): boolean {
  if (!icon) return false
  return /^(https?:\/\/|\/|data:image\/)/.test(icon)
}

// ── API helpers ────────────────────────────────────────────────────────────

async function apiListTools(): Promise<ToolInfo[]> {
  const res = await fetch('/tools')
  if (!res.ok) return []
  const data: { tools: { name: string; description: string }[] } = await res.json()
  return data.tools?.map((t) => ({ name: t.name, description: t.description })) ?? []
}

async function apiGetUIConfig(): Promise<UIConfig> {
  const res = await fetch('/ui-config')
  if (!res.ok) return {}
  return res.json()
}

type ChatResponse = {
  reply: string
  model: string
  time_taken_ms: number
  llm_calls: number
  tool_calls: number
  files?: UploadedFile[]
  user_msg_id?: string
  assistant_msg_id?: string
  trace?: LLMRound[]
}

class ChatError extends Error {
  model?: string
  constructor(message: string, model?: string) {
    super(message)
    this.name = 'ChatError'
    this.model = model
  }
}

interface ModelInfo {
  id: string
  name?: string
}

async function apiGetModels(): Promise<{ models: ModelInfo[]; selection_method: string }> {
  const res = await fetch('/models')
  if (!res.ok) return { models: [], selection_method: 'auto' }
  return res.json()
}

async function apiChat(sessionId: string, message: string, files?: string[], model?: string, systemPrompt?: string): Promise<ChatResponse> {
  const res = await fetch('/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ session_id: sessionId, message, files, model, system_prompt: systemPrompt }),
  })
  const data = await res.json()
  if (!res.ok) throw new ChatError(data.error || 'Request failed', data.model)
  return data as ChatResponse
}

async function apiUploadFile(file: File): Promise<UploadedFile> {
  const formData = new FormData()
  formData.append('file', file)
  const res = await fetch('/upload', {
    method: 'POST',
    body: formData,
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'Upload failed')
  return data as UploadedFile
}

async function apiListConversations(): Promise<ConversationMeta[]> {
  const res = await fetch('/conversations')
  if (!res.ok) return []
  return res.json()
}

async function apiLoadConversation(id: string): Promise<ConversationDetail | null> {
  const res = await fetch(`/conversations/${id}`)
  if (!res.ok) return null
  return res.json()
}

async function apiDeleteConversation(id: string): Promise<void> {
  await fetch(`/conversations/${id}`, { method: 'DELETE' })
}

async function apiRenameConversation(id: string, title: string): Promise<void> {
  await fetch(`/conversations/${id}/title`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title }),
  })
}

async function apiTogglePin(id: string): Promise<boolean> {
  const res = await fetch(`/conversations/${id}/pin`, { method: 'PATCH' })
  const data = await res.json()
  return data.pinned as boolean
}

async function apiDeleteMessage(convId: string, msgId: string): Promise<void> {
  await fetch(`/conversations/${convId}/messages/${msgId}`, { method: 'DELETE' })
}

async function apiDeleteMessagesFrom(convId: string, msgId: string): Promise<void> {
  await fetch(`/conversations/${convId}/messages/${msgId}/after`, { method: 'DELETE' })
}

// ── Utilities ──────────────────────────────────────────────────────────────

function uid(): string {
  return crypto.randomUUID()
}

function formatMessageTime(d: Date): string {
  if (isNaN(d.getTime())) return ''
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

const MAX_FILE_SIZE = 10 * 1024 * 1024 // 10 MB — matches server limit
const MAX_FILES_PER_MESSAGE = 10
const MAX_MESSAGE_LENGTH = 4000
const TYPING_DOTS = [0, 1, 2] // module-level constant to avoid per-render allocation

// Validate a URL is safe to use as href/src (no javascript: etc.)
function safeUrl(url: string | undefined): string {
  if (!url) return '#'
  try {
    const u = new URL(url, window.location.href)
    if (u.protocol === 'javascript:' || u.protocol === 'data:') return '#'
    return url
  } catch {
    return '#'
  }
}

// Linkify plain text — split on URLs and wrap each in an <a>.
const URL_RE = /https?:\/\/[^\s<>"')\]]+/g
function Linkified({ text, linkColor }: { text: string; linkColor: string }) {
  const parts: React.ReactNode[] = []
  let last = 0
  let match: RegExpExecArray | null
  URL_RE.lastIndex = 0
  while ((match = URL_RE.exec(text)) !== null) {
    if (match.index > last) parts.push(text.slice(last, match.index))
    const url = match[0]
    parts.push(
      <a
        key={match.index}
        href={safeUrl(url)}
        target="_blank"
        rel="noopener noreferrer"
        style={{ color: linkColor, textDecoration: 'underline', wordBreak: 'break-all' }}
      >
        {url}
      </a>
    )
    last = match.index + url.length
  }
  if (last < text.length) parts.push(text.slice(last))
  return <>{parts}</>
}

// ── Markdown code block renderer ───────────────────────────────────────────

function CodeBlock({ language, code }: { language?: string; code: string }) {
  const { token } = useToken()
  const { message: antMessage } = AntApp.useApp()
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(code)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      antMessage.error('Failed to copy')
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
          aria-label={copied ? 'Copied' : 'Copy code'}
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

// ── Markdown components factory — built once per theme token ────────────────

function buildMarkdownComponents(token: ReturnType<typeof useToken>['token']) {
  return {
    code({ className, children, ...props }: React.ComponentPropsWithoutRef<'code'> & { className?: string }) {
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
    pre({ children }: React.ComponentPropsWithoutRef<'pre'>) {
      return <>{children}</>
    },
    p({ children }: React.ComponentPropsWithoutRef<'p'>) {
      return <p style={{ margin: '0.5em 0' }}>{children}</p>
    },
    ul({ children }: React.ComponentPropsWithoutRef<'ul'>) {
      return <ul style={{ margin: '0.5em 0', paddingLeft: '1.5em' }}>{children}</ul>
    },
    ol({ children }: React.ComponentPropsWithoutRef<'ol'>) {
      return <ol style={{ margin: '0.5em 0', paddingLeft: '1.5em' }}>{children}</ol>
    },
    li({ children }: React.ComponentPropsWithoutRef<'li'>) {
      return <li style={{ margin: '0.25em 0' }}>{children}</li>
    },
    blockquote({ children }: React.ComponentPropsWithoutRef<'blockquote'>) {
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
    table({ children }: React.ComponentPropsWithoutRef<'table'>) {
      return (
        <div style={{ overflowX: 'auto', margin: '0.5em 0' }}>
          <table style={{ borderCollapse: 'collapse', width: '100%', fontSize: 13 }}>
            {children}
          </table>
        </div>
      )
    },
    th({ children }: React.ComponentPropsWithoutRef<'th'>) {
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
    td({ children }: React.ComponentPropsWithoutRef<'td'>) {
      return (
        <td style={{ border: `1px solid ${token.colorBorder}`, padding: '6px 10px' }}>
          {children}
        </td>
      )
    },
    a({ href, children }: React.ComponentPropsWithoutRef<'a'>) {
      return (
        <a
          href={safeUrl(href)}
          target="_blank"
          rel="noopener noreferrer"
          style={{ color: token.colorPrimary }}
        >
          {children}
        </a>
      )
    },
    h1({ children }: React.ComponentPropsWithoutRef<'h1'>) {
      return <h1 style={{ margin: '0.75em 0 0.4em', fontSize: '1.3em', fontWeight: 700 }}>{children}</h1>
    },
    h2({ children }: React.ComponentPropsWithoutRef<'h2'>) {
      return <h2 style={{ margin: '0.7em 0 0.35em', fontSize: '1.15em', fontWeight: 600 }}>{children}</h2>
    },
    h3({ children }: React.ComponentPropsWithoutRef<'h3'>) {
      return <h3 style={{ margin: '0.6em 0 0.3em', fontSize: '1.05em', fontWeight: 600 }}>{children}</h3>
    },
    hr() {
      return <hr style={{ border: 'none', borderTop: `1px solid ${token.colorBorder}`, margin: '0.75em 0' }} />
    },
  }
}

// ── TraceDrawer component ──────────────────────────────────────────────────

// Role badge colours matching standard OpenAI roles.
const ROLE_COLORS: Record<string, string> = {
  system:    '#8c8c8c',
  user:      '#1677ff',
  assistant: '#52c41a',
  tool:      '#fa8c16',
}

function RoleBadge({ role }: { role: string }) {
  const color = ROLE_COLORS[role] ?? '#595959'
  return (
    <Tag color={color} style={{ fontSize: 11, marginBottom: 4, textTransform: 'uppercase', letterSpacing: '0.04em' }}>
      {role}
    </Tag>
  )
}

function TraceMessageCard({ msg, token }: { msg: TraceMessage; token: ReturnType<typeof useToken>['token'] }) {
  return (
    <div style={{
      border: `1px solid ${token.colorBorderSecondary}`,
      borderRadius: 6,
      padding: '8px 10px',
      marginBottom: 6,
      background: token.colorFillAlter,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
        <RoleBadge role={msg.role} />
        {msg.name && (
          <Text type="secondary" style={{ fontSize: 11 }}>({msg.name})</Text>
        )}
        {msg.tool_call_id && (
          <Text type="secondary" style={{ fontSize: 10, fontFamily: 'monospace' }}>id:{msg.tool_call_id}</Text>
        )}
      </div>

      {msg.content && (
        <pre style={{
          margin: '4px 0 0',
          whiteSpace: 'pre-wrap',
          wordBreak: 'break-word',
          fontSize: 12,
          fontFamily: 'monospace',
          maxHeight: 300,
          overflowY: 'auto',
          color: token.colorText,
        }}>{msg.content}</pre>
      )}
      {msg.reasoning_content && (
        <details style={{ marginTop: 4 }}>
          <summary style={{ fontSize: 11, color: token.colorTextSecondary, cursor: 'pointer', userSelect: 'none' }}>
            reasoning ({msg.reasoning_content.length} chars)
          </summary>
          <pre style={{
            margin: '4px 0 0',
            whiteSpace: 'pre-wrap',
            wordBreak: 'break-word',
            fontSize: 12,
            fontFamily: 'monospace',
            maxHeight: 300,
            overflowY: 'auto',
            color: token.colorTextSecondary,
            borderLeft: `2px solid ${token.colorBorderSecondary}`,
            paddingLeft: 8,
          }}>{msg.reasoning_content}</pre>
        </details>
      )}
      {msg.refusal && (
        <pre style={{
          margin: '4px 0 0',
          whiteSpace: 'pre-wrap',
          wordBreak: 'break-word',
          fontSize: 12,
          fontFamily: 'monospace',
          maxHeight: 200,
          overflowY: 'auto',
          color: token.colorError,
        }}>[refusal] {msg.refusal}</pre>
      )}
      {msg.tool_calls && msg.tool_calls.length > 0 && (
        <div style={{ marginTop: 6 }}>
          {msg.tool_calls.map((tc, i) => (
            <div key={i} style={{
              background: token.colorFillSecondary,
              borderRadius: 4,
              padding: '4px 8px',
              marginBottom: 4,
              fontSize: 12,
              fontFamily: 'monospace',
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <Text strong style={{ fontSize: 12 }}>→ calls {tc.name}</Text>
                <Text type="secondary" style={{ fontSize: 10, fontFamily: 'monospace' }}>id:{tc.id}</Text>
              </div>
              <pre style={{ margin: '2px 0 0', whiteSpace: 'pre-wrap', wordBreak: 'break-word', fontSize: 12, color: token.colorText }}>
                {(() => { try { return JSON.stringify(JSON.parse(tc.args), null, 2) } catch { return tc.args } })()}
              </pre>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function TraceDrawer({ open, onClose, rounds }: {
  open: boolean
  onClose: () => void
  rounds?: LLMRound[]
}) {
  const { token } = useToken()
  if (!rounds?.length) return null

  const fmtMs = (ms: number) => ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`

  const timelineItems = rounds.map((round, idx) => {
    const hasTools = (round.tool_results?.length ?? 0) > 0
    const toolCount = round.tool_results?.length ?? 0
    const totalToolMs = round.tool_results?.reduce((s, t) => s + t.duration_ms, 0) ?? 0
    const isFinal = !hasTools

    // Build collapse panels for the sections inside this round
    const collapseItems = [
      ...(round.available_tools && round.available_tools.length > 0 ? [{
        key: 'available_tools',
        label: (
          <Text style={{ fontSize: 12 }}>
            Available Tools
            <Text type="secondary" style={{ fontSize: 11, marginLeft: 6 }}>({round.available_tools.length})</Text>
          </Text>
        ),
        children: (
          <Table
            size="small"
            pagination={false}
            rowKey="name"
            dataSource={round.available_tools}
            showHeader={false}
            style={{
              border: `1px solid ${token.colorBorderSecondary}`,
              borderRadius: 6,
              overflow: 'hidden',
              background: token.colorFillAlter,
            }}
            columns={[
              {
                title: 'Name',
                dataIndex: 'name',
                key: 'name',
                width: 240,
                render: (name: string) => (
                  <Text strong style={{ fontSize: 12, fontFamily: 'monospace' }}>{name}</Text>
                ),
              },
              {
                title: 'Description',
                dataIndex: 'description',
                key: 'description',
                render: (description: string) => (
                  <Text type="secondary" style={{ fontSize: 12 }}>{description}</Text>
                ),
              },
            ]}
          />
        ),
      }] : []),
      {
        key: 'messages',
        label: (
          <Text style={{ fontSize: 12 }}>
            Messages Sent
            <Text type="secondary" style={{ fontSize: 11, marginLeft: 6 }}>({round.request.length})</Text>
          </Text>
        ),
        children: (
          <div style={{
            border: `1px solid ${token.colorBorderSecondary}`,
            borderRadius: 6,
            maxHeight: 320,
            overflowY: 'auto',
            background: token.colorFillAlter,
          }}>
            {round.request.map((msg, mi) => (
              <div key={mi} style={{
                display: 'flex',
                gap: 8,
                padding: '5px 10px',
                borderBottom: mi < round.request.length - 1 ? `1px solid ${token.colorBorderSecondary}` : undefined,
                alignItems: 'flex-start',
              }}>
                <Tag color={ROLE_COLORS[msg.role] ?? '#595959'} style={{
                  fontSize: 10,
                  marginTop: 1,
                  flexShrink: 0,
                  textTransform: 'uppercase',
                  letterSpacing: '0.04em',
                  lineHeight: '16px',
                }}>
                  {msg.role}
                </Tag>
                <pre style={{
                  margin: 0,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  whiteSpace: 'pre-wrap',
                  wordBreak: 'break-word',
                  color: token.colorText,
                  flex: 1,
                }}>
                  {msg.tool_calls && msg.tool_calls.length > 0
                    ? msg.tool_calls.map(tc => `→ calls ${tc.name}  [id:${tc.id}]\n${(() => { try { return JSON.stringify(JSON.parse(tc.args), null, 2) } catch { return tc.args } })()}`).join('\n\n')
                    : msg.content || ''}
                  {msg.tool_call_id && (
                    <Text type="secondary" style={{ fontSize: 10, fontFamily: 'monospace', display: 'block' }}>
                      id:{msg.tool_call_id}
                    </Text>
                  )}
                </pre>
              </div>
            ))}
          </div>
        ),
      },
      {
        key: 'decision',
        label: (
          <Text style={{ fontSize: 12 }}>
            {isFinal ? 'LLM Response' : 'LLM Decision'}
            <Text type="secondary" style={{ fontSize: 11, marginLeft: 6 }}>{fmtMs(round.llm_duration_ms)}</Text>
          </Text>
        ),
        children: <TraceMessageCard msg={round.response} token={token} />,
      },
      ...(hasTools ? [{
        key: 'tools',
        label: (
          <Text style={{ fontSize: 12 }}>
            Tool Execution
            <Text type="secondary" style={{ fontSize: 11, marginLeft: 6 }}>
              {toolCount} call{toolCount === 1 ? '' : 's'} · {fmtMs(totalToolMs)}
            </Text>
          </Text>
        ),
        children: (
          <div>
            {round.tool_results!.map((tr, ti) => (
              <div key={ti} style={{
                border: `1px solid ${token.colorBorderSecondary}`,
                borderRadius: 6,
                padding: '8px 10px',
                marginBottom: 6,
                background: token.colorFillAlter,
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
                  <Tag color="orange" style={{ fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.04em', margin: 0 }}>
                    {tr.name}
                  </Tag>
                  <Text type="secondary" style={{ fontSize: 11 }}>{fmtMs(tr.duration_ms)}</Text>
                </div>
                <div style={{ marginTop: 4 }}>
                  <Text type="secondary" style={{ fontSize: 11 }}>Args: </Text>
                  <pre style={{ display: 'inline', fontSize: 12, fontFamily: 'monospace', color: token.colorText }}>
                    {(() => { try { return JSON.stringify(JSON.parse(tr.args), null, 2) } catch { return tr.args } })()}
                  </pre>
                </div>
                <div style={{ marginTop: 4 }}>
                  <Text type="secondary" style={{ fontSize: 11 }}>Result: </Text>
                  <pre style={{
                    margin: '2px 0 0',
                    whiteSpace: 'pre-wrap',
                    wordBreak: 'break-word',
                    fontSize: 12,
                    fontFamily: 'monospace',
                    maxHeight: 200,
                    overflowY: 'auto',
                    color: token.colorText,
                  }}>{tr.result}</pre>
                </div>
              </div>
            ))}
          </div>
        ),
      }] : []),
    ]

    return {
      dot: isFinal
        ? <CheckCircleOutlined style={{ fontSize: 16, color: token.colorSuccess }} />
        : <ToolOutlined style={{ fontSize: 14, color: token.colorWarning }} />,
      color: isFinal ? 'green' : 'orange',
      children: (
        <div style={{ paddingBottom: 8 }}>
          <Collapse
            size="small"
            defaultActiveKey={[]}
            style={{ background: 'transparent' }}
            items={[{
              key: 'round',
              label: (
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
                  <Text strong style={{ fontSize: 13 }}>
                    Round {idx + 1} — {isFinal ? 'final answer' : `${toolCount} tool call${toolCount === 1 ? '' : 's'}`}
                  </Text>
                  <Tag color="blue" style={{ fontSize: 11, margin: 0 }}>LLM {fmtMs(round.llm_duration_ms)}</Tag>
                  {hasTools && (
                    <Tag color="orange" style={{ fontSize: 11, margin: 0 }}>tools {fmtMs(totalToolMs)}</Tag>
                  )}
                  {round.usage && (
                    <Text type="secondary" style={{ fontSize: 11 }}>
                      {round.usage.prompt_tokens}↑ {round.usage.completion_tokens}↓ tok
                      {(round.usage.reasoning_tokens ?? 0) > 0 && ` (${round.usage.reasoning_tokens} reasoning)`}
                      {(round.usage.cached_tokens ?? 0) > 0 && ` (${round.usage.cached_tokens} cached)`}
                    </Text>
                  )}
                </span>
              ),
              children: (
                <Collapse
                  size="small"
                  defaultActiveKey={[]}
                  items={collapseItems}
                  style={{ background: 'transparent' }}
                />
              ),
            }]}
          />
        </div>
      ),
    }
  })

  return (
    <Drawer
      title={
        <span>
          LLM Trace
          <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
            {rounds.length} round{rounds.length === 1 ? '' : 's'}
          </Text>
        </span>
      }
      placement="right"
      width="min(960px, 90vw)"
      open={open}
      onClose={onClose}
      styles={{ body: { padding: '16px 24px' } }}
    >
      <Timeline items={timelineItems} />
    </Drawer>
  )
}

// ── Bubble component ───────────────────────────────────────────────────────

const Bubble = memo(function Bubble({
  msg,
  onDelete,
  onEdit,
}: {
  msg: Message
  onDelete: (id: string) => void
  onEdit: (id: string, newContent: string) => void
}) {
  const { token } = useToken()
  const { message: antMessage } = AntApp.useApp()
  const isUser = msg.role === 'user'
  const isError = msg.role === 'error'
  const [copied, setCopied] = useState(false)
  const [traceOpen, setTraceOpen] = useState(false)
  const [isEditing, setIsEditing] = useState(false)
  const [editText, setEditText] = useState(msg.content)
  const [isHovered, setIsHovered] = useState(false)
  const [previewVisible, setPreviewVisible] = useState(false)
  const [previewImage, setPreviewImage] = useState('')

  // Memoize markdown components per theme token to avoid re-creating on every render.
  const mdComponents = useMemo(() => buildMarkdownComponents(token), [token])

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(msg.content)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      antMessage.error('Failed to copy')
    }
  }

  const isImageFile = (filename: string) => {
    const dotIdx = filename.lastIndexOf('.')
    if (dotIdx < 0) return false
    const ext = filename.slice(dotIdx + 1).toLowerCase()
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].includes(ext)
  }

  const handleImageClick = (url: string) => {
    setPreviewImage(url)
    setPreviewVisible(true)
  }

  const bubbleStyle: React.CSSProperties = isUser
    ? {
        background: token.colorPrimary,
        color: '#fff',
        borderRadius: '18px 18px 4px 18px',
        padding: '10px 18px 10px 16px',
        maxWidth: '80%',
        whiteSpace: 'pre-wrap',
        fontSize: 14,
        lineHeight: 1.5,
        boxShadow: token.boxShadow,
      }
    : isError
    ? {
        background: token.colorErrorBg,
        color: token.colorError,
        border: `1px solid ${token.colorErrorBorder}`,
        borderRadius: 8,
        padding: '8px 12px',
        width: '100%',
        whiteSpace: 'pre-wrap',
        fontSize: 13,
        lineHeight: 1.5,
      }
    : {
        // Assistant: no bubble box — full width, flush left, like ChatGPT
        width: '100%',
        color: token.colorText,
        fontSize: 14,
        lineHeight: 1.7,
      }

  const handleEditSubmit = () => {
    const trimmed = editText.trim()
    if (trimmed) {
      onEdit(msg.id, trimmed)
    }
    setIsEditing(false)
  }

  // Shared action toolbar — copy + edit (user only) + delete, shown on hover.
  const actionBar = (
    <div
      style={{
        opacity: isHovered ? 1 : 0,
        transition: 'opacity 0.15s ease',
        display: 'flex',
        gap: 2,
        marginTop: 2,
      }}
    >
      <Button
        className="copy-btn"
        type="text"
        size="small"
        aria-label={copied ? 'Copied' : 'Copy message'}
        icon={copied ? <CheckOutlined style={{ color: token.colorSuccess }} /> : <CopyOutlined />}
        onClick={handleCopy}
        style={{ fontSize: 12, padding: '2px 6px', height: 'auto', color: token.colorTextSecondary }}
      />
      {isUser && (
        <Button
          type="text"
          size="small"
          aria-label="Edit message"
          icon={<EditOutlined />}
          onClick={() => { setEditText(msg.content); setIsEditing(true) }}
          style={{ fontSize: 12, padding: '2px 6px', height: 'auto', color: token.colorTextSecondary }}
        />
      )}
      <Popconfirm
        title="Delete this message?"
        onConfirm={() => onDelete(msg.id)}
        okText="Delete"
        okType="danger"
        placement={isUser ? 'topRight' : 'topLeft'}
      >
        <Button
          type="text"
          size="small"
          danger
          aria-label="Delete message"
          icon={<DeleteOutlined />}
          style={{ fontSize: 12, padding: '2px 6px', height: 'auto' }}
        />
      </Popconfirm>
    </div>
  )

  return (
    <div
      className="bubble-enter"
      role={isError ? 'alert' : undefined}
      style={{
        display: 'flex',
        flexDirection: isUser ? 'row-reverse' : 'row',
        alignItems: isUser ? 'flex-end' : 'flex-start',
        gap: 10,
        padding: '4px 0',
      }}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      {!isUser && !isError && (
        <Avatar
          aria-hidden="true"
          size={32}
          icon={<RobotOutlined />}
          style={{ background: token.colorPrimary, flexShrink: 0, marginTop: 2 }}
        />
      )}
      {isUser && (
        <Avatar
          aria-hidden="true"
          size={32}
          icon={<UserOutlined />}
          style={{ background: token.colorTextSecondary, flexShrink: 0, marginBottom: 2 }}
        />
      )}
      {isError && (
        <Avatar
          aria-hidden="true"
          size={32}
          icon={<RobotOutlined />}
          style={{ background: token.colorError, flexShrink: 0, marginTop: 2 }}
        />
      )}

      <div style={{ display: 'flex', flexDirection: 'column', alignItems: isUser ? 'flex-end' : 'flex-start', gap: 3, flex: isUser ? undefined : 1, minWidth: 0 }}>
        {isEditing ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, width: '100%', maxWidth: '80%' }}>
            <TextArea
              autoFocus
              value={editText}
              onChange={(e) => setEditText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleEditSubmit() }
                if (e.key === 'Escape') { setIsEditing(false) }
              }}
              autoSize={{ minRows: 2, maxRows: 10 }}
              style={{ borderRadius: 8, fontSize: 14 }}
            />
            <div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
              <Button size="small" onClick={() => setIsEditing(false)}>Cancel</Button>
              <Button size="small" type="primary" onClick={handleEditSubmit} disabled={!editText.trim()}>
                Send
              </Button>
            </div>
          </div>
        ) : (
          <>
            <div
              className="bubble-content"
              style={{ ...bubbleStyle, position: isUser || isError ? 'relative' : undefined }}
            >
              {!isUser && !isError ? (
                <div style={{ wordBreak: 'break-word' }}>
                  <ReactMarkdown
                    remarkPlugins={[remarkGfm]}
                    components={mdComponents}
                  >
                    {msg.content}
                  </ReactMarkdown>
                </div>
              ) : (
                <Linkified
                  text={msg.content}
                  linkColor={isUser ? 'rgba(255,255,255,0.9)' : token.colorError}
                />
              )}
            </div>

            {/* Action toolbar — hover-revealed, same layout for all roles */}
            {actionBar}
          </>
        )}

        {msg.files && msg.files.length > 0 && (
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 8 }}>
            {msg.files.map((file) => (
              isImageFile(file.filename) ? (
                <img
                  key={file.id}
                  src={safeUrl(file.url)}
                  alt={file.filename}
                  role="button"
                  tabIndex={0}
                  onClick={() => handleImageClick(safeUrl(file.url))}
                  onKeyDown={(e) => e.key === 'Enter' && handleImageClick(safeUrl(file.url))}
                  style={{
                    maxWidth: 200,
                    maxHeight: 150,
                    borderRadius: 4,
                    cursor: 'pointer',
                    objectFit: 'cover',
                  }}
                />
              ) : (
                <a
                  key={file.id}
                  href={safeUrl(file.url)}
                  download={file.filename}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 4,
                    padding: '4px 8px',
                    borderRadius: 4,
                    background: token.colorFillSecondary,
                    color: token.colorText,
                    textDecoration: 'none',
                    fontSize: 12,
                  }}
                >
                  <FileOutlined /> {file.filename}
                </a>
              )
            ))}
          </div>
        )}
        <Modal
          open={previewVisible}
          footer={null}
          onCancel={() => { setPreviewVisible(false); setPreviewImage('') }}
          width="90vw"
          centered
        >
          <img
            alt="preview"
            style={{ width: '100%', maxHeight: '80vh', objectFit: 'contain' }}
            src={previewImage}
          />
        </Modal>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
          <Tooltip title={isNaN(msg.ts.getTime()) ? undefined : msg.ts.toLocaleString([], { dateStyle: 'medium', timeStyle: 'medium' })}>
            <Text type="secondary" style={{ fontSize: 10, cursor: 'default' }}>
              {formatMessageTime(msg.ts)}
            </Text>
          </Tooltip>
          {msg.model !== undefined && (
            isError
              ? <Tag color="error" style={{ fontSize: 10, margin: 0 }}>{msg.model}</Tag>
              : <Text type="secondary" style={{ fontSize: 10 }}>{msg.model}</Text>
          )}
          {msg.timeTaken !== undefined && (
            <Text type="secondary" style={{ fontSize: 10 }}>
              {msg.timeTaken < 1000 ? `${msg.timeTaken}ms` : `${(msg.timeTaken / 1000).toFixed(1)}s`}
            </Text>
          )}
          {msg.llmCalls !== undefined && (
            msg.trace?.length
              ? <Typography.Link style={{ fontSize: 10 }} onClick={() => setTraceOpen(true)}>
                  {msg.llmCalls} LLM call{msg.llmCalls === 1 ? '' : 's'}
                </Typography.Link>
              : <Text type="secondary" style={{ fontSize: 10 }}>
                  {msg.llmCalls} LLM call{msg.llmCalls === 1 ? '' : 's'}
                </Text>
          )}
          {msg.toolCalls !== undefined && (
            <Text type="secondary" style={{ fontSize: 10 }}>
              {msg.toolCalls} tool call{msg.toolCalls === 1 ? '' : 's'}
            </Text>
          )}
          {(() => {
            if (!msg.trace?.length) return null
            let prompt = 0, completion = 0, reasoning = 0, cached = 0
            for (const r of msg.trace) {
              if (r.usage) {
                prompt += r.usage.prompt_tokens
                completion += r.usage.completion_tokens
                reasoning += r.usage.reasoning_tokens ?? 0
                cached += r.usage.cached_tokens ?? 0
              }
            }
            if (prompt === 0 && completion === 0) return null
            const extra = [
              reasoning > 0 ? `${reasoning} reasoning` : '',
              cached > 0 ? `${cached} cached` : '',
            ].filter(Boolean).join(', ')
            return (
              <Text type="secondary" style={{ fontSize: 10 }}>
                {prompt}↑ {completion}↓ tok{extra ? ` (${extra})` : ''}
              </Text>
            )
          })()}
        </div>
        <TraceDrawer open={traceOpen} onClose={() => setTraceOpen(false)} rounds={msg.trace} />
      </div>
    </div>
  )
})

// ── Typing indicator ───────────────────────────────────────────────────────

function TypingIndicator() {
  const { token } = useToken()
  return (
    <div className="typing-indicator" style={{ display: 'flex', alignItems: 'flex-end', gap: 10 }}>
      <Avatar
        aria-hidden="true"
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
        <span className="sr-only">Assistant is typing…</span>
        {TYPING_DOTS.map((i) => (
          <span
            key={i}
            aria-hidden="true"
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
  const [search, setSearch] = useState('')
  const q = search.trim().toLowerCase()
  const filtered = q
    ? tools.filter(t => t.name.toLowerCase().includes(q) || t.description.toLowerCase().includes(q))
    : tools

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
          <Button
            icon={<ReloadOutlined />}
            type="text"
            onClick={onRefresh}
            loading={loading}
            size="small"
            aria-label="Refresh tools"
          />
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
        <>
          <Input.Search
            placeholder="Search by name or description"
            value={search}
            onChange={e => setSearch(e.target.value)}
            allowClear
            size="small"
            style={{ marginBottom: 12 }}
          />
          {filtered.length === 0 ? (
            <Empty description="No matching tools" image={Empty.PRESENTED_IMAGE_SIMPLE} />
          ) : (
            <List
              dataSource={filtered}
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
                      <Tag color="blue" style={{ fontFamily: 'monospace', marginBottom: 4 }}>
                        {t.name}
                      </Tag>
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
        </>
      )}
    </Drawer>
  )
}

// ── ConvItem — sidebar conversation row ────────────────────────────────────

interface ConvItemProps {
  conv: ConversationMeta
  isActive: boolean
  editingConvId: string | null
  editingTitle: string
  token: ReturnType<typeof useToken>['token']
  onLoad: (id: string) => void
  onStartEdit: (id: string, title: string) => void
  onConfirmEdit: () => void
  onCancelEdit: () => void
  onEditTitleChange: (v: string) => void
  onTogglePin: (id: string) => void
  onDelete: (id: string) => void
}

function ConvItem({
  conv,
  isActive,
  editingConvId,
  editingTitle,
  token,
  onLoad,
  onStartEdit,
  onConfirmEdit,
  onCancelEdit,
  onEditTitleChange,
  onTogglePin,
  onDelete,
}: ConvItemProps) {
  const isEditing = editingConvId === conv.id
  const activeBg = token.colorPrimary
  const activeText = '#fff'
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 4,
        padding: '5px 6px',
        borderRadius: 8,
        cursor: 'pointer',
        background: isActive ? activeBg : 'transparent',
        border: `1px solid ${isActive ? token.colorPrimary : 'transparent'}`,
        marginBottom: 2,
      }}
      onClick={() => { if (!isEditing) onLoad(conv.id) }}
    >
      <MessageOutlined
        style={{
          color: isActive ? activeText : token.colorTextSecondary,
          fontSize: 13,
          flexShrink: 0,
        }}
      />
      {isEditing ? (
        <Input
          size="small"
          value={editingTitle}
          autoFocus
          onChange={(e) => onEditTitleChange(e.target.value)}
          onPressEnter={onConfirmEdit}
          onBlur={onConfirmEdit}
          onKeyDown={(e) => { if (e.key === 'Escape') onCancelEdit() }}
          onClick={(e) => e.stopPropagation()}
          style={{ flex: 1, fontSize: 12, height: 24 }}
        />
      ) : (
        <Text
          ellipsis
          style={{
            flex: 1,
            fontSize: 13,
            fontWeight: isActive ? 600 : 400,
            color: isActive ? activeText : token.colorText,
          }}
        >
          {conv.title || 'Untitled'}
        </Text>
      )}
      {/* Action buttons — always rendered but hidden via opacity to preserve layout */}
      <div
        style={{ display: 'flex', gap: 2, flexShrink: 0 }}
        onClick={(e) => e.stopPropagation()}
      >
        <Tooltip title={conv.pinned ? 'Unpin' : 'Pin'}>
          <Button
            type="text"
            size="small"
            icon={conv.pinned ? <PushpinFilled style={{ color: token.colorPrimary }} /> : <PushpinOutlined />}
            onClick={() => onTogglePin(conv.id)}
            aria-label={conv.pinned ? 'Unpin conversation' : 'Pin conversation'}
            style={{ width: 22, height: 22, padding: 0, color: isActive ? activeText : token.colorTextSecondary }}
          />
        </Tooltip>
        <Tooltip title="Rename">
          <Button
            type="text"
            size="small"
            icon={<EditOutlined />}
            onClick={() => onStartEdit(conv.id, conv.title || '')}
            aria-label="Rename conversation"
            style={{ width: 22, height: 22, padding: 0, color: isActive ? activeText : token.colorTextSecondary }}
          />
        </Tooltip>
        <Popconfirm
          title="Delete this conversation?"
          onConfirm={() => onDelete(conv.id)}
          okText="Delete"
          okType="danger"
          placement="right"
        >
          <Button
            type="text"
            size="small"
            danger
            icon={<DeleteOutlined />}
            aria-label="Delete conversation"
            style={{ width: 22, height: 22, padding: 0 }}
          />
        </Popconfirm>
      </div>
    </div>
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

  // Persist session ID in sessionStorage so it survives in-tab navigations
  // but starts fresh on a new tab/window.
  const [sessionId, setSessionId] = useState(() => {
    const stored = sessionStorage.getItem('chatSessionId')
    if (stored) return stored
    const id = uid()
    sessionStorage.setItem('chatSessionId', id)
    return id
  })
  const [messages, setMessages] = useState<Message[]>([])
  const messagesRef = useRef<Message[]>([]) // ref mirror so handleEditMessage can read current messages synchronously
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const loadingRef = useRef(false) // ref mirror so callbacks don't need loading in deps
  const [models, setModels] = useState<ModelInfo[]>([])
  const [selectedModel, setSelectedModel] = useState<string>('auto')
  const [selectedSystemPrompt, setSelectedSystemPrompt] = useState<string>('')

  const [toolsOpen, setToolsOpen] = useState(false)
  const [tools, setTools] = useState<ToolInfo[]>([])
  const [toolsLoading, setToolsLoading] = useState(false)
  const [uiConfig, setUIConfig] = useState<UIConfig>({})
  const [uploadedFiles, setUploadedFiles] = useState<UploadedFile[]>([])
  const [uploading, setUploading] = useState(false)

  // ── Sidebar state ──
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

  // Scroll to bottom when a new message is added (track last message id).
  const lastMsgId = messages.length > 0 ? messages[messages.length - 1].id : null
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [lastMsgId, loading])

  // Track scroll position for scroll-to-bottom button.
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

  // Load UI config, models, and tools on mount.
  useEffect(() => {
    let cancelled = false
    apiGetUIConfig().then((cfg) => {
      if (cancelled) return
      setUIConfig(cfg)
      setSelectedSystemPrompt((prev) => prev || getFirstSystemPromptName(cfg))
    }).catch(() => {})
    apiGetModels().then((data) => {
      if (cancelled) return
      setModels(data.models)
    }).catch(() => {})
    apiListTools().then((list) => {
      if (cancelled) return
      setTools(list)
    }).catch(() => {})
    return () => { cancelled = true }
  }, [])

  useEffect(() => {
    document.title = appName

    if (!isImageIcon(appIcon)) {
      return
    }

    const link = document.querySelector("link[rel='icon']") || document.createElement('link')
    link.setAttribute('rel', 'icon')
    link.setAttribute('href', appIcon || '')
    if (!link.parentNode) {
      document.head.appendChild(link)
    }
  }, [appIcon, appName])

  const refreshConversations = useCallback(async () => {
    setConvsLoading(true)
    try {
      const list = await apiListConversations()
      setConversations(list ?? [])
    } catch {
      // silently ignore — sidebar just stays empty
    } finally {
      setConvsLoading(false)
    }
  }, [])

  // Fetch conversation list on mount.
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
      if (!silent) {
        antMessage.error('Failed to load conversation')
      }
      return
    }
    sessionStorage.setItem('chatSessionId', id)
    setSessionId(id)
    setInput('')
    setUploadedFiles([])
    // Convert storage messages to UI messages (user/assistant only; skip tool messages).
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
      }))
    setMessages(uiMsgs)
    // Restore the user's explicit model choice for this conversation.
    // detail.model is empty when the user left it on auto.
    const next = detail.model || 'auto'
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
    // If we deleted the active session, start fresh.
    if (id === sessionId) {
      handleNewChat()
    }
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
      // Re-sort: pinned first (preserving relative order within each group).
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

  // selectedModelRef lets send() read the latest selected model without
  // needing it in the dependency array.
  useEffect(() => { messagesRef.current = messages }, [messages])

  const selectedModelRef = useRef(selectedModel)
  useEffect(() => { selectedModelRef.current = selectedModel }, [selectedModel])

  const selectedSystemPromptRef = useRef(selectedSystemPrompt)
  useEffect(() => { selectedSystemPromptRef.current = selectedSystemPrompt }, [selectedSystemPrompt])

  const uploadedFilesRef = useRef(uploadedFiles)
  useEffect(() => { uploadedFilesRef.current = uploadedFiles }, [uploadedFiles])

  // sessionIdRef ensures send() always uses the current session ID even if
  // the state update hasn't propagated through useCallback deps yet.
  const sessionIdRef = useRef(sessionId)
  useEffect(() => { sessionIdRef.current = sessionId }, [sessionId])

  const send = useCallback(async (overrideText?: string) => {
    // Guard: disallow concurrent sends.
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
      const response = await apiChat(currentSessionId, text, fileUrls, modelToSend, systemPromptToSend)
      // Attach persisted storage IDs so individual messages can be deleted later.
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
      }
      setMessages((prev) => [...prev, assistantMsg])
      refreshConversations()
    } catch (err) {
      // Prefer the model reported by the server (ChatError.model); fall back to
      // what the user selected. Always show something — never hide it.
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
      // Defer focus until after React re-enables the textarea.
      setTimeout(() => {
        const el = inputRef.current?.resizableTextArea?.textArea
        el?.focus()
      }, 0)
    }
  }, [input, refreshConversations]) // sessionId, uploadedFiles, selectedModel accessed via refs

  const handleDeleteMessage = useCallback((id: string) => {
    setMessages((prev) => {
      const msg = prev.find((m) => m.id === id)
      if (msg?.msgId) {
        // Fire-and-forget: remove from storage; ignore errors silently.
        apiDeleteMessage(sessionIdRef.current, msg.msgId).catch(() => {})
      }
      return prev.filter((m) => m.id !== id)
    })
  }, [])

  // handleEditMessage: called when the user submits an edited user message.
  // Drops all messages after the edited one from both UI and storage, updates
  // the edited message content, then re-sends it to the LLM.
  const handleEditMessage = useCallback(async (id: string, newContent: string) => {
    const prev = messagesRef.current
    const idx = prev.findIndex((m) => m.id === id)
    if (idx < 0) return

    const msg = prev[idx]
    const convId = sessionIdRef.current

    // Delete the edited message and everything after it from storage.
    if (msg.msgId) {
      apiDeleteMessagesFrom(convId, msg.msgId).catch(() => {})
    }

    // Synchronously truncate: keep only messages before the edited one.
    // The edited message will be re-added by send() as a fresh user message.
    const truncated = prev.slice(0, idx)
    setMessages(truncated)
    messagesRef.current = truncated

    // Now send the edited content as a new message.
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

  // Build model selector options once when models list changes.
  const modelOptions = useMemo(() => [
    { label: 'Auto', value: 'auto' },
    ...models.map((m) => ({ label: m.name || m.id, value: m.id })),
  ], [models])

  const systemPromptOptions = useMemo(() => [
    ...(getSortedSystemPrompts(uiConfig).map((prompt) => ({
      label: prompt.name,
      value: prompt.name,
    }))),
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
          {/* New Chat button */}
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

          {/* Conversation list */}
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
                {/* Pinned group */}
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
                {/* Recent / unpinned group */}
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
                    onClick={() => {
                      if (!loading) send(prompt)
                    }}
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

        {/* Scroll-to-bottom button — fixed so it floats above the input footer */}
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
        <div
          style={{
            maxWidth: 'min(92%, 1800px)',
            margin: '0 auto',
          }}
        >
          {/* ── Textarea with toolbar inset at bottom ── */}
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
                  paddingBottom: 48,  // leave room for the inset toolbar row
                }}
              />
                {/* Inset bottom-left toolbar: attach + prompt/model selectors */}
                <div
                style={{
                  position: 'absolute',
                  bottom: 6,
                  left: 8,
                  right: 54, // stop before the send button (34px + 8px gutter + 12px breathing room)
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
                    prefix={<RobotOutlined style={{ color: token.colorTextSecondary, fontSize: 13 }} />}
                    optionRender={(opt) => (
                      <div style={{ display: 'flex', flexDirection: 'column', padding: '2px 0' }}>
                        <span style={{ fontWeight: 500, fontSize: 13, lineHeight: 1.4 }}>{opt.label}</span>
                        {opt.value !== 'auto' && (
                          <span style={{ fontSize: 11, color: token.colorTextTertiary, lineHeight: 1.3 }}>{opt.value}</span>
                        )}
                      </div>
                    )}
                    style={{ flex: 1, minWidth: 0 }}
                  />
                )}
              </div>
              {/* Inset bottom-right: send button */}
              <div
                style={{
                  position: 'absolute',
                  bottom: 6,
                  right: 8,
                }}
              >
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

              // Validate file count.
              const currentCount = uploadedFilesRef.current.length
              const incoming = Array.from(files)
              if (currentCount + incoming.length > MAX_FILES_PER_MESSAGE) {
                antMessage.error(`You can attach at most ${MAX_FILES_PER_MESSAGE} files per message`)
                e.target.value = ''
                return
              }

              // Validate file sizes.
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
                if (succeeded.length > 0) {
                  setUploadedFiles((prev) => [...prev, ...succeeded])
                }
                if (failed.length > 0) {
                  antMessage.error(`Failed to upload: ${failed.join(', ')}`)
                }
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

      {/* ── Tools Drawer ── */}
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

// ── Root with ConfigProvider ───────────────────────────────────────────────

export default function App() {
  // Respect OS-level dark mode preference as the initial value.
  const [isDark, setIsDark] = useState(
    () => typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches
  )

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
