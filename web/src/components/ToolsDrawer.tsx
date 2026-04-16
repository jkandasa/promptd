import { Badge, Button, Collapse, Drawer, Empty, Input, Spin, Tag, Tooltip, Typography, theme } from 'antd'
import { ReloadOutlined, ToolOutlined } from '@ant-design/icons'
import { useState } from 'react'
import type { ToolInfo } from '../types/chat'
import { ParamsTable } from './ParamsTable'

const { Text } = Typography
const { useToken } = theme

export function ToolsDrawer({
  open,
  onClose,
  tools,
  loading,
  onRefresh,
}: {
  open: boolean
  onClose: () => void
  tools: ToolInfo[]
  loading: boolean
  onRefresh: () => void
}) {
  const { token } = useToken()
  const [search, setSearch] = useState('')
  const q = search.trim().toLowerCase()
  const filtered = q
    ? tools.filter(t => t.name.toLowerCase().includes(q) || t.description.toLowerCase().includes(q))
    : tools

  const hasParams = (t: ToolInfo) =>
    t.parameters?.properties && Object.keys(t.parameters.properties).length > 0

  return (
    <Drawer
      title={
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <ToolOutlined style={{ color: token.colorPrimary }} />
          <span>Active Tools</span>
          <Badge count={tools.length} style={{ marginLeft: 4 }} />
        </div>
      }
      placement="right"
      size="large"
      open={open}
      onClose={onClose}
      extra={
        <Tooltip title="Refresh">
          <Button
            icon={<ReloadOutlined />}
            type="text"
            onClick={onRefresh}
            loading={loading}
            size="small"
            aria-label="Refresh tools"
          />
        </Tooltip>
      }
      styles={{ body: { display: 'flex', flexDirection: 'column', padding: '16px 20px' } }}
    >
      <Input.Search
        placeholder="Search tools…"
        value={search}
        onChange={e => setSearch(e.target.value)}
        allowClear
        size="small"
        style={{ marginBottom: 12, flexShrink: 0 }}
      />

      {loading ? (
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 40 }}>
          <Spin />
        </div>
      ) : tools.length === 0 ? (
        <Empty description="No tools registered" image={Empty.PRESENTED_IMAGE_SIMPLE} style={{ paddingTop: 40 }} />
      ) : filtered.length === 0 ? (
        <Empty description="No matching tools" image={Empty.PRESENTED_IMAGE_SIMPLE} style={{ paddingTop: 40 }} />
      ) : (
        <div style={{ overflowY: 'auto', flex: 1 }}>
          {filtered.map((t, i) => (
            <div
              key={t.name}
              style={{
                border: `1px solid ${token.colorBorderSecondary}`,
                borderRadius: 8,
                padding: '10px 14px',
                marginBottom: i < filtered.length - 1 ? 8 : 0,
                background: token.colorBgContainer,
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
                <Tag color="blue" style={{ fontFamily: 'ui-monospace, monospace', fontSize: 12, margin: 0 }}>
                  {t.name}
                </Tag>
                {hasParams(t) && (
                  <Text type="secondary" style={{ fontSize: 11 }}>
                    {Object.keys(t.parameters.properties).length} param{Object.keys(t.parameters.properties).length === 1 ? '' : 's'}
                  </Text>
                )}
              </div>
              <Text type="secondary" style={{ fontSize: 13, lineHeight: 1.5, display: 'block' }}>
                {t.description}
              </Text>
              {hasParams(t) && (
                <Collapse
                  size="small"
                  ghost
                  style={{ marginTop: 6 }}
                  items={[{
                    key: 'params',
                    label: <Text style={{ fontSize: 12 }}>Parameters</Text>,
                    children: <ParamsTable parameters={t.parameters} />,
                  }]}
                />
              )}
            </div>
          ))}
        </div>
      )}
    </Drawer>
  )
}
