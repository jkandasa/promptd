import {
  Badge,
  Button,
  Collapse,
  Descriptions,
  Drawer,
  Empty,
  Popconfirm,
  Space,
  Spin,
  Switch,
  Tag,
  Tooltip,
  Typography,
  message,
  theme,
} from 'antd'
import {
  ClockCircleOutlined,
  DeleteOutlined,
  EditOutlined,
  PlusOutlined,
  ReloadOutlined,
  ThunderboltOutlined,
} from '@ant-design/icons'
import { useCallback, useEffect, useState } from 'react'
import type { Execution, Schedule } from '../../types/scheduler'
import type { ModelInfo } from '../../api/client'
import type { LLMRound, ToolInfo, UIConfig } from '../../types/chat'
import {
  apiCreateSchedule,
  apiDeleteExecution,
  apiDeleteSchedule,
  apiListExecutions,
  apiListSchedules,
  apiTriggerSchedule,
  apiUpdateSchedule,
} from '../../api/scheduler'
import { ScheduleForm } from './ScheduleForm'
import './SchedulerDrawer.scss'

const { Text, Title } = Typography
const { useToken } = theme

// ── Helpers ─────────────────────────────────────────────────────────────────

function fmtDate(iso?: string) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString()
}

function fmtDuration(ms?: number) {
  if (!ms) return ''
  if (ms < 1000) return `${ms}ms`
  return `${(ms / 1000).toFixed(1)}s`
}

function StatusBadge({ status }: { status: Execution['status'] }) {
  const map = {
    running: 'processing',
    success: 'success',
    error:   'error',
  } as const
  return <Badge status={map[status]} text={status} />
}

// ── Trace inline view ────────────────────────────────────────────────────────

function TraceView({ rounds }: { rounds: LLMRound[] }) {
  const { token } = useToken()
  if (!rounds.length) return null
  return (
    <Collapse
      size="small"
      ghost
      items={[{
        key: 'trace',
        label: <Text style={{ fontSize: 12 }}>LLM Trace ({rounds.length} round{rounds.length !== 1 ? 's' : ''})</Text>,
        children: (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {rounds.map((r, i) => (
              <div
                key={i}
                style={{
                  border: `1px solid ${token.colorBorderSecondary}`,
                  borderRadius: 6,
                  padding: '8px 10px',
                  background: token.colorFillAlter,
                  fontSize: 12,
                }}
              >
                <Space wrap size={8}>
                  <Text type="secondary">Round {i + 1}</Text>
                  <Text type="secondary">{r.llm_duration_ms}ms</Text>
                  {r.usage && (
                    <Text type="secondary">
                      {r.usage.total_tokens} tokens
                      {r.usage.reasoning_tokens ? ` (${r.usage.reasoning_tokens} reasoning)` : ''}
                    </Text>
                  )}
                  {r.tool_results?.length ? (
                    <Tag color="orange" style={{ fontSize: 11 }}>{r.tool_results.length} tool call{r.tool_results.length !== 1 ? 's' : ''}</Tag>
                  ) : null}
                </Space>
                {r.response?.content && (
                  <div style={{ marginTop: 6, color: token.colorText, whiteSpace: 'pre-wrap', lineHeight: 1.5 }}>
                    {r.response.content.slice(0, 300)}{r.response.content.length > 300 ? '…' : ''}
                  </div>
                )}
              </div>
            ))}
          </div>
        ),
      }]}
    />
  )
}

// ── Execution detail ─────────────────────────────────────────────────────────

