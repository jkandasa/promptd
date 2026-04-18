import './ScheduleForm.scss'

import {
  Button,
  DatePicker,
  Form,
  Input,
  InputNumber,
  Radio,
  Select,
  Space,
  Switch,
  Tag,
  Typography,
  theme,
} from 'antd'
import React, { useMemo } from 'react'
import type { Schedule, ScheduleType } from '../../types/scheduler'
import type { ToolInfo, UIConfig } from '../../types/chat'

import type { ModelInfo } from '../../api/client'
import { apiGetModels } from '../../api/client'
import dayjs from 'dayjs'

const { Text } = Typography
const { TextArea } = Input
const { useToken } = theme

const CRON_PRESETS = [
  { label: 'Every min',    value: '0 * * * * *' },
  { label: '5 min',        value: '0 */5 * * * *' },
  { label: '15 min',       value: '0 */15 * * * *' },
  { label: '30 min',       value: '0 */30 * * * *' },
  { label: '1 hour',       value: '0 0 * * * *' },
  { label: 'Daily 00:00',  value: '0 0 0 * * *' },
  { label: 'Daily 08:00',  value: '0 0 8 * * *' },
  { label: 'Weekly (Sun)', value: '0 0 0 * * 0' },
  { label: 'Monthly',      value: '0 0 0 1 * *' },
]

const RETAIN_PRESETS = [
  { label: 'All', value: 0 },
  { label: '5',   value: 5 },
  { label: '10',  value: 10 },
  { label: '20',  value: 20 },
  { label: '50',  value: 50 },
]

// ── Custom controlled inputs ─────────────────────────────────────────────────

function CronInput({ value, onChange }: { value?: string; onChange?: (v: string) => void }) {
  const { token } = useToken()
  return (
    <Space direction="vertical" style={{ width: '100%' }} size={8}>
      <Input
        value={value ?? ''}
        onChange={e => onChange?.(e.target.value)}
        placeholder="0 0 * * * *"
        style={{ fontFamily: token.fontFamilyCode, fontSize: 13 }}
      />
      <Space wrap size={4}>
        {CRON_PRESETS.map(p => (
          <Tag
            key={p.value}
            color={value === p.value ? 'blue' : undefined}
            style={{ cursor: 'pointer', userSelect: 'none', fontSize: 11 }}
            onClick={() => onChange?.(p.value)}
          >
            {p.label}
          </Tag>
        ))}
      </Space>
    </Space>
  )
}

function RetainInput({ value, onChange }: { value?: number; onChange?: (v: number | null) => void }) {
  return (
    <Space direction="vertical" size={8} style={{ width: '100%' }}>
      <Space size={8} align="center">
        <InputNumber min={0} max={1000} value={value} onChange={onChange} style={{ width: 110 }} />
        <Text type="secondary" style={{ fontSize: 12 }}>
          {value === 0 ? 'Keep all executions' : `Keep last ${value}`}
        </Text>
      </Space>
      <Space size={4}>
        {RETAIN_PRESETS.map(p => (
          <Tag
            key={p.value}
            color={value === p.value ? 'blue' : undefined}
            style={{ cursor: 'pointer', userSelect: 'none', fontSize: 11 }}
            onClick={() => onChange?.(p.value)}
          >
            {p.label}
          </Tag>
        ))}
      </Space>
    </Space>
  )
}

// ── Props ────────────────────────────────────────────────────────────────────

interface Props {
  open: boolean
  initial?: Partial<Schedule>
  models: ModelInfo[]
  tools: ToolInfo[]
  uiConfig: UIConfig
  onSubmit: (values: Partial<Schedule>) => Promise<void>
  onClose: () => void
}

