import {
  App as AntApp,
  Avatar,
  Badge,
  Button,
  Layout,
  Tooltip,
  Typography,
  theme,
} from 'antd'
import {
  CalendarOutlined,
  GithubOutlined,
  MenuFoldOutlined,
  MenuUnfoldOutlined,
  MessageOutlined,
  MoonOutlined,
  RobotOutlined,
  SunOutlined,
  ToolOutlined,
} from '@ant-design/icons'
import { apiGetModels, apiGetUIConfig, apiListTools } from '../api/client'
import type { ModelData, ModelInfo, ProviderInfo } from '../api/client'
import type { ToolInfo, UIConfig } from '../types/chat'
import { isImageIcon } from '../utils/helpers'
import { useCallback, useEffect, useState } from 'react'

import { ChatPage } from './chat/ChatPage'
import { SchedulerPage } from './scheduler/SchedulerPage'
import { ToolsDrawer } from '../components/ToolsDrawer'
import './index.scss'

const { Text } = Typography
const { useToken } = theme

interface PromptdAppProps {
  isDark: boolean
  onToggleDark: () => void
}

export function PromptdApp({ isDark, onToggleDark }: PromptdAppProps) {
  const { token } = useToken()
  const { message: antMessage } = AntApp.useApp()

  const [view, setView] = useState<'chat' | 'scheduler'>('chat')
  const [siderCollapsed, setSiderCollapsed] = useState(false)

  const [models, setModels] = useState<ModelInfo[]>([])
  const [modelData, setModelData] = useState<{ source?: string; count: number; updated_at?: string; refresh_interval?: string; global_params?: ModelData['global_params']; providers?: ProviderInfo[] }>({ count: 0 })
  const [uiConfig, setUIConfig] = useState<UIConfig>({})

  const [toolsOpen, setToolsOpen] = useState(false)
  const [tools, setTools] = useState<ToolInfo[]>([])
  const [toolsLoading, setToolsLoading] = useState(false)

  const appName = uiConfig.appName || 'Chatbot'
  const appIcon = uiConfig.appIcon

  useEffect(() => {
    let cancelled = false
    apiGetUIConfig().then((cfg) => {
      if (cancelled) return
      setUIConfig(cfg)
    }).catch(() => {})
    apiGetModels().then((data) => {
      if (cancelled) return
      const tagged = data.models.map((m) => ({ ...m, source: (data.source ?? 'static') as 'static' | 'discovered' }))
      setModels(tagged)
      setModelData({ source: data.source, count: data.count, updated_at: data.updated_at, refresh_interval: data.refresh_interval, global_params: data.global_params, providers: data.providers })
    }).catch(() => {})
    apiListTools().then((list) => {
      if (cancelled) return
      setTools(list)
    }).catch(() => {})
    return () => { cancelled = true }
  }, [])

  useEffect(() => {
    document.title = appName
    if (!isImageIcon(appIcon)) return
    const link = document.querySelector("link[rel='icon']") || document.createElement('link')
    link.setAttribute('rel', 'icon')
    link.setAttribute('href', appIcon || '')
    if (!link.parentNode) document.head.appendChild(link)
  }, [appIcon, appName])

  const fetchTools = useCallback(async () => {
    setToolsLoading(true)
    try {
      const list = await apiListTools()
      setTools(list)
    } catch {
      antMessage.error('Could not load tools')
    } finally {
      setToolsLoading(false)
    }
  }, [antMessage])

  const handleOpenTools = useCallback(() => {
    setToolsOpen(true)
    fetchTools()
  }, [fetchTools])

  const handleRefreshModels = useCallback(async (provider?: string) => {
    const data = await apiGetModels(provider, true)
    const tagged = data.models.map((m) => ({ ...m, source: (data.source ?? 'static') as 'static' | 'discovered' }))
    if (!provider) {
      setModels(tagged)
    }
    setModelData({ source: data.source, count: data.count, updated_at: data.updated_at, refresh_interval: data.refresh_interval, global_params: data.global_params, providers: data.providers })
  }, [])

  return (
    <Layout className="app-root" style={{ background: token.colorBgLayout }}>
      {/* ── Nav Rail ── */}
      <div
        className="nav-rail"
        style={{
          background: token.colorBgContainer,
          borderRight: `1px solid ${token.colorBorderSecondary}`,
        }}
      >
        {/* Spacer matching the 56px header so buttons sit below it */}
        <div className="nav-spacer" style={{ borderBottom: `1px solid ${token.colorBorderSecondary}` }} />
        <div className="nav-buttons">
          <Tooltip title="Chat" placement="right">
            <Button
              type={view === 'chat' ? 'primary' : 'text'}
              icon={<MessageOutlined />}
              onClick={() => setView('chat')}
              aria-label="Chat"
              className="nav-btn"
            />
          </Tooltip>
          <Tooltip title="Scheduler" placement="right">
            <Button
              type={view === 'scheduler' ? 'primary' : 'text'}
              icon={<CalendarOutlined />}
              onClick={() => setView('scheduler')}
              aria-label="Scheduler"
              className="nav-btn"
            />
          </Tooltip>
        </div>
      </div>

      {/* ── Main area ── */}
      <Layout className="main-col">
        {/* ── Header ── */}
        <div
          className="header"
          style={{
            background: token.colorBgContainer,
            borderBottom: `1px solid ${token.colorBorderSecondary}`,
            boxShadow: token.boxShadow,
          }}
        >
          <div className="header-left">
            {view === 'chat' && (
              <Button
                type="text"
                icon={siderCollapsed ? <MenuUnfoldOutlined /> : <MenuFoldOutlined />}
                onClick={() => setSiderCollapsed(!siderCollapsed)}
                aria-label={siderCollapsed ? 'Open sidebar' : 'Close sidebar'}
                style={{ color: token.colorTextSecondary }}
              />
            )}
            <Avatar
              aria-hidden="true"
              src={isImageIcon(appIcon) ? appIcon : undefined}
              icon={!appIcon ? <RobotOutlined /> : undefined}
              style={{
                background: !appIcon ? token.colorPrimary : isImageIcon(appIcon) ? token.colorFillSecondary : token.colorBgContainer,
                color: !appIcon ? '#fff' : token.colorText,
                fontSize: appIcon && !isImageIcon(appIcon) ? 18 : undefined,
                border: isImageIcon(appIcon) ? `1px solid ${token.colorBorderSecondary}` : undefined,
              }}
              size={36}
            >
              {appIcon && !isImageIcon(appIcon) ? appIcon : null}
            </Avatar>
            <div>
              <Text strong className="app-name">{appName}</Text>
              <Text type="secondary" className="app-subtitle">AI Assistant</Text>
            </div>
          </div>

          <div className="header-right">
            <Tooltip title={isDark ? 'Light mode' : 'Dark mode'}>
              <Button
                icon={isDark ? <SunOutlined /> : <MoonOutlined />}
                onClick={onToggleDark}
                type="text"
                aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
                style={{ color: token.colorTextSecondary }}
              />
            </Tooltip>
            <Tooltip title="Active tools">
              <Badge count={tools.length} size="small">
                <Button
                  icon={<ToolOutlined />}
                  onClick={handleOpenTools}
                  type="text"
                  aria-label="View active tools"
                  style={{ color: token.colorTextSecondary }}
                />
              </Badge>
            </Tooltip>
            <Tooltip title="GitHub (opens in new tab)">
              <Button
                icon={<GithubOutlined />}
                href="https://github.com/jkandasa/promptd"
                target="_blank"
                rel="noopener noreferrer"
                type="text"
                aria-label="View source on GitHub (opens in new tab)"
                style={{ color: token.colorTextSecondary }}
              />
            </Tooltip>
          </div>
        </div>

        {/* ── Page content ── */}
        {view === 'chat' ? (
          <ChatPage
            models={models}
            modelData={modelData}
            uiConfig={uiConfig}
            isDark={isDark}
            siderCollapsed={siderCollapsed}
            setSiderCollapsed={setSiderCollapsed}
            onRefreshModels={handleRefreshModels}
          />
        ) : (
          <div className="scheduler-wrap">
            <SchedulerPage models={models} tools={tools} uiConfig={uiConfig} />
          </div>
        )}

        <ToolsDrawer
          open={toolsOpen}
          onClose={() => setToolsOpen(false)}
          tools={tools}
          loading={toolsLoading}
          onRefresh={fetchTools}
        />
      </Layout>
    </Layout>
  )
}
