import { Collapse, Drawer, Table, Tag, Timeline, Typography, theme } from 'antd'
import { CheckCircleOutlined, ToolOutlined } from '@ant-design/icons'
import type { LLMRound, TraceMessage } from '../../types/chat'
import { ParamsTable } from '../ParamsTable'

const { Text } = Typography
const { useToken } = theme

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

export function TraceDrawer({ open, onClose, rounds }: {
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
                render: (_: string, tool) => (
                  <div>
                    <Text type="secondary" style={{ fontSize: 12 }}>{tool.description}</Text>
                    {tool.parameters && <ParamsTable parameters={tool.parameters} />}
                  </div>
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
          <Table
            size="small"
            pagination={false}
            rowKey={(_, i) => String(i)}
            dataSource={round.request.map((msg, i) => ({ ...msg, _idx: i }))}
            style={{
              border: `1px solid ${token.colorBorderSecondary}`,
              borderRadius: 6,
              overflow: 'hidden',
            }}
            columns={[
              {
                title: '#',
                key: 'idx',
                width: 32,
                render: (_: unknown, __: unknown, i: number) => (
                  <Text type="secondary" style={{ fontSize: 11 }}>{i + 1}</Text>
                ),
              },
              {
                title: 'Role',
                dataIndex: 'role',
                key: 'role',
                width: 90,
                render: (role: string) => (
                  <Tag
                    color={ROLE_COLORS[role] ?? '#595959'}
                    style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: '0.04em', margin: 0 }}
                  >
                    {role}
                  </Tag>
                ),
              },
              {
                title: 'Content',
                key: 'content',
                render: (_: unknown, msg: TraceMessage & { _idx: number }) => {
                  if (msg.tool_calls && msg.tool_calls.length > 0) {
                    return (
                      <div>
                        {msg.tool_calls.map((tc, tci) => (
                          <div key={tci} style={{
                            background: token.colorFillSecondary,
                            borderRadius: 4,
                            padding: '3px 8px',
                            marginBottom: tci < msg.tool_calls!.length - 1 ? 4 : 0,
                          }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 2 }}>
                              <Text strong style={{ fontSize: 12, fontFamily: 'ui-monospace, monospace' }}>{tc.name}</Text>
                              <Text type="secondary" style={{ fontSize: 10, fontFamily: 'ui-monospace, monospace' }}>id:{tc.id}</Text>
                            </div>
                            <pre style={{
                              margin: 0,
                              fontSize: 11,
                              fontFamily: 'ui-monospace, monospace',
                              whiteSpace: 'pre-wrap',
                              wordBreak: 'break-word',
                              color: token.colorText,
                              maxHeight: 160,
                              overflowY: 'auto',
                            }}>
                              {(() => { try { return JSON.stringify(JSON.parse(tc.args), null, 2) } catch { return tc.args } })()}
                            </pre>
                          </div>
                        ))}
                      </div>
                    )
                  }
                  if (msg.role === 'tool') {
                    return (
                      <div>
                        {msg.tool_call_id && (
                          <Text type="secondary" style={{ fontSize: 10, fontFamily: 'ui-monospace, monospace', display: 'block', marginBottom: 2 }}>
                            id:{msg.tool_call_id}
                          </Text>
                        )}
                        {msg.name && (
                          <Text strong style={{ fontSize: 11, fontFamily: 'ui-monospace, monospace', display: 'block', marginBottom: 2 }}>
                            {msg.name}
                          </Text>
                        )}
                        <pre style={{
                          margin: 0,
                          fontSize: 11,
                          fontFamily: 'ui-monospace, monospace',
                          whiteSpace: 'pre-wrap',
                          wordBreak: 'break-word',
                          color: token.colorText,
                          maxHeight: 160,
                          overflowY: 'auto',
                        }}>{msg.content || ''}</pre>
                      </div>
                    )
                  }
                  return (
                    <pre style={{
                      margin: 0,
                      fontSize: 12,
                      fontFamily: 'ui-monospace, monospace',
                      whiteSpace: 'pre-wrap',
                      wordBreak: 'break-word',
                      color: token.colorText,
                      maxHeight: 200,
                      overflowY: 'auto',
                    }}>{msg.content || ''}</pre>
                  )
                },
              },
            ]}
          />
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
