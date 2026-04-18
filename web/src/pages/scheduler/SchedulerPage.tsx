import {
  Badge,
  Button,
  Collapse,
  Descriptions,
  Empty,
  Input,
  Popconfirm,
  Radio,
  Segmented,
  Space,
  Spin,
  Switch,
  Tag,
  Tooltip,
  Typography,
  message,
  theme,
} from 'antd'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { buildMarkdownComponents } from '../../components/markdown/buildComponents'
import { LLMTraceView } from '../../components/trace/TraceDrawer'
import {
  ClockCircleOutlined,
  DeleteOutlined,
  EditOutlined,
  FilterOutlined,
  PlusOutlined,
  ReloadOutlined,
  ThunderboltOutlined,
} from '@ant-design/icons'
import { useCallback, useEffect, useMemo, useState } from 'react'
import type { Execution, ExecutionStatus, Schedule } from '../../types/scheduler'
import type { LLMRound } from '../../types/chat'
import type { ModelInfo } from '../../api/client'
import type { ToolInfo, UIConfig } from '../../types/chat'
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
import './SchedulerPage.scss'

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

/** Human-readable relative time: "3m ago", "2h ago", "5d ago". */
function relativeTime(iso?: string): string {
  if (!iso) return ''
  const diff = Date.now() - new Date(iso).getTime()
  const s = Math.floor(diff / 1000)
  if (s < 60) return `${s}s ago`
  const m = Math.floor(s / 60)
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  return `${Math.floor(h / 24)}d ago`
}

interface TokenStats {
  promptTokens: number
  completionTokens: number
  cachedTokens: number
  reasoningTokens: number
}

function computeTokenStats(trace?: LLMRound[]): TokenStats | null {
  if (!trace?.length) return null
  let promptTokens = 0, completionTokens = 0, cachedTokens = 0, reasoningTokens = 0
  for (const r of trace) {
    promptTokens     += r.usage?.prompt_tokens     ?? 0
    completionTokens += r.usage?.completion_tokens ?? 0
    cachedTokens     += r.usage?.cached_tokens     ?? 0
    reasoningTokens  += r.usage?.reasoning_tokens  ?? 0
  }
  if (promptTokens === 0 && completionTokens === 0) return null
  return { promptTokens, completionTokens, cachedTokens, reasoningTokens }
}

