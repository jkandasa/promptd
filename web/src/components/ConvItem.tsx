import { Button, Input, Popconfirm, Tooltip, Typography, theme } from 'antd'
import {
  DeleteOutlined,
  EditOutlined,
  MessageOutlined,
  PushpinFilled,
  PushpinOutlined,
} from '@ant-design/icons'
import type { ConversationMeta } from '../types/chat'
import { relativeTime } from '../utils/helpers'

const { Text } = Typography
const { useToken } = theme

export interface ConvItemProps {
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

export function ConvItem({
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
        <div style={{ flex: 1, minWidth: 0, overflow: 'hidden' }}>
          <Text
            ellipsis
            style={{
              display: 'block',
              fontSize: 13,
              fontWeight: isActive ? 600 : 400,
              color: isActive ? activeText : token.colorText,
              lineHeight: 1.3,
            }}
          >
            {conv.title || 'Untitled'}
          </Text>
          <Text
            style={{
              fontSize: 10,
              color: isActive ? 'rgba(255,255,255,0.65)' : token.colorTextTertiary,
              display: 'block',
              lineHeight: 1.3,
              marginTop: 1,
            }}
          >
            {relativeTime(conv.updated_at)}
          </Text>
        </div>
      )}
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