function ExecutionItem({
  exec,
  onDelete,
}: {
  exec: Execution
  onDelete: (id: string) => void
}) {
  const { token } = useToken()
  return (
    <div
      className="exec-item"
      style={{
        border: `1px solid ${token.colorBorderSecondary}`,
        background: token.colorBgContainer,
      }}
    >
      <div className="exec-item-header">
        <Space direction="vertical" size={2} style={{ flex: 1 }}>
          <Space wrap size={8}>
            <StatusBadge status={exec.status} />
            {exec.modelUsed && <Tag style={{ fontSize: 11 }}>{exec.modelUsed}</Tag>}
            {exec.durationMs != null && (
              <Text type="secondary" style={{ fontSize: 11 }}>{fmtDuration(exec.durationMs)}</Text>
            )}
            {(exec.llmCalls ?? 0) > 0 && (
              <Text type="secondary" style={{ fontSize: 11 }}>{exec.llmCalls} LLM call{exec.llmCalls !== 1 ? 's' : ''}</Text>
            )}
            {(exec.toolCalls ?? 0) > 0 && (
              <Text type="secondary" style={{ fontSize: 11 }}>{exec.toolCalls} tool call{exec.toolCalls !== 1 ? 's' : ''}</Text>
            )}
          </Space>
          <Text type="secondary" style={{ fontSize: 11 }}>{fmtDate(exec.triggeredAt)}</Text>
        </Space>
        <Popconfirm
          title="Delete this execution?"
          onConfirm={() => onDelete(exec.id)}
          okText="Delete"
          okType="danger"
        >
          <Button type="text" size="small" icon={<DeleteOutlined />} danger />
        </Popconfirm>
      </div>

      {exec.error && (
        <div className="exec-error" style={{ background: token.colorErrorBg, color: token.colorError }}>
          {exec.error}
        </div>
      )}

      {exec.response && (
        <div style={{ marginTop: 8 }}>
          <Collapse
            size="small"
            ghost
            defaultActiveKey={[]}
            items={[{
              key: 'resp',
              label: <Text style={{ fontSize: 12 }}>Response</Text>,
              children: (
                <div style={{ whiteSpace: 'pre-wrap', fontSize: 12, lineHeight: 1.6 }}>
                  {exec.response}
                </div>
              ),
            }]}
          />
        </div>
      )}

      {exec.trace?.length ? <TraceView rounds={exec.trace} /> : null}
    </div>
  )
}

// ── Schedule card ────────────────────────────────────────────────────────────

function ScheduleCard({
  schedule,
  selected,
  onSelect,
  onToggle,
  onEdit,
  onDelete,
  onTrigger,
}: {
  schedule: Schedule
  selected: boolean
  onSelect: () => void
  onToggle: (enabled: boolean) => void
  onEdit: () => void
  onDelete: () => void
  onTrigger: () => void
}) {
  const { token } = useToken()
  return (
    <div
      onClick={onSelect}
      className="schedule-card"
      style={{
        border: `1px solid ${selected ? token.colorPrimary : token.colorBorderSecondary}`,
        background: selected ? token.colorPrimaryBg : token.colorBgContainer,
      }}
    >
      <div className="schedule-card-header">
        <Space size={6}>
          <Switch
            size="small"
            checked={schedule.enabled}
            onChange={(v, e) => { e.stopPropagation(); onToggle(v) }}
          />
          <Text strong style={{ fontSize: 13 }}>{schedule.name}</Text>
        </Space>
        <Space size={2} onClick={(e) => e.stopPropagation()}>
          <Tooltip title="Run now">
            <Button type="text" size="small" icon={<ThunderboltOutlined />} onClick={onTrigger} />
          </Tooltip>
          <Tooltip title="Edit">
            <Button type="text" size="small" icon={<EditOutlined />} onClick={onEdit} />
          </Tooltip>
          <Popconfirm title="Delete this schedule?" onConfirm={onDelete} okType="danger" okText="Delete">
            <Button type="text" size="small" icon={<DeleteOutlined />} danger />
          </Popconfirm>
        </Space>
      </div>

      <Space direction="vertical" size={1} className="schedule-card-meta">
        <Space size={6} wrap>
          <Tag color={schedule.type === 'cron' ? 'blue' : 'purple'} style={{ fontSize: 11 }}>
            {schedule.type === 'cron' ? schedule.cronExpr : 'once'}
          </Tag>
          {schedule.modelId && <Tag style={{ fontSize: 11 }}>{schedule.modelId}</Tag>}
        </Space>
        {schedule.nextRunAt && (
          <Text type="secondary" style={{ fontSize: 11 }}>
            <ClockCircleOutlined style={{ marginRight: 4 }} />
            Next: {fmtDate(schedule.nextRunAt)}
          </Text>
        )}
        {schedule.lastRunAt && (
          <Text type="secondary" style={{ fontSize: 11 }}>
            Last: {fmtDate(schedule.lastRunAt)}
          </Text>
        )}
      </Space>
    </div>
  )
}

// ── Main Drawer ──────────────────────────────────────────────────────────────

interface Props {
  open: boolean
  onClose: () => void
  models: ModelInfo[]
  tools: ToolInfo[]
  uiConfig: UIConfig
}

