import { Button, Input, Popover, Slider, Tooltip, Typography, theme } from 'antd'
import { SlidersOutlined } from '@ant-design/icons'
import type { LLMParamsOverride } from '../types/chat'

const { Text } = Typography
const { useToken } = theme

export interface LLMParamsPopoverProps {
  params: LLMParamsOverride
  configDefaults: LLMParamsOverride
  onChange: (p: LLMParamsOverride) => void
  disabled?: boolean
}

export function LLMParamsPopover({ params, configDefaults, onChange, disabled }: LLMParamsPopoverProps) {
  const { token } = useToken()
  const hasOverrides = (Object.keys(params) as Array<keyof LLMParamsOverride>).some(
    (k) => params[k] != null && params[k] !== configDefaults[k]
  )

  const row = (label: string, key: keyof LLMParamsOverride, min: number, max: number, step: number, decimals: number) => (
    <div style={{ marginBottom: 14 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
        <Text style={{ fontSize: 12, fontWeight: 500 }}>{label}</Text>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <Input
            size="small"
            value={params[key] ?? ''}
            onChange={(e) => {
              const v = e.target.value
              if (v === '') { const next = { ...params }; delete next[key]; onChange(next); return }
              const n = parseFloat(v)
              if (!isNaN(n)) onChange({ ...params, [key]: n })
            }}
            style={{ width: 60, fontSize: 12, textAlign: 'right' }}
          />
          {params[key] != null && (
            <Button
              type="text" size="small"
              onClick={() => { const next = { ...params }; delete next[key]; onChange(next) }}
              style={{ fontSize: 11, color: token.colorTextTertiary, padding: '0 4px', height: 22 }}
            >reset</Button>
          )}
        </div>
      </div>
      <Slider
        min={min} max={max} step={step}
        value={params[key] as number ?? undefined}
        onChange={(v) => onChange({ ...params, [key]: v })}
        tooltip={{ formatter: (v) => v?.toFixed(decimals) }}
        style={{ margin: '0 4px' }}
      />
    </div>
  )

  const content = (
    <div style={{ width: 280, padding: '4px 0' }}>
      <Text type="secondary" style={{ fontSize: 11, display: 'block', marginBottom: 12 }}>
        Overrides config defaults for this session. Leave blank to use config value.
      </Text>
      {row('Temperature', 'temperature', 0, 2, 0.01, 2)}
      {row('Top P', 'top_p', 0, 1, 0.01, 2)}
      <div style={{ marginBottom: 14 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
          <Text style={{ fontSize: 12, fontWeight: 500 }}>Top K</Text>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <Input
              size="small"
              value={params.top_k ?? ''}
              onChange={(e) => {
                const v = e.target.value
                if (v === '') { const next = { ...params }; delete next.top_k; onChange(next); return }
                const n = parseInt(v)
                if (!isNaN(n) && n >= 0) onChange({ ...params, top_k: n })
              }}
              style={{ width: 60, fontSize: 12, textAlign: 'right' }}
            />
            {params.top_k != null && (
              <Button type="text" size="small"
                onClick={() => { const next = { ...params }; delete next.top_k; onChange(next) }}
                style={{ fontSize: 11, color: token.colorTextTertiary, padding: '0 4px', height: 22 }}
              >reset</Button>
            )}
          </div>
        </div>
        <Slider min={0} max={100} step={1}
          value={params.top_k != null ? Math.min(params.top_k, 100) : undefined}
          onChange={(v) => onChange({ ...params, top_k: v })}
          tooltip={{ formatter: (v) => v?.toString() }}
          style={{ margin: '0 4px' }}
        />
      </div>
      <div style={{ marginBottom: 14 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
          <Text style={{ fontSize: 12, fontWeight: 500 }}>Max Tokens</Text>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <Input
              size="small"
              value={params.max_tokens ?? ''}
              onChange={(e) => {
                const v = e.target.value
                if (v === '') { const next = { ...params }; delete next.max_tokens; onChange(next); return }
                const n = parseInt(v)
                if (!isNaN(n)) onChange({ ...params, max_tokens: n })
              }}
              style={{ width: 60, fontSize: 12, textAlign: 'right' }}
            />
            {params.max_tokens != null && (
              <Button type="text" size="small"
                onClick={() => { const next = { ...params }; delete next.max_tokens; onChange(next) }}
                style={{ fontSize: 11, color: token.colorTextTertiary, padding: '0 4px', height: 22 }}
              >reset</Button>
            )}
          </div>
        </div>
        <Slider min={256} max={32768} step={256}
          value={params.max_tokens ?? undefined}
          onChange={(v) => onChange({ ...params, max_tokens: v })}
          tooltip={{ formatter: (v) => v?.toString() }}
          style={{ margin: '0 4px' }}
        />
      </div>
      {hasOverrides && (
        <Button size="small" block onClick={() => onChange(configDefaults)}
          style={{ marginTop: 4, fontSize: 12 }}>
          Reset all to config defaults
        </Button>
      )}
    </div>
  )

  return (
    <Popover
      content={content}
      title={<span style={{ fontSize: 13 }}>LLM Parameters</span>}
      trigger="click"
      placement="topLeft"
      arrow={false}
    >
      <Tooltip title="LLM parameters">
        <Button
          type="text"
          size="small"
          icon={<SlidersOutlined />}
          disabled={disabled}
          style={{
            height: 28, width: 28, padding: 0, flexShrink: 0,
            color: hasOverrides ? token.colorPrimary : token.colorTextSecondary,
          }}
          aria-label="LLM parameters"
        />
      </Tooltip>
    </Popover>
  )
}
