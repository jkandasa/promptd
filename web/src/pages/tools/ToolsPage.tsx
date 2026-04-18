import { Button, Collapse, Empty, Grid, Input, Segmented, Spin, Table, Tag, Tooltip, Typography, theme } from 'antd'
import { CheckCircleFilled, ReloadOutlined, SearchOutlined } from '@ant-design/icons'
import { useMemo, useState } from 'react'
import type { ToolInfo } from '../../types/chat'
import './ToolsPage.scss'

const { Text, Title } = Typography
const { useToken } = theme
const { useBreakpoint } = Grid

const BUILT_IN_TOOL_NAMES = new Set(['get_current_datetime'])

function getParamNames(tool: ToolInfo) {
  if (!tool.parameters?.properties || typeof tool.parameters.properties !== 'object') return []
  return Object.keys(tool.parameters.properties)
}

function getRequiredNames(tool: ToolInfo) {
  return Array.isArray(tool.parameters?.required) ? tool.parameters.required as string[] : []
}

function hasParams(tool: ToolInfo) {
  return getParamNames(tool).length > 0
}

interface ToolsPageProps {
  tools: ToolInfo[]
  loading: boolean
  onRefresh: () => void
}

interface ToolRow {
  key: string
  tool: ToolInfo
  name: string
  description: string
  paramCount: number
  requiredCount: number
  isInbuilt: boolean
}