export function ScheduleForm({ open, initial, models, tools, uiConfig, onSubmit, onClose }: Props) {
  const [form] = Form.useForm()
  const { token } = useToken()
  const [submitting, setSubmitting]   = React.useState(false)
  const [providerFilter, setProviderFilter] = React.useState<string>('')
  const [providerModels, setProviderModels] = React.useState<ModelInfo[]>([])
  const [loadingProviderModels, setLoadingProviderModels] = React.useState(false)
  const schedType: ScheduleType       = Form.useWatch('type', form) ?? 'cron'

  const providerNames = useMemo(() =>
    [...new Set(models.map(m => m.provider).filter((p): p is string => Boolean(p)))],
    [models]
  )
  const isMultiProvider = providerNames.length > 1

  React.useEffect(() => {
    const selectedModel = form.getFieldValue('modelId') as string | undefined
    if (!selectedModel) return
    if (providerFilter && providerModels.some((m) => m.id === selectedModel)) return
    form.setFieldValue('modelId', '')
  }, [providerFilter, providerModels, form])

  React.useEffect(() => {
    if (!open || !providerFilter) {
      setProviderModels([])
      setLoadingProviderModels(false)
      return
    }

    let cancelled = false
    setLoadingProviderModels(true)
    void apiGetModels(providerFilter).then((data) => {
      if (cancelled) return
      const tagged = data.models.map((m) => ({ ...m, source: (m.source ?? data.source ?? 'static') as 'static' | 'discovered' }))
      setProviderModels(tagged)
    }).catch(() => {
      if (cancelled) return
      setProviderModels([])
    }).finally(() => {
      if (!cancelled) setLoadingProviderModels(false)
    })

    return () => { cancelled = true }
  }, [open, providerFilter])

  React.useEffect(() => {
    if (open) {
      setProviderFilter(initial?.provider ?? '')
      form.setFieldsValue({
        name:          initial?.name ?? '',
        prompt:        initial?.prompt ?? '',
        type:          initial?.type ?? 'cron',
        cronExpr:      initial?.cronExpr ?? '0 0 * * * *',
        runAt:         initial?.runAt ? dayjs(initial.runAt) : null,
         modelId:       initial?.provider ? initial?.modelId ?? '' : '',
        systemPrompt:  initial?.systemPrompt ?? undefined,
        allowedTools:  initial?.allowedTools ?? undefined,
        params:        initial?.params ?? {},
        traceEnabled:  initial?.traceEnabled == null ? 'default' : initial.traceEnabled ? 'on' : 'off',
        retainHistory: initial?.retainHistory ?? 10,
        enabled:       initial?.enabled ?? true,
      })
    }
  }, [open, initial, form])

  const handleOk = async () => {
    try {
      const values = await form.validateFields()
      setSubmitting(true)
      const p = values.params ?? {}
      const hasParams = p.temperature != null || p.max_tokens != null || p.top_p != null || p.top_k != null
      const payload: Partial<Schedule> = {
        name:          values.name,
        prompt:        values.prompt,
        type:          values.type,
        enabled:       values.enabled,
        retainHistory: values.retainHistory ?? 0,
        modelId:       values.modelId || undefined,
        provider:      providerFilter || undefined,
        systemPrompt:  values.systemPrompt || undefined,
        allowedTools:  values.allowedTools?.length ? values.allowedTools : null,
        params:        hasParams ? p : null,
        traceEnabled:  values.traceEnabled === 'on' ? true : values.traceEnabled === 'off' ? false : null,
      }
      if (values.type === 'cron') {
        payload.cronExpr = values.cronExpr
      } else {
        payload.runAt = values.runAt ? (values.runAt as dayjs.Dayjs).toISOString() : undefined
      }
      await onSubmit(payload)
      form.resetFields()
    } catch {
    } finally {
      setSubmitting(false)
    }
  }

  const handleClose = () => {
    form.resetFields()
    onClose()
  }

  const systemPrompts = uiConfig.systemPrompts ?? []

  return (
    open ? (
      <div className="schedule-form-panel">
        <Form form={form} layout="vertical" size="middle" className="schedule-form-shell">
          <div className="form-scroll">
            <div className="form-section-card">
              <div className="form-section">
                <Text strong className="section-title">Schedule</Text>
                <div className="top-controls-row">
                  <Form.Item name="enabled" label="Enabled" valuePropName="checked" style={{ marginBottom: 0 }}>
                    <Switch />
                  </Form.Item>
                </div>

              <Form.Item
                name="name"
                label="Name"
                rules={[{ required: true, message: 'Name is required' }]}
              >
                <Input placeholder="Daily summary" />
              </Form.Item>

              <Form.Item
                name="prompt"
                label="Prompt"
                rules={[{ required: true, message: 'Prompt is required' }]}
                extra="Sent to the model as the user message on every execution."
              >
                <TextArea
                  placeholder="Write a concise summary of today's key events…"
                  autoSize={{ minRows: 4, maxRows: 8 }}
                />
              </Form.Item>

              <Form.Item name="type" label="Repeat">
                <Radio.Group>
                  <Radio value="cron">Recurring (cron)</Radio>
                  <Radio value="once">One-time</Radio>
                </Radio.Group>
              </Form.Item>

              {schedType === 'cron' ? (
                <Form.Item
                  name="cronExpr"
                  label="Cron expression"
                  rules={[{ required: true, message: 'Cron expression is required' }]}
                  extra={
                    <Text type="secondary" style={{ fontSize: 11 }}>
                      6-field: <code style={{ fontFamily: token.fontFamilyCode, fontSize: 11 }}>seconds minutes hours day month weekday</code>
                    </Text>
                  }
                >
                  <CronInput />
                </Form.Item>
              ) : (
                <Form.Item
                  name="runAt"
                  label="Run at"
                  rules={[{ required: true, message: 'Date and time is required' }]}
                >
                  <DatePicker
                    showTime
                    style={{ width: '100%' }}
                    format="YYYY-MM-DD HH:mm:ss"
                    disabledDate={d => d && d.isBefore(dayjs(), 'day')}
                  />
                </Form.Item>
              )}

              <div className="two-col">
                <Form.Item
                  name="retainHistory"
                  label="Keep last N executions"
                  extra="0 = keep all"
                >
                  <RetainInput />
                </Form.Item>

                <Form.Item
                  name="traceEnabled"
                  label="LLM trace"
                  extra={<Text type="secondary" style={{ fontSize: 11 }}>Default follows global config</Text>}
                >
                  <Radio.Group optionType="button" buttonStyle="solid" size="small">
                    <Radio.Button value="default">Default</Radio.Button>
                    <Radio.Button value="on">On</Radio.Button>
                    <Radio.Button value="off">Off</Radio.Button>
                  </Radio.Group>
                </Form.Item>
              </div>
            </div>
          </div>

          <div className="form-section-card">
            <div className="form-section">
              <Text strong className="section-title">Model</Text>
              <div className="two-col">
                {isMultiProvider ? (
                  <Form.Item label="Provider" extra="Auto = server picks provider based on selection method">
                    <Select
                      value={providerFilter}
                      onChange={(v: string) => {
                        setProviderFilter(v)
                        form.setFieldValue('modelId', '')
                      }}
                      showSearch={{ filterOption: (input, opt) => {
                        if (!input) return true
                        const q = input.toLowerCase()
                        return String(opt?.label ?? '').toLowerCase().includes(q) || String(opt?.value ?? '').toLowerCase().includes(q)
                      } }}
                      placeholder="Auto"
                      options={[
                        { label: 'Auto', value: '' },
                        ...providerNames.map(p => ({ label: p, value: p })),
                      ]}
                    />
                  </Form.Item>
                ) : <div />}

                <Form.Item name="modelId" label="Model" extra={providerFilter ? 'Choose a model for the selected provider' : 'Auto provider keeps model on Auto'}>
                  <Select
                    key={`schedule-model-${providerFilter || 'auto'}`}
                    showSearch={{ filterOption: (input, opt) =>
                      !input ||
                      String(opt?.label ?? '').toLowerCase().includes(input.toLowerCase()) ||
                      String(opt?.value ?? '').toLowerCase().includes(input.toLowerCase())
                    }}
                    placeholder="Auto"
                    disabled={!providerFilter || loadingProviderModels}
                    options={[
                      { value: '', label: 'Auto' },
                      ...[...providerModels]
                        .sort((a, b) => (a.name || a.id).localeCompare(b.name || b.id))
                        .map(m => ({ value: m.id, label: m.name || m.id, provider: m.provider })),
                    ]}
                    optionRender={opt => {
                      const { provider } = opt.data as { provider?: string }
                      const providerName = provider
                      const subtitle = isMultiProvider && !providerFilter && providerName
                        ? `${providerName} · ${opt.value as string}`
                        : String(opt.value) !== String(opt.label) ? opt.value as string : ''
                      return (
                        <Space direction="vertical" size={0}>
                          <Text style={{ fontSize: 13, fontWeight: 500 }}>{opt.label as string}</Text>
                          {subtitle && <Text type="secondary" style={{ fontSize: 11 }}>{subtitle}</Text>}
                        </Space>
                      )
                    }}
                  />
                </Form.Item>
              </div>

              <div className="two-col">
                {systemPrompts.length > 0 ? (
                  <Form.Item name="systemPrompt" label="System prompt" extra="Blank = default">
                    <Select
                      allowClear
                      showSearch={{ filterOption: (input, opt) =>
                        !input || String(opt?.label ?? '').toLowerCase().includes(input.toLowerCase())
                      }}
                      placeholder="Default prompt"
                      options={[...systemPrompts]
                        .sort((a, b) => a.name.localeCompare(b.name))
                        .map(p => ({ value: p.name, label: p.name }))}
                    />
                  </Form.Item>
                ) : <div />}

                {tools.length > 0 ? (
                  <Form.Item
                    name="allowedTools"
                    label="Allowed tools"
                    extra="Leave empty to allow all tools."
                  >
                    <Select
                      mode="multiple"
                      allowClear
                      showSearch={{ filterOption: (input, opt) =>
                        !input || String(opt?.label ?? '').toLowerCase().includes(input.toLowerCase())
                      }}
                      placeholder="All tools"
                      options={[...tools]
                        .sort((a, b) => a.name.localeCompare(b.name))
                        .map(t => ({ value: t.name, label: t.name }))}
                      optionRender={opt => {
                        const tool = tools.find(t => t.name === opt.value)
                        return (
                          <Space direction="vertical" size={0}>
                            <Text style={{ fontFamily: token.fontFamilyCode, fontSize: 12 }}>{opt.label as string}</Text>
                            {tool?.description && (
                              <Text type="secondary" style={{ fontSize: 11 }}>{tool.description}</Text>
                            )}
                          </Space>
                        )
                      }}
                    />
                  </Form.Item>
                ) : <div />}
              </div>

              <Text type="secondary" className="params-hint">
                LLM parameters — leave blank to use model or global defaults.
              </Text>

              <div className="four-col">
                <Form.Item
                  name={['params', 'temperature']}
                  label="Temperature"
                  extra={<Text type="secondary" style={{ fontSize: 11 }}>0 = deterministic · 2 = very random</Text>}
                >
                  <InputNumber min={0} max={2} step={0.1} precision={2} placeholder="default" style={{ width: '100%' }} />
                </Form.Item>

                <Form.Item
                  name={['params', 'max_tokens']}
                  label="Max tokens"
                  extra={<Text type="secondary" style={{ fontSize: 11 }}>Maximum output tokens</Text>}
                >
                  <InputNumber min={1} step={256} placeholder="default" style={{ width: '100%' }} />
                </Form.Item>

                <Form.Item
                  name={['params', 'top_p']}
                  label="Top P"
                  extra={<Text type="secondary" style={{ fontSize: 11 }}>Nucleus sampling (0–1)</Text>}
                >
                  <InputNumber min={0} max={1} step={0.05} precision={2} placeholder="default" style={{ width: '100%' }} />
                </Form.Item>

                <Form.Item
                  name={['params', 'top_k']}
                  label="Top K"
                  extra={<Text type="secondary" style={{ fontSize: 11 }}>Provider-specific</Text>}
                >
                  <InputNumber min={1} step={10} placeholder="default" style={{ width: '100%' }} />
                </Form.Item>
              </div>
            </div>
          </div>

          </div>
          <div className="schedule-form-footer">
            <Button onClick={handleClose}>Cancel</Button>
            <Button type="primary" onClick={() => { void handleOk() }} loading={submitting}>
              {initial?.id ? 'Save changes' : 'Create schedule'}
            </Button>
          </div>
        </Form>
      </div>
    ) : null
  )
}
