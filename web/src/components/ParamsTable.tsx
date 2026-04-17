import { Table, Tag, Typography, theme } from 'antd'

const { Text } = Typography
const { useToken } = theme

export function ParamsTable({ parameters }: { parameters?: any }) {
  const { token } = useToken()
  if (!parameters || typeof parameters !== 'object') return null
  const props = parameters.properties
  if (!props || typeof props !== 'object' || Object.keys(props).length === 0) return null
  const required: string[] = Array.isArray(parameters.required) ? parameters.required : []
  const rows = Object.entries(props).map(([k, v]) => ({
    key: k,
    name: k,
    type: (v as any).type || (Array.isArray((v as any).enum) ? 'enum' : ''),
    desc: (v as any).description || '',
    req: required.includes(k),
  }))
  return (
    <Table
      size="small"
      pagination={false}
      dataSource={rows}
      columns={[
        {
          title: 'Parameter',
          dataIndex: 'name',
          width: 160,
          render: (name: string, row) => (
            <span style={{ fontFamily: token.fontFamilyCode, fontSize: 12 }}>
              {name}
              {row.req && <Tag color="red" style={{ fontSize: 10, marginLeft: 4, padding: '0 4px', lineHeight: '16px' }}>req</Tag>}
            </span>
          ),
        },
        {
          title: 'Type',
          dataIndex: 'type',
          width: 70,
          render: (t: string) => t ? <Tag style={{ fontSize: 10, fontFamily: token.fontFamilyCode }}>{t}</Tag> : null,
        },
        {
          title: 'Description',
          dataIndex: 'desc',
          render: (d: string) => <Text type="secondary" style={{ fontSize: 12 }}>{d}</Text>,
        },
      ]}
      style={{ marginTop: 8 }}
    />
  )
}
