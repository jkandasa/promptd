import { App as AntApp, ConfigProvider, theme } from 'antd'
import { useState } from 'react'
import { PromptdApp } from './pages'

export default function App() {
  const [isDark, setIsDark] = useState(
    () => typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches
  )

  return (
    <ConfigProvider
      theme={{
        algorithm: isDark ? theme.darkAlgorithm : theme.defaultAlgorithm,
        token: {
          colorPrimary: '#5b21b6',
          borderRadius: 8,
          fontFamily: "'Open Sans', system-ui, sans-serif",
          fontFamilyCode: "ui-monospace, Menlo, 'Courier New', monospace",
        },
      }}
    >
      <AntApp>
        <PromptdApp isDark={isDark} onToggleDark={() => setIsDark(!isDark)} />
      </AntApp>
    </ConfigProvider>
  )
}