export function ToolsPage({ tools, loading, onRefresh }: ToolsPageProps) {
  const { token } = useToken()
  const screens = useBreakpoint()
  const [search, setSearch] = useState('')
  const [filterMode, setFilterMode] = useState<'all' | 'configurable' | 'simple'>('all')
  const [sortKey, setSortKey] = useState<'default' | 'name' | 'params' | 'required' | 'inbuilt'>('default')
  const isMobile = !screens.md

  const toolsWithParams = useMemo(() => tools.filter(hasParams).length, [tools])
  const simpleTools = tools.length - toolsWithParams

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    const filteredByMode = tools.filter((tool) => {
      if (filterMode === 'configurable' && !hasParams(tool)) return false
      if (filterMode === 'simple' && hasParams(tool)) return false
      return true
    })

    if (!q) return filteredByMode

    return filteredByMode.filter((tool) => {
      const required = getRequiredNames(tool).join(' ').toLowerCase()
      return tool.name.toLowerCase().includes(q) || tool.description.toLowerCase().includes(q) || required.includes(q)
    })
  }, [filterMode, search, tools])

  const rows = useMemo<ToolRow[]>(() => filtered.map((tool) => {
    const paramNames = getParamNames(tool)
    const requiredNames = getRequiredNames(tool)
    return {
      key: tool.name,
      tool,
      name: tool.name,
      description: tool.description,
      paramCount: paramNames.length,
      requiredCount: requiredNames.length,
      isInbuilt: BUILT_IN_TOOL_NAMES.has(tool.name),
    }
  }), [filtered])

  const sortedRows = useMemo(() => {
    const list = [...rows]
    switch (sortKey) {
      case 'default':
        return list
      case 'params':
        return list.sort((a, b) => b.paramCount - a.paramCount || a.name.localeCompare(b.name))
      case 'required':
        return list.sort((a, b) => b.requiredCount - a.requiredCount || a.name.localeCompare(b.name))
      case 'inbuilt':
        return list.sort((a, b) => Number(b.isInbuilt) - Number(a.isInbuilt) || a.name.localeCompare(b.name))
      case 'name':
      default:
        return list.sort((a, b) => a.name.localeCompare(b.name))
    }
  }, [rows, sortKey])

  return (
    <div className="tools-page">
      <div className="tools-topbar">
        <Title level={3} style={{ margin: 0 }}>Available Tools</Title>
        <Tooltip title="Refresh tools">
          <Button icon={<ReloadOutlined />} onClick={onRefresh} loading={loading} />
        </Tooltip>
      </div>

      <div
        className="tools-panel"
        style={{
          background: token.colorBgContainer,
          border: `1px solid ${token.colorBorderSecondary}`,
          boxShadow: token.boxShadowTertiary,
        }}
      >
        <div className="tools-panel-header">
          <div className="tools-panel-header-copy">
            <Title level={5} style={{ margin: 0 }}>Catalog</Title>
            <Text type="secondary">{rows.length} tool{rows.length === 1 ? '' : 's'} shown</Text>
          </div>
          <div className="tools-panel-controls">
            <Segmented
              value={filterMode}
              onChange={(value) => setFilterMode(value as 'all' | 'configurable' | 'simple')}
              options={[
                { label: `All (${tools.length})`, value: 'all' },
                { label: `Configurable (${toolsWithParams})`, value: 'configurable' },
                { label: `Simple (${simpleTools})`, value: 'simple' },
              ]}
            />
            {isMobile && (
              <Segmented
                value={sortKey}
                onChange={(value) => setSortKey(value as 'name' | 'params' | 'required' | 'inbuilt')}
                options={[
                  { label: 'Default', value: 'default' },
                  { label: 'Name', value: 'name' },
                  { label: 'Params', value: 'params' },
                  { label: 'Required', value: 'required' },
                  { label: 'Built-in', value: 'inbuilt' },
                ]}
              />
            )}
            <Input
              placeholder="Search tools"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              allowClear
              prefix={<SearchOutlined style={{ color: token.colorTextTertiary }} />}
              className="tools-search"
            />
          </div>
        </div>

        {loading ? (
          <div className="tools-state">
            <Spin />
          </div>
        ) : tools.length === 0 ? (
          <div className="tools-state">
            <Empty description="No tools registered" image={Empty.PRESENTED_IMAGE_SIMPLE} />
          </div>
        ) : rows.length === 0 ? (
          <div className="tools-state">
            <Empty description="No matching tools" image={Empty.PRESENTED_IMAGE_SIMPLE}>
              <Button onClick={() => { setSearch(''); setFilterMode('all') }}>Clear filters</Button>
            </Empty>
          </div>
        ) : isMobile ? (
          <div className="tools-mobile-list">
            {sortedRows.map((row) => {
              const paramNames = getParamNames(row.tool)
              const requiredNames = new Set(getRequiredNames(row.tool))
              return (
                <div
                  key={row.key}
                  className="tools-mobile-card"
                  style={{
                    background: token.colorBgElevated,
                    border: `1px solid ${token.colorBorderSecondary}`,
                  }}
                >
                  <div className="tools-mobile-card-head">
                    <div className="tools-name-copy">
                      <Text strong>{row.name}</Text>
                      <Text type="secondary" className="tools-name-description">{row.description}</Text>
                    </div>
                    {row.isInbuilt && <CheckCircleFilled style={{ color: token.colorSuccess, fontSize: 16 }} />}
                  </div>
                  <div className="tools-mobile-meta">
                    {row.paramCount > 0 && <Tag bordered={false}>{row.paramCount} params</Tag>}
                    {row.requiredCount > 0 && <Tag bordered={false} color="red">{row.requiredCount} required</Tag>}
                  </div>
                  {paramNames.length > 0 && (
                    <Collapse
                      ghost
                      size="small"
                      className="tools-mobile-collapse"
                      items={[{
                        key: 'params',
                        label: <Text>Parameters</Text>,
                        children: (
                          <div className="tools-mobile-params">
                            {paramNames.map((name) => {
                              const def = row.tool.parameters?.properties?.[name] as { description?: string } | undefined
                              return (
                                <div key={name} className="tools-mobile-param-row">
                                  <div className="tools-mobile-param-name" style={{ fontFamily: token.fontFamilyCode }}>
                                    <span>{name}</span>
                                    {requiredNames.has(name) && <Tag color="red" style={{ margin: 0 }}>required</Tag>}
                                  </div>
                                  <Text type="secondary">{def?.description || '-'}</Text>
                                </div>
                              )
                            })}
                          </div>
                        ),
                      }]}
                    />
                  )}
                </div>
              )
            })}
          </div>
        ) : (
          <div className="tools-table-wrap">
            <Table
              rowKey="name"
              className="tools-table"
              dataSource={rows}
              pagination={false}
              size="small"
              tableLayout="auto"
              sticky
              scroll={{ y: 'calc(100vh - 320px)' }}
              expandable={{
                rowExpandable: (row: ToolRow) => getParamNames(row.tool).length > 0,
                expandedRowRender: (row: ToolRow) => {
                  const paramNames = getParamNames(row.tool)
                  const requiredNames = new Set(getRequiredNames(row.tool))

                  if (paramNames.length === 0) {
                    return <Text type="secondary">This tool does not require any parameters.</Text>
                  }

                  return (
                    <Table
                      rowKey="name"
                      className="tools-params-table"
                      size="small"
                      pagination={false}
                      tableLayout="auto"
                      dataSource={paramNames.map((name) => {
                        const def = row.tool.parameters?.properties?.[name] as { description?: string } | undefined
                        return {
                          key: name,
                          name,
                          required: requiredNames.has(name),
                          description: def?.description || '-',
                        }
                      })}
                      columns={[
                        {
                          title: 'Name',
                          dataIndex: 'name',
                          width: '34%',
                          render: (name: string, paramRow: { required: boolean }) => (
                            <span className="tools-param-name" style={{ fontFamily: token.fontFamilyCode }}>
                              {name}
                              {paramRow.required && <Tag color="red" style={{ marginInlineStart: 8 }}>required</Tag>}
                            </span>
                          ),
                        },
                        {
                          title: 'Description',
                          dataIndex: 'description',
                          render: (description: string) => <Text type="secondary">{description}</Text>,
                        },
                      ]}
                    />
                  )
                },
              }}
              columns={[
                {
                  title: 'Name',
                  dataIndex: 'name',
                  width: '62%',
                  sorter: (a: ToolRow, b: ToolRow) => a.name.localeCompare(b.name),
                  render: (name: string, row: ToolRow) => (
                    <div className="tools-name-cell">
                      <div className="tools-name-copy">
                        <Text strong>{name}</Text>
                        <Text type="secondary" className="tools-name-description">{row.description}</Text>
                      </div>
                    </div>
                  ),
                },
                {
                  title: 'Parameters',
                  dataIndex: 'paramCount',
                  width: '14%',
                  align: 'center',
                  sorter: (a: ToolRow, b: ToolRow) => a.paramCount - b.paramCount,
                  render: (count: number) => count > 0 ? <Tag bordered={false}>{count}</Tag> : null,
                },
                {
                  title: 'Required',
                  dataIndex: 'requiredCount',
                  width: '14%',
                  align: 'center',
                  sorter: (a: ToolRow, b: ToolRow) => a.requiredCount - b.requiredCount,
                  render: (count: number) => count > 0 ? <Tag bordered={false} color="red">{count}</Tag> : null,
                },
                {
                  title: 'Is Inbuilt',
                  dataIndex: 'isInbuilt',
                  width: '10%',
                  align: 'center',
                  sorter: (a: ToolRow, b: ToolRow) => Number(a.isInbuilt) - Number(b.isInbuilt),
                  render: (value: boolean) => value ? <CheckCircleFilled style={{ color: token.colorSuccess, fontSize: 16 }} /> : null,
                },
              ]}
            />
          </div>
        )}
      </div>
    </div>
  )
}
