import { Button, Popover, Slider, Tooltip, Typography, theme } from 'antd'
import { InfoCircleOutlined, SlidersOutlined } from '@ant-design/icons'
import { useState } from 'react'
import type { LLMParamsOverride } from '../types/chat'

const { Text } = Typography
const { useToken } = theme

export interface LLMParamsPopoverProps {
  params: LLMParamsOverride
  configDefaults: LLMParamsOverride
  onChange: (p: LLMParamsOverride) => void
  disabled?: boolean
}

const PARAM_DESCRIPTIONS: Record<keyof LLMParamsOverride, string> = {
  temperature: 'Controls randomness. 0 = deterministic, 2 = very creative. Avoid setting both temperature and top_p.',
  top_p:       'Nucleus sampling threshold. Only tokens comprising the top P probability mass are considered. Avoid using alongside temperature.',
  top_k:       'Restricts sampling to the top K most likely tokens. Provider-specific — some models ignore this.',
  max_tokens:  'Maximum number of tokens the model may generate in this response.',
}

interface RowProps {
  label: string
  paramKey: keyof LLMParamsOverride
  min: number
  max: number
  step: number
  decimals: number
  params: LLMParamsOverride
  configDefaults: LLMParamsOverride
  onChange: (p: LLMParamsOverride) => void
}

function ParamRow({ label, paramKey, min, max, step, decimals, params, configDefaults, onChange }: RowProps) {
  const { token } = useToken()
  const [inputStr, setInputStr] = useState<string | null>(null)

  const current  = params[paramKey]
  const defVal   = configDefaults[paramKey]
  const isOverride = current != null && current !== defVal
  const sliderVal  = current ?? defVal   // show config default position when not set

  const defHint = defVal != null
    ? `config: ${defVal}`
    : 'provider default'

  const handleInputChange = (raw: string) => {
    setInputStr(raw)
    if (raw === '') {
      const next = { ...params }; delete next[paramKey]; onChange(next)
      return
    }
    const n = decimals > 0 ? parseFloat(raw) : parseInt(raw)
    if (!isNaN(n)) onChange({ ...params, [paramKey]: n })
  }

  const handleInputBlur = () => setInputStr(null)

  const displayVal = inputStr !== null
    ? inputStr
    : current != null
      ? (decimals > 0 ? current.toFixed(decimals) : String(current))
      : ''

  const handleReset = () => {
    setInputStr(null)
    const next = { ...params }
    delete next[paramKey]
    onChange(next)
  }

  return (
    <div style={{ marginBottom: 16 }}>
      {/* Label row */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          <Text style={{ fontSize: 12, fontWeight: 500 }}>{label}</Text>
          <Tooltip title={PARAM_DESCRIPTIONS[paramKey]} placement="right">
            <InfoCircleOutlined style={{ fontSize: 10, color: token.colorTextTertiary, cursor: 'default' }} />
          </Tooltip>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          <input
            value={displayVal}
            onChange={e => handleInputChange(e.target.value)}
            onBlur={handleInputBlur}
            placeholder={defVal != null ? String(defVal) : '—'}
            style={{
              width: 56,
              fontSize: 12,
              textAlign: 'right',
              background: 'transparent',
              border: `1px solid ${isOverride ? token.colorPrimary : token.colorBorderSecondary}`,
              borderRadius: 4,
              padding: '1px 6px',
              color: isOverride ? token.colorPrimary : token.colorText,
              outline: 'none',
              fontFamily: token.fontFamilyCode,
            }}
          />
          {isOverride && (
            <Tooltip title={defVal != null ? `Reset to config default (${defVal})` : 'Clear override'}>
              <Button
                type="text"
                size="small"
                onClick={handleReset}
                style={{
                  fontSize: 11,
                  color: token.colorTextTertiary,
                  padding: '0 4px',
                  height: 20,
                  lineHeight: 1,
                }}
              >
                ↺{defVal != null ? ` ${defVal}` : ''}
              </Button>
            </Tooltip>
          )}
        </div>
      </div>

      {/* Slider */}
      <Slider
        min={min}
        max={max}
        step={step}
        value={sliderVal as number | undefined}
        onChange={v => { setInputStr(null); onChange({ ...params, [paramKey]: v }) }}
        tooltip={{ formatter: v => v != null ? v.toFixed(decimals) : '—' }}
        styles={{
          track: { background: isOverride ? token.colorPrimary : token.colorFillSecondary },
          handle: { borderColor: isOverride ? token.colorPrimary : token.colorTextSecondary },
        }}
        style={{ margin: '2px 4px 0' }}
      />

      {/* Config hint */}
      <Text type="secondary" style={{ fontSize: 10, marginLeft: 4 }}>{defHint}</Text>
    </div>
  )
}

export function LLMParamsPopover({ params, configDefaults, onChange, disabled }: LLMParamsPopoverProps) {
  const { token } = useToken()

  const overrideCount = (Object.keys(params) as Array<keyof LLMParamsOverride>).filter(
    k => params[k] != null && params[k] !== configDefaults[k]
  ).length

  const sharedProps = { params, configDefaults, onChange }

  const content = (
    <div style={{ width: 296, padding: '4px 0' }}>
      <Text type="secondary" style={{ fontSize: 11, display: 'block', marginBottom: 14 }}>
        Override config defaults for this session. Leave blank to use config value.
      </Text>

      <ParamRow label="Temperature" paramKey="temperature" min={0} max={2}      step={0.01} decimals={2} {...sharedProps} />
      <ParamRow label="Top P"       paramKey="top_p"       min={0} max={1}      step={0.01} decimals={2} {...sharedProps} />
      <ParamRow label="Top K"       paramKey="top_k"       min={0} max={100}    step={1}    decimals={0} {...sharedProps} />
      <ParamRow label="Max Tokens"  paramKey="max_tokens"  min={256} max={128000} step={256} decimals={0} {...sharedProps} />

      {overrideCount > 0 && (
        <Button
          size="small"
          block
          onClick={() => onChange({})}
          style={{ marginTop: 4, fontSize: 12 }}
        >
          Reset all {overrideCount} override{overrideCount !== 1 ? 's' : ''} to config defaults
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
      <Tooltip title={overrideCount > 0 ? `${overrideCount} param override${overrideCount !== 1 ? 's' : ''} active` : 'LLM parameters'}>
        <Button
          type="text"
          size="small"
          icon={<SlidersOutlined />}
          disabled={disabled}
          style={{
            height: 28,
            width: 28,
            padding: 0,
            flexShrink: 0,
            color: overrideCount > 0 ? token.colorPrimary : token.colorTextSecondary,
          }}
          aria-label="LLM parameters"
        />
      </Tooltip>
    </Popover>
  )
}
