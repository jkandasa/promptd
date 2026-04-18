import { App as AntApp, Avatar, Button, Input, Modal, Popconfirm, Tag, Tooltip, Typography, theme } from 'antd'
import {
  CheckOutlined,
  CopyOutlined,
  DeleteOutlined,
  EditOutlined,
  FileOutlined,
  RobotOutlined,
  UserOutlined,
} from '@ant-design/icons'
import { memo, useMemo, useState } from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import type { Message } from '../types/chat'
import { formatMessageTime, safeUrl } from '../utils/helpers'
import { TraceDrawer } from './trace/TraceDrawer'
import { UsedParamsChip } from './UsedParamsChip'
import { Linkified } from './Linkified'
import { buildMarkdownComponents } from './markdown/buildComponents'

const { Text, Link } = Typography
const { TextArea } = Input
const { useToken } = theme

export const Bubble = memo(function Bubble({
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
        background: `linear-gradient(135deg, ${token.colorPrimaryHover} 0%, ${token.colorPrimary} 100%)`,
        color: '#fff',
        borderRadius: '18px 18px 4px 18px',
        padding: '10px 18px 10px 16px',
        whiteSpace: 'pre-wrap',
        wordBreak: 'break-word',
        fontSize: 14,
        lineHeight: 1.5,
        boxShadow: `0 2px 12px ${token.colorPrimary}50`,
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

      <div style={{ display: 'flex', flexDirection: 'column', alignItems: isUser ? 'flex-end' : 'flex-start', gap: 3, flex: isUser ? undefined : 1, minWidth: 0, maxWidth: isUser ? '80%' : undefined }}>
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
              ? <Tag color="error" style={{ fontSize: 10, margin: 0 }}>{msg.provider ? `${msg.provider} · ${msg.model}` : msg.model}</Tag>
              : <Text type="secondary" style={{ fontSize: 10 }}>{msg.provider ? `${msg.provider} · ${msg.model}` : msg.model}</Text>
          )}
          {msg.timeTaken !== undefined && (
            <Text type="secondary" style={{ fontSize: 10 }}>
              {msg.timeTaken < 1000 ? `${msg.timeTaken}ms` : `${(msg.timeTaken / 1000).toFixed(1)}s`}
            </Text>
          )}
          {msg.llmCalls !== undefined && (
            msg.trace?.length
              ? <Link style={{ fontSize: 10 }} onClick={() => setTraceOpen(true)}>
                  {msg.llmCalls} LLM call{msg.llmCalls === 1 ? '' : 's'}
                </Link>
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
          {msg.usedParams && <UsedParamsChip params={msg.usedParams} />}
        </div>
        <TraceDrawer open={traceOpen} onClose={() => setTraceOpen(false)} rounds={msg.trace} />
      </div>
    </div>
  )
})
