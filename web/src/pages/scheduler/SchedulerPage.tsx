import {
  Badge,
  Button,
  Collapse,
  Descriptions,
  Empty,
  Grid,
  Input,
  Popconfirm,
  Radio,
  Segmented,
  Space,
  Spin,
  Switch,
  Table,
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
const { useBreakpoint } = Grid

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
  const diffMs = new Date(iso).getTime() - Date.now()
  const future = diffMs > 0
  const seconds = Math.floor(Math.abs(diffMs) / 1000)

  if (seconds < 60) return future ? `in ${seconds}s` : `${seconds}s ago`

  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return future ? `in ${minutes}m` : `${minutes}m ago`

  const hours = Math.floor(minutes / 60)
  if (hours < 24) return future ? `in ${hours}h` : `${hours}h ago`

  const days = Math.floor(hours / 24)
  return future ? `in ${days}d` : `${days}d ago`
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

// ── Main Page ────────────────────────────────────────────────────────────────

interface Props {
  models: ModelInfo[]
  tools: ToolInfo[]
  uiConfig: UIConfig
  selectedScheduleId?: string | null
  schedulerEditorMode?: 'new' | 'edit' | null
  onSelectedScheduleChange?: (id: string | null) => void
  onCreateSchedule?: () => void
  onEditSchedule?: (id: string) => void
  onCloseEditor?: () => void
}

type StatusFilter = 'all' | 'enabled' | 'disabled'
type ExecStatusFilter = 'all' | ExecutionStatus

const EXEC_STATUS_OPTIONS: { label: string; value: ExecStatusFilter }[] = [
  { label: 'All', value: 'all' },
  { label: 'Success', value: 'success' },
  { label: 'Error', value: 'error' },
  { label: 'Running', value: 'running' },
]

export function SchedulerPage({
  models,
  tools,
  uiConfig,
  selectedScheduleId,
  schedulerEditorMode,
  onSelectedScheduleChange,
  onCreateSchedule,
  onEditSchedule,
  onCloseEditor,
}: Props) {
  const { token } = useToken()
  const screens = useBreakpoint()
  const [schedules, setSchedules] = useState<Schedule[]>([])
  const [selectedId, setSelectedId] = useState<string | null>(selectedScheduleId ?? null)
  const [executions, setExecutions] = useState<Execution[]>([])
  const [loadingSchedules, setLoadingSchedules] = useState(false)
  const [loadingExecs, setLoadingExecs] = useState(false)
  const [loadedSchedulesOnce, setLoadedSchedulesOnce] = useState(false)
  const [msgApi, contextHolder] = message.useMessage()

  // Schedule filters
  const [nameFilter, setNameFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')
  const [scheduleSortKey, setScheduleSortKey] = useState<'default' | 'name' | 'lastRun' | 'nextRun'>('default')

  // Execution filter
  const [execStatusFilter, setExecStatusFilter] = useState<ExecStatusFilter>('all')

  const loadSchedules = useCallback(async () => {
    setLoadingSchedules(true)
    try {
      const data = await apiListSchedules()
      setSchedules(data)
    } finally {
      setLoadedSchedulesOnce(true)
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
    if (selectedScheduleId === undefined || selectedScheduleId === selectedId) return
    setSelectedId(selectedScheduleId ?? null)
  }, [selectedId, selectedScheduleId])

  useEffect(() => {
    if (selectedId) loadExecutions(selectedId)
    else setExecutions([])
  }, [selectedId, loadExecutions])

  useEffect(() => {
    if (!loadedSchedulesOnce || loadingSchedules || !selectedId) return
    if (schedules.some((s) => s.id === selectedId)) return
    setSelectedId(null)
    setExecutions([])
    onSelectedScheduleChange?.(null)
  }, [loadedSchedulesOnce, loadingSchedules, onSelectedScheduleChange, schedules, selectedId])

  // Auto-refresh executions while any are still running
  useEffect(() => {
    const hasRunning = executions.some(e => e.status === 'running')
    if (!hasRunning || !selectedId) return
    const timer = setInterval(() => loadExecutions(selectedId), 3000)
    return () => clearInterval(timer)
  }, [executions, selectedId, loadExecutions])

  // Filtered + derived schedules
  const filteredSchedules = useMemo(() => {
    const base = schedules.filter(sc => {
      if (nameFilter && !sc.name.toLowerCase().includes(nameFilter.toLowerCase())) return false
      if (statusFilter === 'enabled' && !sc.enabled) return false
      if (statusFilter === 'disabled' && sc.enabled) return false
      return true
    })

    if (scheduleSortKey === 'name') {
      return [...base].sort((a, b) => a.name.localeCompare(b.name))
    }
    if (scheduleSortKey === 'lastRun') {
      return [...base].sort((a, b) => new Date(b.lastRunAt || 0).getTime() - new Date(a.lastRunAt || 0).getTime())
    }
    if (scheduleSortKey === 'nextRun') {
      return [...base].sort((a, b) => new Date(a.nextRunAt || 0).getTime() - new Date(b.nextRunAt || 0).getTime())
    }
    return base
  }, [schedules, nameFilter, statusFilter, scheduleSortKey])

  // Filtered + sorted executions (newest first)
  const filteredExecutions = useMemo(() => {
    const sorted = [...executions].sort(
      (a, b) => new Date(b.triggeredAt).getTime() - new Date(a.triggeredAt).getTime()
    )
    if (execStatusFilter === 'all') return sorted
    return sorted.filter(e => e.status === execStatusFilter)
  }, [executions, execStatusFilter])

  const selectedSchedule = schedules.find((s) => s.id === selectedId) ?? null
  const formOpen = schedulerEditorMode === 'new' || schedulerEditorMode === 'edit'
  const editingSchedule = schedulerEditorMode === 'edit' ? selectedSchedule : null
  const showHistoryPage = !formOpen && Boolean(selectedSchedule)

  const handleSelectSchedule = useCallback((id: string | null) => {
    setSelectedId(id)
    onSelectedScheduleChange?.(id)
  }, [onSelectedScheduleChange])

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
      setTimeout(() => {
        void loadSchedules()
        if (selectedId === id) void loadExecutions(id)
      }, 2000)
    } catch (e: any) {
      msgApi.error(e.message || 'Failed to trigger')
    }
  }

  const handleDeleteSchedule = async (id: string) => {
    try {
      await apiDeleteSchedule(id)
      setSchedules((prev) => prev.filter((s) => s.id !== id))
      if (selectedId === id) {
        setSelectedId(null)
        setExecutions([])
        onSelectedScheduleChange?.(null)
      }
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
      setSelectedId(updated.id)
      onSelectedScheduleChange?.(updated.id)
      msgApi.success('Schedule updated')
    } else {
      const created = await apiCreateSchedule(values as any)
      setSchedules((prev) => [created, ...prev])
      setSelectedId(created.id)
      onSelectedScheduleChange?.(created.id)
      msgApi.success('Schedule created')
    }
  }

  const openEdit = (sc: Schedule) => {
    onEditSchedule?.(sc.id)
  }

  const openCreate = () => {
    onCreateSchedule?.()
  }

  const hasScheduleFilters = nameFilter !== '' || statusFilter !== 'all'
  const clearScheduleFilters = () => { setNameFilter(''); setStatusFilter('all') }

  const runningCount = executions.filter(e => e.status === 'running').length
  const isMobile = !screens.md
  const scheduleColumns = [
    {
      title: 'Name',
      key: 'name',
      width: '48%',
      sorter: (a: Schedule, b: Schedule) => a.name.localeCompare(b.name),
      render: (_: unknown, sc: Schedule) => (
        <Space direction="vertical" size={2} style={{ minWidth: 0 }}>
          <Space size={8} wrap>
            <Button
              type="link"
              size="small"
              className="schedule-name-link"
              style={{ padding: 0, height: 'auto', fontWeight: 600 }}
              onClick={() => handleSelectSchedule(sc.id)}
            >
              {sc.name}
            </Button>
            <Tag color={sc.enabled ? 'green' : 'default'}>{sc.enabled ? 'enabled' : 'disabled'}</Tag>
            <Tag color={sc.type === 'cron' ? 'blue' : 'purple'}>{sc.type}</Tag>
          </Space>
          <Text type="secondary" ellipsis style={{ maxWidth: 520, fontSize: 12 }}>
            {sc.prompt}
          </Text>
        </Space>
      ),
    },
    {
      title: 'Schedule',
      key: 'schedule',
      width: '20%',
      render: (_: unknown, sc: Schedule) => (
        <Text style={{ fontSize: 12 }}>
          {sc.type === 'cron' ? sc.cronExpr || '—' : fmtDate(sc.runAt)}
        </Text>
      ),
    },
    {
      title: 'Last Run',
      key: 'lastRunAt',
      width: '12%',
      sorter: (a: Schedule, b: Schedule) => new Date(a.lastRunAt || 0).getTime() - new Date(b.lastRunAt || 0).getTime(),
      render: (_: unknown, sc: Schedule) => {
        if (!sc.lastRunAt) return <Text style={{ fontSize: 12 }}>-</Text>
        return (
          <Tooltip title={fmtDate(sc.lastRunAt)}>
            <Text style={{ fontSize: 12, cursor: 'default' }}>{relativeTime(sc.lastRunAt)}</Text>
          </Tooltip>
        )
      },
    },
    {
      title: 'Next Run',
      key: 'nextRunAt',
      width: '12%',
      sorter: (a: Schedule, b: Schedule) => new Date(a.nextRunAt || 0).getTime() - new Date(b.nextRunAt || 0).getTime(),
      render: (_: unknown, sc: Schedule) => {
        if (!sc.enabled) return <Text style={{ fontSize: 12 }}>-</Text>
        if (!sc.nextRunAt) return <Text style={{ fontSize: 12 }}>-</Text>
        return (
          <Tooltip title={fmtDate(sc.nextRunAt)}>
            <Text style={{ fontSize: 12, cursor: 'default' }}>{relativeTime(sc.nextRunAt)}</Text>
          </Tooltip>
        )
      },
    },
    {
      title: 'Actions',
      key: 'actions',
      width: '8%',
      render: (_: unknown, sc: Schedule) => (
        <Space size={4} onClick={(e) => e.stopPropagation()}>
          <Tooltip title="Run now">
            <Button size="small" icon={<ThunderboltOutlined />} onClick={() => handleTrigger(sc.id)} />
          </Tooltip>
          <Tooltip title="Edit">
            <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(sc)} />
          </Tooltip>
          <Switch size="small" checked={sc.enabled} onChange={(enabled) => handleToggle(sc, enabled)} />
          <Popconfirm title="Delete this schedule?" okText="Delete" okType="danger" onConfirm={() => handleDeleteSchedule(sc.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <>
      {contextHolder}
      <div className="scheduler-page">
        {formOpen ? (
          <div className="scheduler-surface">
            <div className="page-header" style={{ borderBottom: `1px solid ${token.colorBorderSecondary}` }}>
              <Space direction="vertical" size={2} style={{ minWidth: 0 }}>
                <Title level={4} style={{ margin: 0 }}>{schedulerEditorMode === 'edit' ? 'Edit Schedule' : 'New Schedule'}</Title>
                <Text type="secondary">Configure when the schedule runs and how it should call the model.</Text>
              </Space>
            </div>
            {schedulerEditorMode === 'edit' && selectedScheduleId && !editingSchedule ? (
              <div className="centered-page">
                {loadingSchedules ? <Spin /> : <Empty description="Schedule not found" image={Empty.PRESENTED_IMAGE_SIMPLE} />}
              </div>
            ) : (
              <ScheduleForm
                open={formOpen}
                initial={editingSchedule ?? undefined}
                models={models}
                tools={tools}
                uiConfig={uiConfig}
                onSubmit={handleFormSubmit}
                onClose={() => onCloseEditor?.()}
              />
            )}
          </div>
        ) : showHistoryPage && selectedSchedule ? (
          <div className="scheduler-surface">
            <div className="page-header" style={{ borderBottom: `1px solid ${token.colorBorderSecondary}` }}>
              <div className="page-header-row">
                <Space direction="vertical" size={4} style={{ minWidth: 0, flex: 1 }}>
                  <Button type="link" size="small" style={{ padding: 0, alignSelf: 'flex-start' }} onClick={() => handleSelectSchedule(null)}>
                    All schedules
                  </Button>
                  <Space size={8} wrap>
                    <Title level={4} style={{ margin: 0 }}>{selectedSchedule.name}</Title>
                    <Tag color={selectedSchedule.enabled ? 'green' : 'default'}>{selectedSchedule.enabled ? 'enabled' : 'disabled'}</Tag>
                    <Tag color={selectedSchedule.type === 'cron' ? 'blue' : 'purple'}>{selectedSchedule.type}</Tag>
                    {runningCount > 0 && <Tag color="processing">{runningCount} running</Tag>}
                  </Space>
                  <Text type="secondary" style={{ fontSize: 13 }}>{selectedSchedule.prompt}</Text>
                </Space>
                <Space wrap>
                  <Button icon={<ThunderboltOutlined />} onClick={() => handleTrigger(selectedSchedule.id)}>Run now</Button>
                  <Button icon={<EditOutlined />} onClick={() => openEdit(selectedSchedule)}>Edit</Button>
                  <Button icon={<ReloadOutlined spin={loadingExecs} />} onClick={() => loadExecutions(selectedSchedule.id)}>Refresh</Button>
                </Space>
              </div>
            </div>

            <div className="history-meta">
              <Descriptions size="small" column={3}>
                <Descriptions.Item label="Schedule">
                  {selectedSchedule.type === 'cron' ? selectedSchedule.cronExpr || '—' : fmtDate(selectedSchedule.runAt)}
                </Descriptions.Item>
                <Descriptions.Item label="Next run">{selectedSchedule.nextRunAt ? fmtDate(selectedSchedule.nextRunAt) : '—'}</Descriptions.Item>
                <Descriptions.Item label="Last run">{selectedSchedule.lastRunAt ? relativeTime(selectedSchedule.lastRunAt) : 'Never'}</Descriptions.Item>
                <Descriptions.Item label="Retain">
                  {selectedSchedule.retainHistory === 0 ? 'All executions' : `Last ${selectedSchedule.retainHistory}`}
                </Descriptions.Item>
                <Descriptions.Item label="Trace">
                  {selectedSchedule.traceEnabled == null
                    ? <Text type="secondary">default</Text>
                    : selectedSchedule.traceEnabled
                      ? <Tag color="green">on</Tag>
                      : <Tag>off</Tag>}
                </Descriptions.Item>
                <Descriptions.Item label="Model">
                  {selectedSchedule.modelId ? (selectedSchedule.provider ? `${selectedSchedule.provider} · ${selectedSchedule.modelId}` : selectedSchedule.modelId) : 'Auto'}
                </Descriptions.Item>
                <Descriptions.Item label="Tools" span={3}>
                  {selectedSchedule.allowedTools?.length ? selectedSchedule.allowedTools.map((t) => <Tag key={t}>{t}</Tag>) : <Text type="secondary">All tools</Text>}
                </Descriptions.Item>
                {selectedSchedule.params && (
                  <Descriptions.Item label="LLM params" span={3}>
                    <Space size={6} wrap>
                      {selectedSchedule.params.temperature != null && <Tag>temp={selectedSchedule.params.temperature}</Tag>}
                      {selectedSchedule.params.max_tokens != null && <Tag>max_tokens={selectedSchedule.params.max_tokens}</Tag>}
                      {selectedSchedule.params.top_p != null && <Tag>top_p={selectedSchedule.params.top_p}</Tag>}
                      {selectedSchedule.params.top_k != null && <Tag>top_k={selectedSchedule.params.top_k}</Tag>}
                    </Space>
                  </Descriptions.Item>
                )}
              </Descriptions>
            </div>

            <div className="history-toolbar" style={{ borderTop: `1px solid ${token.colorBorderSecondary}`, borderBottom: `1px solid ${token.colorBorderSecondary}` }}>
              <Space size={6}>
                <FilterOutlined style={{ color: token.colorTextSecondary, fontSize: 12 }} />
                <Text type="secondary" style={{ fontSize: 12 }}>
                  {execStatusFilter === 'all'
                    ? `${executions.length} execution${executions.length !== 1 ? 's' : ''}`
                    : `${filteredExecutions.length} of ${executions.length}`}
                </Text>
              </Space>
              <Radio.Group size="small" value={execStatusFilter} onChange={e => setExecStatusFilter(e.target.value)}>
                {EXEC_STATUS_OPTIONS.map(opt => (
                  <Radio.Button key={opt.value} value={opt.value}>{opt.label}</Radio.Button>
                ))}
              </Radio.Group>
            </div>

            <div className="history-content">
              {loadingExecs && executions.length === 0 ? (
                <div className="spin-center"><Spin /></div>
              ) : executions.length === 0 ? (
                <div className="centered-page">
                  <Empty description="No executions yet. Run this schedule to build history." image={Empty.PRESENTED_IMAGE_SIMPLE}>
                    <Button icon={<ThunderboltOutlined />} onClick={() => handleTrigger(selectedSchedule.id)}>Run now</Button>
                  </Empty>
                </div>
              ) : filteredExecutions.length === 0 ? (
                <div className="centered-page">
                  <Empty description={`No ${execStatusFilter} executions`} image={Empty.PRESENTED_IMAGE_SIMPLE}>
                    <Button onClick={() => setExecStatusFilter('all')}>Show all</Button>
                  </Empty>
                </div>
              ) : (
                <div className="execution-stack">
                  {filteredExecutions.map((exec) => (
                    <ExecutionItem key={exec.id} exec={exec} onDelete={handleDeleteExecution} />
                  ))}
                </div>
              )}
            </div>
          </div>
        ) : (
          <div className="scheduler-surface">
            <div className="page-header" style={{ borderBottom: `1px solid ${token.colorBorderSecondary}` }}>
              <div className="page-header-row">
                <Space direction="vertical" size={2} style={{ minWidth: 0 }}>
                  <Title level={4} style={{ margin: 0 }}>Schedules</Title>
                  <Text type="secondary">Manage recurring prompts and open a schedule to review its execution history.</Text>
                </Space>
                <Space>
                  <Button icon={<ReloadOutlined spin={loadingSchedules} />} onClick={loadSchedules}>Refresh</Button>
                  <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>New schedule</Button>
                </Space>
              </div>
            </div>

            <div className="list-toolbar">
              <Input
                placeholder="Search schedules by name..."
                allowClear
                value={nameFilter}
                onChange={e => setNameFilter(e.target.value)}
                className="schedule-search"
              />
              <Segmented
                value={statusFilter}
                onChange={v => setStatusFilter(v as StatusFilter)}
                options={[
                  { label: 'All', value: 'all' },
                  { label: 'Active', value: 'enabled' },
                  { label: 'Disabled', value: 'disabled' },
                ]}
              />
              {isMobile && (
                <Segmented
                  value={scheduleSortKey}
                  onChange={v => setScheduleSortKey(v as 'default' | 'name' | 'lastRun' | 'nextRun')}
                  options={[
                    { label: 'Default', value: 'default' },
                    { label: 'Name', value: 'name' },
                    { label: 'Last run', value: 'lastRun' },
                    { label: 'Next run', value: 'nextRun' },
                  ]}
                />
              )}
              <Text type="secondary" className="schedule-count">
                {hasScheduleFilters
                  ? `${filteredSchedules.length} of ${schedules.length} schedules`
                  : `${schedules.length} schedule${schedules.length !== 1 ? 's' : ''}`}
              </Text>
            </div>

            <div className="list-content">
              {loadingSchedules && schedules.length === 0 ? (
                <div className="spin-center"><Spin /></div>
              ) : schedules.length === 0 ? (
                <div className="centered-page">
                  <Empty description="No schedules yet" image={Empty.PRESENTED_IMAGE_SIMPLE}>
                    <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>Create first schedule</Button>
                  </Empty>
                </div>
              ) : filteredSchedules.length === 0 ? (
                <div className="centered-page">
                  <Empty description="No schedules match the current filters" image={Empty.PRESENTED_IMAGE_SIMPLE}>
                    <Button onClick={clearScheduleFilters}>Clear filters</Button>
                  </Empty>
                </div>
              ) : isMobile ? (
                <div className="schedule-mobile-list">
                  {filteredSchedules.map((sc) => (
                    <div
                      key={sc.id}
                      className={`schedule-mobile-card${sc.id === selectedId ? ' schedule-mobile-card-selected' : ''}`}
                      style={{
                        border: `1px solid ${sc.id === selectedId ? token.colorPrimaryBorder : token.colorBorderSecondary}`,
                        background: token.colorBgContainer,
                      }}
                      onClick={() => handleSelectSchedule(sc.id)}
                    >
                      <div className="schedule-mobile-head">
                        <Space direction="vertical" size={4} style={{ minWidth: 0, flex: 1 }}>
                          <Space size={8} wrap>
                            <Button
                              type="link"
                              size="small"
                              className="schedule-name-link"
                              style={{ padding: 0, height: 'auto', fontWeight: 600 }}
                              onClick={() => handleSelectSchedule(sc.id)}
                            >
                              {sc.name}
                            </Button>
                            <Tag color={sc.enabled ? 'green' : 'default'}>{sc.enabled ? 'enabled' : 'disabled'}</Tag>
                            <Tag color={sc.type === 'cron' ? 'blue' : 'purple'}>{sc.type}</Tag>
                          </Space>
                          <Text type="secondary" className="schedule-mobile-prompt">{sc.prompt}</Text>
                        </Space>
                      </div>

                      <div className="schedule-mobile-meta">
                        <div className="schedule-mobile-meta-item">
                          <Text type="secondary">Schedule</Text>
                          <Text>{sc.type === 'cron' ? sc.cronExpr || '—' : fmtDate(sc.runAt)}</Text>
                        </div>
                        <div className="schedule-mobile-meta-item">
                          <Text type="secondary">Last run</Text>
                          <Text>{sc.lastRunAt ? relativeTime(sc.lastRunAt) : '-'}</Text>
                        </div>
                        <div className="schedule-mobile-meta-item">
                          <Text type="secondary">Next run</Text>
                          <Text>{!sc.enabled || !sc.nextRunAt ? '-' : relativeTime(sc.nextRunAt)}</Text>
                        </div>
                      </div>

                      <Space size={6} wrap onClick={(e) => e.stopPropagation()}>
                        <Button size="small" onClick={() => handleSelectSchedule(sc.id)}>History</Button>
                        <Button size="small" icon={<ThunderboltOutlined />} onClick={() => handleTrigger(sc.id)}>Run now</Button>
                        <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(sc)}>Edit</Button>
                        <Switch size="small" checked={sc.enabled} onChange={(enabled) => handleToggle(sc, enabled)} />
                        <Popconfirm title="Delete this schedule?" okText="Delete" okType="danger" onConfirm={() => handleDeleteSchedule(sc.id)}>
                          <Button size="small" danger icon={<DeleteOutlined />} />
                        </Popconfirm>
                      </Space>
                    </div>
                  ))}
                </div>
              ) : (
                <Table
                  size="middle"
                  rowKey="id"
                  columns={scheduleColumns}
                  dataSource={filteredSchedules}
                  pagination={false}
                  rowHoverable
                  className="schedule-table"
                  tableLayout="auto"
                  sticky
                  rowClassName={(record) => record.id === selectedId ? 'schedule-row-selected' : ''}
                  scroll={{ y: 'calc(100vh - 320px)' }}
                />
              )}
            </div>
          </div>
        )}
      </div>
    </>
  )
}
