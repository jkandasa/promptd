import { Button, Collapse, Drawer, Empty, Input, Tag, Tooltip, Typography, theme } from 'antd'
import {
  CheckCircleOutlined,
  CheckOutlined,
  CopyOutlined,
  DownOutlined,
  ThunderboltOutlined,
  ToolOutlined,
  UpOutlined,
} from '@ant-design/icons'
import { memo, useState } from 'react'
import type { LLMRound, ToolResult, TraceMessage } from '../../types/chat'
import { ParamsTable } from '../ParamsTable'

const { Text } = Typography
const { useToken } = theme

// ── Role colors ───────────────────────────────────────────────────────────
const ROLE_COLOR: Record<string, string> = {
  system:    '#8c8c8c',
  user:      '#1677ff',
  assistant: '#52c41a',
  tool:      '#fa8c16',
}

function RoleBadge({ role }: { role: string }) {
  const color = ROLE_COLOR[role] ?? '#595959'
  return (
    <Tag
      color={color}
      style={{ fontSize: 10, margin: 0, padding: '0 5px', lineHeight: '18px', textTransform: 'uppercase', letterSpacing: '0.05em' }}
    >
      {role}
    </Tag>
  )
}

// ── Helpers ───────────────────────────────────────────────────────────────
const fmtMs = (ms: number) => ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`

function formatJSON(raw: string): string {
  try { return JSON.stringify(JSON.parse(raw), null, 2) } catch { return raw }
}

// ── ContentBlock: copyable, expandable pre ────────────────────────────────
const PREVIEW_LINES = 8

const ContentBlock = memo(function ContentBlock({
  content,
  label,
  bg,
}: {
  content: string
  label?: string
  bg?: string
}) {
  const { token } = useToken()
  const lines = content.split('\n')
  const canCollapse = lines.length > PREVIEW_LINES + 2
  const [expanded, setExpanded] = useState(false)
  const [copied, setCopied] = useState(false)

  const displayed = canCollapse && !expanded
    ? lines.slice(0, PREVIEW_LINES).join('\n')
    : content

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(content)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch { /* silent */ }
  }

  return (
    <div style={{ marginTop: label ? 4 : 2 }}>
      {label && (
        <Text style={{
          fontSize: 10,
          color: token.colorTextTertiary,
          textTransform: 'uppercase',
          letterSpacing: '0.06em',
          display: 'block',
          marginBottom: 2,
        }}>
          {label}
        </Text>
      )}
      <div style={{
        position: 'relative',
        borderRadius: 6,
        border: `1px solid ${token.colorBorderSecondary}`,
        background: bg ?? token.colorFillAlter,
        overflow: 'hidden',
      }}>
        <pre style={{
          margin: 0,
          padding: '7px 34px 7px 10px',
          whiteSpace: 'pre-wrap',
          wordBreak: 'break-word',
          fontSize: 12,
          fontFamily: token.fontFamilyCode,
          color: token.colorText,
          lineHeight: 1.55,
        }}>
          {displayed}
          {canCollapse && !expanded && <Text type="secondary"> …</Text>}
        </pre>
        <Tooltip title={copied ? 'Copied!' : 'Copy'}>
          <Button
            type="text"
            size="small"
            icon={copied
              ? <CheckOutlined style={{ color: token.colorSuccess, fontSize: 11 }} />
              : <CopyOutlined style={{ fontSize: 11 }} />}
            onClick={handleCopy}
            style={{
              position: 'absolute',
              top: 4,
              right: 4,
              width: 22,
              height: 22,
              padding: 0,
              color: token.colorTextSecondary,
              opacity: 0.7,
            }}
          />
        </Tooltip>
        {canCollapse && (
          <button
            onClick={() => setExpanded(e => !e)}
            style={{
              width: '100%',
              padding: '3px 0',
              fontSize: 11,
              color: token.colorLink,
              background: token.colorFillSecondary,
              border: 'none',
              borderTop: `1px solid ${token.colorBorderSecondary}`,
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 4,
            }}
          >
            {expanded
              ? <><UpOutlined style={{ fontSize: 9 }} /> Show less</>
              : <><DownOutlined style={{ fontSize: 9 }} /> {lines.length - PREVIEW_LINES} more lines</>}
          </button>
        )}
      </div>
    </div>
  )
})

// ── MessageCard ───────────────────────────────────────────────────────────
function MessageCard({ msg }: { msg: TraceMessage }) {
  const { token } = useToken()
  const roleColor = ROLE_COLOR[msg.role] ?? '#d9d9d9'

  return (
    <div style={{
      borderTop: `1px solid ${token.colorBorderSecondary}`,
      borderRight: `1px solid ${token.colorBorderSecondary}`,
      borderBottom: `1px solid ${token.colorBorderSecondary}`,
      borderLeft: `3px solid ${roleColor}`,
      borderRadius: '0 6px 6px 0',
      padding: '6px 10px',
      marginBottom: 6,
      background: token.colorFillAlter,
    }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4, flexWrap: 'wrap' }}>
        <RoleBadge role={msg.role} />
        {msg.name && (
          <Text style={{ fontSize: 11, fontFamily: token.fontFamilyCode, color: token.colorTextSecondary }}>
            {msg.name}
          </Text>
        )}
        {msg.tool_call_id && (
          <Text style={{ fontSize: 10, fontFamily: token.fontFamilyCode, color: token.colorTextTertiary, marginLeft: 'auto', flexShrink: 0 }}>
            id:{msg.tool_call_id}
          </Text>
        )}
      </div>

      {/* Main content */}
      {msg.content && <ContentBlock content={msg.content} />}

      {/* Reasoning */}
      {msg.reasoning_content && (
        <details style={{ marginTop: 6 }}>
          <summary style={{ cursor: 'pointer', userSelect: 'none', fontSize: 11, color: token.colorTextSecondary, listStyle: 'none', display: 'flex', alignItems: 'center', gap: 4 }}>
            <DownOutlined style={{ fontSize: 9 }} />
            reasoning · {msg.reasoning_content.length.toLocaleString()} chars
          </summary>
          <div style={{ marginTop: 4 }}>
            <ContentBlock content={msg.reasoning_content} bg={token.colorWarningBg} />
          </div>
        </details>
      )}

      {/* Refusal */}
      {msg.refusal && (
        <ContentBlock content={`[refusal] ${msg.refusal}`} bg={token.colorErrorBg} />
      )}

      {/* Tool calls */}
      {msg.tool_calls && msg.tool_calls.length > 0 && (
        <div style={{ marginTop: (msg.content || msg.reasoning_content || msg.refusal) ? 8 : 0 }}>
          {msg.tool_calls.map((tc, i) => (
            <div key={i} style={{
              border: `1px solid ${token.colorBorderSecondary}`,
              borderRadius: 6,
              overflow: 'hidden',
              marginBottom: i < msg.tool_calls!.length - 1 ? 6 : 0,
            }}>
              <div style={{
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                padding: '4px 8px',
                background: token.colorFillSecondary,
                borderBottom: `1px solid ${token.colorBorderSecondary}`,
              }}>
                <Tag color="orange" style={{ fontSize: 10, margin: 0, padding: '0 5px', lineHeight: '18px' }}>call</Tag>
                <Text strong style={{ fontSize: 12, fontFamily: token.fontFamilyCode, flex: 1 }}>{tc.name}</Text>
                <Text style={{ fontSize: 10, fontFamily: token.fontFamilyCode, color: token.colorTextTertiary, marginLeft: 'auto', flexShrink: 0 }}>
                  id:{tc.id}
                </Text>
              </div>
              <div style={{ padding: '6px 8px' }}>
                <ContentBlock content={formatJSON(tc.args)} />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ── ToolResultCard ────────────────────────────────────────────────────────
function ToolResultCard({ tr }: { tr: ToolResult }) {
  const { token } = useToken()
  const lowerResult = tr.result.toLowerCase()
  const isError = lowerResult.startsWith('error') || lowerResult.includes('"error"') || lowerResult.includes('error:')

  return (
    <div style={{
      border: `1px solid ${isError ? token.colorErrorBorder : token.colorBorderSecondary}`,
      borderRadius: 8,
      overflow: 'hidden',
      marginBottom: 8,
    }}>
      {/* Header */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        padding: '6px 10px',
        background: isError ? token.colorErrorBg : token.colorFillSecondary,
        borderBottom: `1px solid ${isError ? token.colorErrorBorder : token.colorBorderSecondary}`,
      }}>
        <ToolOutlined style={{ color: isError ? token.colorError : token.colorWarning, fontSize: 13, flexShrink: 0 }} />
        <Text strong style={{ fontSize: 13, fontFamily: token.fontFamilyCode, flex: 1 }}>{tr.name}</Text>
        <Tag
          color={isError ? 'error' : 'default'}
          style={{ fontSize: 10, margin: 0, flexShrink: 0 }}
        >
          {fmtMs(tr.duration_ms)}
        </Tag>
      </div>
      {/* Body */}
      <div style={{ padding: '8px 10px', display: 'flex', flexDirection: 'column', gap: 6 }}>
        <ContentBlock content={formatJSON(tr.args)} label="Input" />
        <ContentBlock
          content={tr.result}
          label="Output"
          bg={isError ? token.colorErrorBg : undefined}
        />
      </div>
    </div>
  )
}

// ── TokenBar ──────────────────────────────────────────────────────────────
function TokenBar({ usage }: { usage: NonNullable<LLMRound['usage']> }) {
  const { token } = useToken()
  const { prompt_tokens: p, completion_tokens: c, reasoning_tokens: r = 0, cached_tokens: cached = 0 } = usage
  const total = p + c
  if (total === 0) return null
  const pct = (n: number) => `${Math.max(0, (n / total) * 100).toFixed(1)}%`

  return (
    <div style={{
      marginTop: 8,
      padding: '8px 10px',
      background: token.colorFillAlter,
      border: `1px solid ${token.colorBorderSecondary}`,
      borderRadius: 6,
    }}>
      {/* Legend */}
      <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap', marginBottom: 6 }}>
        <Text style={{ fontSize: 11, color: token.colorTextSecondary }}>
          <span style={{ color: token.colorPrimary, marginRight: 3 }}>■</span>
          {p.toLocaleString()} prompt
        </Text>
        <Text style={{ fontSize: 11, color: token.colorTextSecondary }}>
          <span style={{ color: token.colorSuccess, marginRight: 3 }}>■</span>
          {c.toLocaleString()} completion
        </Text>
        {r > 0 && (
          <Text style={{ fontSize: 11, color: token.colorTextSecondary }}>
            <span style={{ color: token.colorWarning, marginRight: 3 }}>■</span>
            {r.toLocaleString()} reasoning
          </Text>
        )}
        {cached > 0 && (
          <Text style={{ fontSize: 11, color: token.colorTextSecondary }}>
            <span style={{ color: token.colorTextQuaternary, marginRight: 3 }}>■</span>
            {cached.toLocaleString()} cached
          </Text>
        )}
      </div>
      {/* Stacked bar */}
      <div style={{
        height: 6,
        borderRadius: 3,
        background: token.colorFillSecondary,
        display: 'flex',
        overflow: 'hidden',
        gap: 1,
      }}>
        {cached > 0 && (
          <div style={{ width: pct(cached), background: token.colorTextQuaternary, borderRadius: '3px 0 0 3px' }} />
        )}
        <div style={{
          width: pct(p - cached),
          background: token.colorPrimary,
          borderRadius: cached === 0 ? '3px 0 0 3px' : undefined,
        }} />
        <div style={{
          width: pct(c - r),
          background: token.colorSuccess,
          borderRadius: r === 0 ? '0 3px 3px 0' : undefined,
        }} />
        {r > 0 && (
          <div style={{ width: pct(r), background: token.colorWarning, borderRadius: '0 3px 3px 0' }} />
        )}
      </div>
    </div>
  )
}

// ── AvailableToolsList ────────────────────────────────────────────────────
type ToolDef = { name: string; description: string; parameters?: any }

function AvailableToolsList({ tools }: { tools: ToolDef[] }) {
  const { token } = useToken()
  const [search, setSearch] = useState('')
  const q = search.trim().toLowerCase()
  const filtered = q
    ? tools.filter(t => t.name.toLowerCase().includes(q) || t.description.toLowerCase().includes(q))
    : tools

  const paramCount = (t: ToolDef) => {
    const props = t.parameters?.properties
    return props && typeof props === 'object' ? Object.keys(props).length : 0
  }

  return (
    <div>
      {tools.length > 5 && (
        <Input.Search
          placeholder="Filter tools…"
          value={search}
          onChange={e => setSearch(e.target.value)}
          allowClear
          size="small"
          style={{ marginBottom: 8 }}
        />
      )}
      {filtered.length === 0 ? (
        <Empty description="No matching tools" image={Empty.PRESENTED_IMAGE_SIMPLE} style={{ padding: '12px 0' }} />
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          {filtered.map((tool, i) => {
            const pc = paramCount(tool)
            return (
              <div
                key={tool.name ?? i}
                style={{
                  border: `1px solid ${token.colorBorderSecondary}`,
                  borderRadius: 8,
                  padding: '10px 14px',
                  background: token.colorBgContainer,
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: tool.description ? 4 : 0 }}>
                  <Tag color="blue" style={{ fontFamily: token.fontFamilyCode, fontSize: 12, margin: 0 }}>
                    {tool.name}
                  </Tag>
                  {pc > 0 && (
                    <Text type="secondary" style={{ fontSize: 11 }}>
                      {pc} param{pc === 1 ? '' : 's'}
                    </Text>
                  )}
                </div>
                {tool.description && (
                  <Text type="secondary" style={{ fontSize: 12, display: 'block', lineHeight: 1.5 }}>
                    {tool.description}
                  </Text>
                )}
                {pc > 0 && (
                  <Collapse
                    size="small"
                    ghost
                    style={{ marginTop: 6 }}
                    items={[{
                      key: 'params',
                      label: <Text style={{ fontSize: 12 }}>Parameters</Text>,
                      children: <ParamsTable parameters={tool.parameters} />,
                    }]}
                  />
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ── LLMTraceView — reusable panel (no Drawer shell) ──────────────────────
export function LLMTraceView({ rounds }: { rounds: LLMRound[] }) {
  const { token } = useToken()

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      {rounds.map((round, idx) => {
        const hasTools    = (round.tool_results?.length ?? 0) > 0
        const toolCount   = round.tool_results?.length ?? 0
        const roundToolMs = round.tool_results?.reduce((s, t) => s + t.duration_ms, 0) ?? 0
        const isFinal     = !hasTools
        const isLast      = idx === rounds.length - 1

        const borderColor = isFinal ? token.colorSuccessBorder : token.colorWarningBorder
        const headerBg    = isFinal ? token.colorSuccessBg     : token.colorWarningBg
        const iconColor   = isFinal ? token.colorSuccess       : token.colorWarning

        const innerItems = [
          ...(round.available_tools && round.available_tools.length > 0 ? [{
            key: 'available_tools',
            label: (
              <Text style={{ fontSize: 12 }}>
                Available Tools
                <Text type="secondary" style={{ fontSize: 11, marginLeft: 6 }}>({round.available_tools.length})</Text>
              </Text>
            ),
            children: <AvailableToolsList tools={round.available_tools} />,
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
              <div>
                {round.request.map((msg, i) => (
                  <MessageCard key={i} msg={msg} />
                ))}
              </div>
            ),
          },
          {
            key: 'response',
            label: (
              <Text style={{ fontSize: 12 }}>
                {isFinal ? 'LLM Response' : 'LLM Decision'}
                <Text type="secondary" style={{ fontSize: 11, marginLeft: 6 }}>{fmtMs(round.llm_duration_ms)}</Text>
              </Text>
            ),
            children: (
              <div>
                <MessageCard msg={round.response} />
                {round.usage && <TokenBar usage={round.usage} />}
              </div>
            ),
          },
          ...(hasTools ? [{
            key: 'tools',
            label: (
              <Text style={{ fontSize: 12 }}>
                Tool Execution
                <Text type="secondary" style={{ fontSize: 11, marginLeft: 6 }}>
                  {toolCount} call{toolCount === 1 ? '' : 's'} · {fmtMs(roundToolMs)}
                </Text>
              </Text>
            ),
            children: (
              <div>
                {round.tool_results!.map((tr, ti) => (
                  <ToolResultCard key={ti} tr={tr} />
                ))}
              </div>
            ),
          }] : []),
        ]

        return (
          <div
            key={idx}
            style={{ border: `1px solid ${borderColor}`, borderRadius: 10, overflow: 'hidden' }}
          >
            <div style={{
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              padding: '9px 14px',
              background: headerBg,
              flexWrap: 'wrap',
            }}>
              {isFinal
                ? <CheckCircleOutlined style={{ color: iconColor, fontSize: 15 }} />
                : <ToolOutlined style={{ color: iconColor, fontSize: 14 }} />
              }
              <Text strong style={{ fontSize: 13 }}>Round {idx + 1}</Text>
              <Text type="secondary" style={{ fontSize: 12 }}>
                — {isFinal ? 'final answer' : `${toolCount} tool call${toolCount === 1 ? '' : 's'}`}
              </Text>
              <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                <Tag color="blue" style={{ fontSize: 10, margin: 0 }}>LLM {fmtMs(round.llm_duration_ms)}</Tag>
                {hasTools && (
                  <Tag color="orange" style={{ fontSize: 10, margin: 0 }}>tools {fmtMs(roundToolMs)}</Tag>
                )}
                {round.usage && (
                  <Text type="secondary" style={{ fontSize: 11 }}>
                    {round.usage.prompt_tokens.toLocaleString()}↑ {round.usage.completion_tokens.toLocaleString()}↓ tok
                  </Text>
                )}
              </div>
            </div>
            <Collapse
              size="small"
              defaultActiveKey={isLast ? ['response', ...(hasTools ? ['tools'] : [])] : []}
              style={{ background: 'transparent', borderRadius: 0, border: 'none' }}
              items={innerItems}
            />
          </div>
        )
      })}
    </div>
  )
}

// ── TraceDrawer ───────────────────────────────────────────────────────────
export function TraceDrawer({ open, onClose, rounds }: {
  open: boolean
  onClose: () => void
  rounds?: LLMRound[]
}) {
  const { token } = useToken()
  if (!rounds?.length) return null

  const totalLLMMs     = rounds.reduce((s, r) => s + r.llm_duration_ms, 0)
  const totalToolMs    = rounds.reduce((s, r) => s + (r.tool_results?.reduce((a, t) => a + t.duration_ms, 0) ?? 0), 0)
  const totalToolCalls = rounds.reduce((s, r) => s + (r.tool_results?.length ?? 0), 0)
  const totalPrompt    = rounds.reduce((s, r) => s + (r.usage?.prompt_tokens ?? 0), 0)
  const totalCompl     = rounds.reduce((s, r) => s + (r.usage?.completion_tokens ?? 0), 0)
  const totalReason    = rounds.reduce((s, r) => s + (r.usage?.reasoning_tokens ?? 0), 0)
  const totalCached    = rounds.reduce((s, r) => s + (r.usage?.cached_tokens ?? 0), 0)

  return (
    <Drawer
      title={
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Text strong style={{ fontSize: 15 }}>LLM Trace</Text>
            <Tag color="blue" style={{ fontSize: 11, margin: 0 }}>
              {rounds.length} round{rounds.length === 1 ? '' : 's'}
            </Tag>
          </div>
          <div style={{ display: 'flex', gap: 14, marginTop: 6, flexWrap: 'wrap' }}>
            <Text style={{ fontSize: 11, color: token.colorTextSecondary }}>
              <ThunderboltOutlined style={{ color: token.colorPrimary, marginRight: 3 }} />
              LLM {fmtMs(totalLLMMs)}
            </Text>
            {totalToolMs > 0 && (
              <Text style={{ fontSize: 11, color: token.colorTextSecondary }}>
                <ToolOutlined style={{ color: token.colorWarning, marginRight: 3 }} />
                Tools {fmtMs(totalToolMs)} · {totalToolCalls} call{totalToolCalls === 1 ? '' : 's'}
              </Text>
            )}
            {(totalPrompt + totalCompl) > 0 && (
              <Text style={{ fontSize: 11, color: token.colorTextSecondary }}>
                {totalPrompt.toLocaleString()}↑ {totalCompl.toLocaleString()}↓ tok
                {totalReason > 0 && ` · ${totalReason.toLocaleString()} reasoning`}
                {totalCached > 0 && ` · ${totalCached.toLocaleString()} cached`}
              </Text>
            )}
          </div>
        </div>
      }
      placement="right"
      width="min(960px, 90vw)"
      open={open}
      onClose={onClose}
      styles={{ body: { padding: '16px 20px' }, header: { paddingBottom: 12 } }}
    >
      <LLMTraceView rounds={rounds} />
    </Drawer>
  )
}