function StatusBadge({ status }: { status: Execution['status'] }) {
  const map = {
    running: 'processing',
    success: 'success',
    error:   'error',
  } as const
  return <Badge status={map[status]} text={status} />
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
  const mdComponents = buildMarkdownComponents(token)
  const tokenStats = useMemo(() => computeTokenStats(exec.trace), [exec.trace])
  const borderColor = exec.status === 'error'
    ? token.colorErrorBorder
    : exec.status === 'running'
      ? token.colorPrimaryBorder
      : token.colorBorderSecondary

  return (
    <div
      className="exec-item"
      style={{
        border: `1px solid ${borderColor}`,
        background: token.colorBgContainer,
      }}
    >
      <div className="exec-item-header">
        <Space direction="vertical" size={3} style={{ flex: 1 }}>
          <Space wrap size={8}>
            <StatusBadge status={exec.status} />
            {exec.modelUsed && <Tag style={{ fontSize: 11 }}>{exec.providerUsed ? `${exec.providerUsed} · ${exec.modelUsed}` : exec.modelUsed}</Tag>}
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
          {/* Token stats row */}
          {tokenStats && (
            <Space wrap size={10}>
              <Text type="secondary" style={{ fontSize: 11 }}>
                ↑ {tokenStats.promptTokens.toLocaleString()} in
              </Text>
              <Text type="secondary" style={{ fontSize: 11 }}>
                ↓ {tokenStats.completionTokens.toLocaleString()} out
              </Text>
              {tokenStats.cachedTokens > 0 && (
                <Text style={{ fontSize: 11, color: token.colorSuccess }}>
                  ⚡ {tokenStats.cachedTokens.toLocaleString()} cached
                </Text>
              )}
              {tokenStats.reasoningTokens > 0 && (
                <Text type="secondary" style={{ fontSize: 11 }}>
                  💭 {tokenStats.reasoningTokens.toLocaleString()} reasoning
                </Text>
              )}
            </Space>
          )}
          <Tooltip title={fmtDate(exec.triggeredAt)}>
            <Text type="secondary" style={{ fontSize: 11, cursor: 'default' }}>{relativeTime(exec.triggeredAt)}</Text>
          </Tooltip>
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

      {(exec.response || (exec.trace?.length ?? 0) > 0) && (
        <Collapse
          size="small"
          ghost
          style={{ marginTop: 8 }}
          defaultActiveKey={[]}
          items={[
            ...(exec.response ? [{
              key: 'resp',
              label: <Text style={{ fontSize: 12 }}>Response</Text>,
              children: (
                <div
                  style={{
                    borderLeft: `3px solid ${token.colorPrimary}`,
                    background: token.colorFillAlter,
                    borderRadius: '0 6px 6px 0',
                    padding: '10px 14px',
                    fontSize: 13,
                    lineHeight: 1.7,
                    wordBreak: 'break-word',
                  }}
                >
                  <ReactMarkdown remarkPlugins={[remarkGfm]} components={mdComponents}>
                    {exec.response}
                  </ReactMarkdown>
                </div>
              ),
            }] : []),
            ...(exec.trace?.length ? [{
              key: 'trace',
              label: (
                <Space size={6}>
                  <Text style={{ fontSize: 12 }}>LLM Trace</Text>
                  <Tag style={{ fontSize: 10, margin: 0 }}>{exec.trace.length} round{exec.trace.length !== 1 ? 's' : ''}</Tag>
                  {exec.llmCalls != null && exec.llmCalls > 0 && (
                    <Text type="secondary" style={{ fontSize: 11 }}>
                      {fmtDuration(exec.trace.reduce((s, r) => s + r.llm_duration_ms, 0))}
                    </Text>
                  )}
                  {exec.trace.some(r => (r.usage?.total_tokens ?? 0) > 0) && (
                    <Text type="secondary" style={{ fontSize: 11 }}>
                      {exec.trace.reduce((s, r) => s + (r.usage?.total_tokens ?? 0), 0).toLocaleString()} tok
                    </Text>
                  )}
                </Space>
              ),
              children: <LLMTraceView rounds={exec.trace} />,
            }] : []),
          ]}
        />
      )}
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
  const dimmed = !schedule.enabled

  return (
    <div
      onClick={onSelect}
      className="schedule-card"
      style={{
        border: `1px solid ${selected ? token.colorPrimary : token.colorBorderSecondary}`,
        background: selected ? token.colorPrimaryBg : token.colorBgContainer,
        opacity: dimmed ? 0.6 : 1,
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
          {schedule.modelId && (
            <Tag style={{ fontSize: 11 }}>
              {schedule.provider ? `${schedule.provider} · ${schedule.modelId}` : schedule.modelId}
            </Tag>
          )}
        </Space>
        {schedule.nextRunAt && (
          <Text type="secondary" style={{ fontSize: 11 }}>
            <ClockCircleOutlined style={{ marginRight: 4 }} />
            Next: {fmtDate(schedule.nextRunAt)}
          </Text>
        )}
        {schedule.lastRunAt ? (
          <Text type="secondary" style={{ fontSize: 11 }}>
            Last: {relativeTime(schedule.lastRunAt)}
          </Text>
        ) : (
          <Text type="secondary" style={{ fontSize: 11, fontStyle: 'italic' }}>Never run</Text>
        )}
      </Space>
    </div>
  )
}

// ── Main Page ────────────────────────────────────────────────────────────────

interface Props {
  models: ModelInfo[]
  tools: ToolInfo[]
  uiConfig: UIConfig
}

type StatusFilter = 'all' | 'enabled' | 'disabled'
type ExecStatusFilter = 'all' | ExecutionStatus

const EXEC_STATUS_OPTIONS: { label: string; value: ExecStatusFilter }[] = [
  { label: 'All', value: 'all' },
  { label: 'Success', value: 'success' },
  { label: 'Error', value: 'error' },
  { label: 'Running', value: 'running' },
]

export function SchedulerPage({ models, tools, uiConfig }: Props) {
  const { token } = useToken()
  const [schedules, setSchedules] = useState<Schedule[]>([])
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [executions, setExecutions] = useState<Execution[]>([])
  const [loadingSchedules, setLoadingSchedules] = useState(false)
  const [loadingExecs, setLoadingExecs] = useState(false)
  const [formOpen, setFormOpen] = useState(false)
  const [editingSchedule, setEditingSchedule] = useState<Schedule | null>(null)
  const [msgApi, contextHolder] = message.useMessage()

  // Schedule filters
  const [nameFilter, setNameFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')

  // Execution filter
  const [execStatusFilter, setExecStatusFilter] = useState<ExecStatusFilter>('all')

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
    loadSchedules()
  }, [loadSchedules])

  useEffect(() => {
    if (selectedId) loadExecutions(selectedId)
    else setExecutions([])
  }, [selectedId, loadExecutions])

  // Auto-refresh executions while any are still running
  useEffect(() => {
    const hasRunning = executions.some(e => e.status === 'running')
    if (!hasRunning || !selectedId) return
    const timer = setInterval(() => loadExecutions(selectedId), 3000)
    return () => clearInterval(timer)
  }, [executions, selectedId, loadExecutions])

  // Filtered + derived schedules
  const filteredSchedules = useMemo(() => {
    return schedules.filter(sc => {
      if (nameFilter && !sc.name.toLowerCase().includes(nameFilter.toLowerCase())) return false
      if (statusFilter === 'enabled' && !sc.enabled) return false
      if (statusFilter === 'disabled' && sc.enabled) return false
      return true
    })
  }, [schedules, nameFilter, statusFilter])

  // Filtered + sorted executions (newest first)
  const filteredExecutions = useMemo(() => {
    const sorted = [...executions].sort(
      (a, b) => new Date(b.triggeredAt).getTime() - new Date(a.triggeredAt).getTime()
    )
    if (execStatusFilter === 'all') return sorted
    return sorted.filter(e => e.status === execStatusFilter)
  }, [executions, execStatusFilter])

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

  const hasScheduleFilters = nameFilter !== '' || statusFilter !== 'all'
  const clearScheduleFilters = () => { setNameFilter(''); setStatusFilter('all') }

  const runningCount = executions.filter(e => e.status === 'running').length

  return (
    <>
      {contextHolder}
      <div className="page">
        {/* Left panel — schedule list */}
        <div
          className="left-panel"
          style={{ borderRight: `1px solid ${token.colorBorderSecondary}` }}
        >
          {/* Left header */}
          <div
            className="left-header"
            style={{ borderBottom: `1px solid ${token.colorBorderSecondary}` }}
          >
            <div className="left-header-row">
              <Text strong style={{ fontSize: 13 }}>
                {hasScheduleFilters
                  ? `${filteredSchedules.length} / ${schedules.length} schedule${schedules.length !== 1 ? 's' : ''}`
                  : `${schedules.length} schedule${schedules.length !== 1 ? 's' : ''}`}
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

            {/* Search */}
            <Input
              size="small"
              placeholder="Search by name…"
              allowClear
              value={nameFilter}
              onChange={e => setNameFilter(e.target.value)}
              style={{ marginBottom: 6 }}
            />

            {/* Status filter */}
            <Segmented
              size="small"
              block
              value={statusFilter}
              onChange={v => setStatusFilter(v as StatusFilter)}
              options={[
                { label: 'All', value: 'all' },
                {
                  label: (
                    <Space size={4}>
                      <Badge status="success" />
                      Active
                    </Space>
                  ),
                  value: 'enabled',
                },
                {
                  label: (
                    <Space size={4}>
                      <Badge status="default" />
                      Disabled
                    </Space>
                  ),
                  value: 'disabled',
                },
              ]}
            />
          </div>

          {/* Schedule list */}
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
              >
                <Button type="primary" size="small" icon={<PlusOutlined />} onClick={openCreate}>
                  Create first schedule
                </Button>
              </Empty>
            ) : filteredSchedules.length === 0 ? (
              <Empty
                description={`No schedules match "${nameFilter || statusFilter}"`}
                image={Empty.PRESENTED_IMAGE_SIMPLE}
                style={{ marginTop: 40 }}
              >
                <Button size="small" onClick={clearScheduleFilters}>Clear filters</Button>
              </Empty>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {filteredSchedules.map((sc) => (
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
              {/* Right header */}
              <div
                className="right-header"
                style={{ borderBottom: `1px solid ${token.colorBorderSecondary}` }}
              >
                <div className="right-header-row">
                  <Space direction="vertical" size={2} style={{ flex: 1, minWidth: 0 }}>
                    <Space size={8} wrap>
                      <Title level={5} style={{ margin: 0 }}>{selectedSchedule.name}</Title>
                      {runningCount > 0 && (
                        <Tag color="processing" style={{ fontSize: 11 }}>
                          {runningCount} running
                        </Tag>
                      )}
                    </Space>
                    {selectedSchedule.prompt && (
                      <Text type="secondary" style={{ fontSize: 12 }} ellipsis>
                        {selectedSchedule.prompt.length > 100
                          ? selectedSchedule.prompt.slice(0, 100) + '…'
                          : selectedSchedule.prompt}
                      </Text>
                    )}
                  </Space>
                  <Button
                    size="small"
                    icon={<ReloadOutlined spin={loadingExecs} />}
                    onClick={() => loadExecutions(selectedSchedule.id)}
                    style={{ marginLeft: 12, flexShrink: 0 }}
                  >
                    Refresh
                  </Button>
                </div>
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
                    <Descriptions.Item label="Last run">{relativeTime(selectedSchedule.lastRunAt)}</Descriptions.Item>
                  )}
                  <Descriptions.Item label="Retain">
                    {selectedSchedule.retainHistory === 0 ? 'All' : `Last ${selectedSchedule.retainHistory}`}
                  </Descriptions.Item>
                  <Descriptions.Item label="Trace">
                    {selectedSchedule.traceEnabled == null
                      ? <Text type="secondary" style={{ fontSize: 11 }}>default</Text>
                      : selectedSchedule.traceEnabled
                        ? <Tag color="green"  style={{ fontSize: 11 }}>on</Tag>
                        : <Tag color="default" style={{ fontSize: 11 }}>off</Tag>
                    }
                  </Descriptions.Item>
                  {selectedSchedule.allowedTools?.length ? (
                    <Descriptions.Item label="Tools">
                      {selectedSchedule.allowedTools.map((t) => <Tag key={t} style={{ fontSize: 11 }}>{t}</Tag>)}
                    </Descriptions.Item>
                  ) : null}
                  {selectedSchedule.params && (
                    <Descriptions.Item label="LLM params" span={3}>
                      <Space size={6} wrap>
                        {selectedSchedule.params.temperature != null && (
                          <Tag style={{ fontSize: 11 }}>temp={selectedSchedule.params.temperature}</Tag>
                        )}
                        {selectedSchedule.params.max_tokens != null && (
                          <Tag style={{ fontSize: 11 }}>max_tokens={selectedSchedule.params.max_tokens}</Tag>
                        )}
                        {selectedSchedule.params.top_p != null && (
                          <Tag style={{ fontSize: 11 }}>top_p={selectedSchedule.params.top_p}</Tag>
                        )}
                        {selectedSchedule.params.top_k != null && (
                          <Tag style={{ fontSize: 11 }}>top_k={selectedSchedule.params.top_k}</Tag>
                        )}
                      </Space>
                    </Descriptions.Item>
                  )}
                </Descriptions>
              </div>

              {/* Execution filter toolbar */}
              <div
                className="exec-filter-bar"
                style={{ borderBottom: `1px solid ${token.colorBorderSecondary}` }}
              >
                <Space size={6}>
                  <FilterOutlined style={{ color: token.colorTextSecondary, fontSize: 12 }} />
                  <Text type="secondary" style={{ fontSize: 12 }}>
                    {execStatusFilter === 'all'
                      ? `${executions.length} execution${executions.length !== 1 ? 's' : ''}`
                      : `${filteredExecutions.length} of ${executions.length}`}
                  </Text>
                </Space>
                <Radio.Group
                  size="small"
                  value={execStatusFilter}
                  onChange={e => setExecStatusFilter(e.target.value)}
                >
                  {EXEC_STATUS_OPTIONS.map(opt => (
                    <Radio.Button key={opt.value} value={opt.value}>
                      {opt.label}
                      {opt.value !== 'all' && executions.filter(e => e.status === opt.value).length > 0 && (
                        <Text
                          style={{
                            marginLeft: 4,
                            fontSize: 11,
                            color: opt.value === 'error' ? token.colorError : opt.value === 'running' ? token.colorPrimary : token.colorSuccess,
                          }}
                        >
                          {executions.filter(e => e.status === opt.value).length}
                        </Text>
                      )}
                    </Radio.Button>
                  ))}
                </Radio.Group>
              </div>

              {/* Execution list */}
              <div className="exec-list">
                {loadingExecs && executions.length === 0 ? (
                  <div className="spin-center"><Spin /></div>
                ) : executions.length === 0 ? (
                  <Empty
                    description="No executions yet — trigger the schedule to see results here"
                    image={Empty.PRESENTED_IMAGE_SIMPLE}
                    style={{ marginTop: 40 }}
                  >
                    <Button
                      size="small"
                      icon={<ThunderboltOutlined />}
                      onClick={() => handleTrigger(selectedSchedule.id)}
                    >
                      Run now
                    </Button>
                  </Empty>
                ) : filteredExecutions.length === 0 ? (
                  <Empty
                    description={`No ${execStatusFilter} executions`}
                    image={Empty.PRESENTED_IMAGE_SIMPLE}
                    style={{ marginTop: 40 }}
                  >
                    <Button size="small" onClick={() => setExecStatusFilter('all')}>Show all</Button>
                  </Empty>
                ) : (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                    {filteredExecutions.map((exec) => (
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