export function SchedulerDrawer({ open, onClose, models, tools, uiConfig }: Props) {
  const { token } = useToken()
  const [schedules, setSchedules] = useState<Schedule[]>([])
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [executions, setExecutions] = useState<Execution[]>([])
  const [loadingSchedules, setLoadingSchedules] = useState(false)
  const [loadingExecs, setLoadingExecs] = useState(false)
  const [formOpen, setFormOpen] = useState(false)
  const [editingSchedule, setEditingSchedule] = useState<Schedule | null>(null)
  const [msgApi, contextHolder] = message.useMessage()

  const loadSchedules = useCallback(async () => {
    setLoadingSchedules(true)
    try {
      const data = await apiListSchedules()
      setSchedules(data)
    } finally {
      setLoadingSchedules(false)
    }
  }, [])

  const loadExecutions = useCallback(async (id: string) => {
    setLoadingExecs(true)
    try {
      const data = await apiListExecutions(id)
      setExecutions(data)
    } finally {
      setLoadingExecs(false)
    }
  }, [])

  useEffect(() => {
    if (open) loadSchedules()
  }, [open, loadSchedules])

  useEffect(() => {
    if (selectedId) loadExecutions(selectedId)
    else setExecutions([])
  }, [selectedId, loadExecutions])

  const selectedSchedule = schedules.find((s) => s.id === selectedId) ?? null

  const handleToggle = async (sc: Schedule, enabled: boolean) => {
    try {
      const updated = await apiUpdateSchedule(sc.id, { ...sc, enabled })
      setSchedules((prev) => prev.map((s) => (s.id === sc.id ? updated : s)))
    } catch (e: any) {
      msgApi.error(e.message || 'Failed to update schedule')
    }
  }

  const handleTrigger = async (id: string) => {
    try {
      await apiTriggerSchedule(id)
      msgApi.success('Triggered — check execution history in a moment')
      setTimeout(() => { if (selectedId === id) loadExecutions(id) }, 2000)
    } catch (e: any) {
      msgApi.error(e.message || 'Failed to trigger')
    }
  }

  const handleDeleteSchedule = async (id: string) => {
    try {
      await apiDeleteSchedule(id)
      setSchedules((prev) => prev.filter((s) => s.id !== id))
      if (selectedId === id) { setSelectedId(null); setExecutions([]) }
      msgApi.success('Schedule deleted')
    } catch {
      msgApi.error('Failed to delete schedule')
    }
  }

  const handleDeleteExecution = async (execId: string) => {
    if (!selectedId) return
    try {
      await apiDeleteExecution(selectedId, execId)
      setExecutions((prev) => prev.filter((e) => e.id !== execId))
    } catch {
      msgApi.error('Failed to delete execution')
    }
  }

  const handleFormSubmit = async (values: Partial<Schedule>) => {
    if (editingSchedule) {
      const updated = await apiUpdateSchedule(editingSchedule.id, { ...editingSchedule, ...values })
      setSchedules((prev) => prev.map((s) => (s.id === updated.id ? updated : s)))
      msgApi.success('Schedule updated')
    } else {
      const created = await apiCreateSchedule(values as any)
      setSchedules((prev) => [created, ...prev])
      msgApi.success('Schedule created')
    }
    setFormOpen(false)
    setEditingSchedule(null)
  }

  const openEdit = (sc: Schedule) => {
    setEditingSchedule(sc)
    setFormOpen(true)
  }

  const openCreate = () => {
    setEditingSchedule(null)
    setFormOpen(true)
  }

  return (
    <>
      {contextHolder}
      <Drawer
        title="Schedules"
        placement="right"
        width={Math.min(window.innerWidth * 0.92, 1100)}
        open={open}
        onClose={onClose}
        styles={{ body: { padding: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column', height: '100%' } }}
      >
        <div className="drawer-body">
          {/* Left panel — schedule list */}
          <div
            className="left-panel"
            style={{ borderRight: `1px solid ${token.colorBorderSecondary}` }}
          >
            <div
              className="left-header"
              style={{ borderBottom: `1px solid ${token.colorBorderSecondary}` }}
            >
              <Text strong>
                {schedules.length > 0 ? `${schedules.length} schedule${schedules.length !== 1 ? 's' : ''}` : 'No schedules'}
              </Text>
              <Space size={4}>
                <Tooltip title="Refresh">
                  <Button
                    type="text"
                    size="small"
                    icon={<ReloadOutlined spin={loadingSchedules} />}
                    onClick={loadSchedules}
                  />
                </Tooltip>
                <Button type="primary" size="small" icon={<PlusOutlined />} onClick={openCreate}>
                  New
                </Button>
              </Space>
            </div>

            <div className="schedule-list">
              {loadingSchedules && schedules.length === 0 ? (
                <div className="spin-center">
                  <Spin />
                </div>
              ) : schedules.length === 0 ? (
                <Empty
                  description="No schedules yet"
                  image={Empty.PRESENTED_IMAGE_SIMPLE}
                  style={{ marginTop: 40 }}
                />
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  {schedules.map((sc) => (
                    <ScheduleCard
                      key={sc.id}
                      schedule={sc}
                      selected={sc.id === selectedId}
                      onSelect={() => setSelectedId(sc.id === selectedId ? null : sc.id)}
                      onToggle={(enabled) => handleToggle(sc, enabled)}
                      onEdit={() => openEdit(sc)}
                      onDelete={() => handleDeleteSchedule(sc.id)}
                      onTrigger={() => handleTrigger(sc.id)}
                    />
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Right panel — execution history */}
          <div className="right-panel">
            {selectedSchedule ? (
              <>
                <div
                  className="right-header"
                  style={{ borderBottom: `1px solid ${token.colorBorderSecondary}` }}
                >
                  <Space direction="vertical" size={2}>
                    <Title level={5} style={{ margin: 0 }}>{selectedSchedule.name}</Title>
                    {selectedSchedule.prompt && (
                      <Text type="secondary" style={{ fontSize: 12, maxWidth: 500 }} ellipsis>
                        {selectedSchedule.prompt.slice(0, 120)}{selectedSchedule.prompt.length > 120 ? '…' : ''}
                      </Text>
                    )}
                  </Space>
                  <Space>
                    <Button
                      size="small"
                      icon={<ReloadOutlined spin={loadingExecs} />}
                      onClick={() => loadExecutions(selectedSchedule.id)}
                    >
                      Refresh
                    </Button>
                  </Space>
                </div>

                {/* Schedule metadata */}
                <div className="meta-section" style={{ borderBottom: `1px solid ${token.colorBorderSecondary}` }}>
                  <Descriptions size="small" column={3}>
                    <Descriptions.Item label="Type">
                      <Tag color={selectedSchedule.type === 'cron' ? 'blue' : 'purple'}>
                        {selectedSchedule.type}
                      </Tag>
                    </Descriptions.Item>
                    {selectedSchedule.cronExpr && (
                      <Descriptions.Item label="Expression">
                        <Text style={{ fontFamily: 'monospace', fontSize: 12 }}>{selectedSchedule.cronExpr}</Text>
                      </Descriptions.Item>
                    )}
                    {selectedSchedule.nextRunAt && (
                      <Descriptions.Item label="Next run">{fmtDate(selectedSchedule.nextRunAt)}</Descriptions.Item>
                    )}
                    {selectedSchedule.lastRunAt && (
                      <Descriptions.Item label="Last run">{fmtDate(selectedSchedule.lastRunAt)}</Descriptions.Item>
                    )}
                    <Descriptions.Item label="Retain">
                      {selectedSchedule.retainHistory === 0 ? 'All' : selectedSchedule.retainHistory}
                    </Descriptions.Item>
                    {selectedSchedule.allowedTools?.length ? (
                      <Descriptions.Item label="Tools">
                        {selectedSchedule.allowedTools.map((t) => <Tag key={t} style={{ fontSize: 11 }}>{t}</Tag>)}
                      </Descriptions.Item>
                    ) : null}
                  </Descriptions>
                </div>

                <div className="exec-list">
                  {loadingExecs ? (
                    <div className="spin-center"><Spin /></div>
                  ) : executions.length === 0 ? (
                    <Empty description="No executions yet" image={Empty.PRESENTED_IMAGE_SIMPLE} style={{ marginTop: 40 }} />
                  ) : (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                      {executions.map((exec) => (
                        <ExecutionItem
                          key={exec.id}
                          exec={exec}
                          onDelete={handleDeleteExecution}
                        />
                      ))}
                    </div>
                  )}
                </div>
              </>
            ) : (
              <div className="centered">
                <Empty
                  description="Select a schedule to see execution history"
                  image={Empty.PRESENTED_IMAGE_SIMPLE}
                />
              </div>
            )}
          </div>
        </div>
      </Drawer>

      <ScheduleForm
        open={formOpen}
        initial={editingSchedule ?? undefined}
        models={models}
        tools={tools}
        uiConfig={uiConfig}
        onSubmit={handleFormSubmit}
        onClose={() => { setFormOpen(false); setEditingSchedule(null) }}
      />
    </>
  )
}
