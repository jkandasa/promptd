import { Popover, Tag, Typography, theme } from 'antd'
import type { UsedParams } from '../types/chat'

const { Text } = Typography
const { useToken } = theme

export function UsedParamsChip({ params }: { params: UsedParams }) {
  const { token } = useToken()

  const entries: { label: string; value: string }[] = []
  if (params.temperature != null) entries.push({ label: 'temp', value: params.temperature.toFixed(2) })
  if (params.top_p       != null) entries.push({ label: 'top_p', value: params.top_p.toFixed(2) })
  if (params.max_tokens)          entries.push({ label: 'max_tok', value: String(params.max_tokens) })
  if (params.top_k)               entries.push({ label: 'top_k', value: String(params.top_k) })

  if (entries.length === 0) return null

  const content = (
    <div style={{ minWidth: 180 }}>
      <Text type="secondary" style={{ fontSize: 11, display: 'block', marginBottom: 8 }}>
        Effective parameters sent to the LLM for this reply.
      </Text>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        {entries.map(({ label, value }) => (
          <div key={label} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12 }}>
            <Text style={{ fontSize: 12, fontFamily: token.fontFamilyCode, color: token.colorTextSecondary }}>{label}</Text>
            <Text strong style={{ fontSize: 12, fontFamily: token.fontFamilyCode }}>{value}</Text>
          </div>
        ))}
      </div>
    </div>
  )

  const summary = entries.map(({ label, value }) => `${label}=${value}`).join(' ')

  return (
    <Popover content={content} title={<span style={{ fontSize: 12 }}>Used Parameters</span>} trigger="click" placement="top" arrow={false}>
      <Tag
        style={{
          fontSize: 10,
          margin: 0,
          cursor: 'pointer',
          fontFamily: token.fontFamilyCode,
          color: token.colorTextSecondary,
          background: token.colorFillAlter,
          border: `1px solid ${token.colorBorderSecondary}`,
          padding: '0 5px',
          lineHeight: '18px',
        }}
      >
        {summary}
      </Tag>
    </Popover>
  )
}
