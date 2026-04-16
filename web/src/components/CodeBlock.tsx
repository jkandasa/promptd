import { App as AntApp, Button, Typography, theme } from 'antd'
import { CheckOutlined, CopyOutlined } from '@ant-design/icons'
import { useState } from 'react'
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter'
import { vscDarkPlus } from 'react-syntax-highlighter/dist/esm/styles/prism'

const { Text } = Typography
const { useToken } = theme

export function CodeBlock({ language, code }: { language?: string; code: string }) {
  const { token } = useToken()
  const { message: antMessage } = AntApp.useApp()
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(code)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      antMessage.error('Failed to copy')
    }
  }

  return (
    <div style={{ position: 'relative', margin: '8px 0', borderRadius: 8, overflow: 'hidden' }}>
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          padding: '6px 12px',
          background: token.colorBgLayout,
          borderBottom: `1px solid ${token.colorBorderSecondary}`,
        }}
      >
        <Text style={{ fontSize: 12, color: token.colorTextSecondary }}>
          {language || 'code'}
        </Text>
        <Button
          type="text"
          size="small"
          aria-label={copied ? 'Copied' : 'Copy code'}
          icon={copied ? <CheckOutlined style={{ color: token.colorSuccess }} /> : <CopyOutlined />}
          onClick={handleCopy}
          style={{ fontSize: 12 }}
        >
          {copied ? 'Copied' : 'Copy'}
        </Button>
      </div>
      <SyntaxHighlighter
        language={language || 'text'}
        style={vscDarkPlus}
        customStyle={{ margin: 0, borderRadius: 0, fontSize: 13 }}
        wrapLongLines
      >
        {code}
      </SyntaxHighlighter>
    </div>
  )
}
