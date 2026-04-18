import {
  App as AntApp,
  Avatar,
  Button,
  Layout,
  Menu,
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
import { useLocation, useNavigate, useSearchParams } from 'react-router-dom'

import { ChatPage } from './chat/ChatPage'
import { SchedulerPage } from './scheduler/SchedulerPage'
import { ToolsPage } from './tools/ToolsPage'
import './index.scss'

const { Text } = Typography
const { useToken } = theme

interface PromptdAppProps {
  isDark: boolean
  onToggleDark: () => void
}

type AppView = 'chat' | 'scheduler' | 'tools'
type SchedulerEditorMode = 'new' | 'edit' | null

const VIEW_PATHS: Record<AppView, string> = {
  chat: '/chat',
  scheduler: '/scheduler',
  tools: '/tools',
}

function getPathState(pathname: string): {
  view: AppView
  conversationId: string | null
  scheduleId: string | null
  schedulerEditorMode: SchedulerEditorMode
} | null {
  const [root, id, action] = pathname.split('/').filter(Boolean)

  if (!root) {
    return { view: 'chat', conversationId: null, scheduleId: null, schedulerEditorMode: null }
  }

  if (root === 'chat') {
    if (!id || id === 'new') {
      return { view: 'chat', conversationId: null, scheduleId: null, schedulerEditorMode: null }
    }
    return { view: 'chat', conversationId: id, scheduleId: null, schedulerEditorMode: null }
  }

  if (root === 'scheduler') {
    if (id === 'new') {
      return { view: 'scheduler', conversationId: null, scheduleId: null, schedulerEditorMode: 'new' }
    }
    if (id && action === 'edit') {
      return { view: 'scheduler', conversationId: null, scheduleId: id, schedulerEditorMode: 'edit' }
    }
    return { view: 'scheduler', conversationId: null, scheduleId: id ?? null, schedulerEditorMode: null }
  }

  if (root === 'tools') {
    return { view: 'tools', conversationId: null, scheduleId: null, schedulerEditorMode: null }
  }

  return null
}

export function PromptdApp({ isDark, onToggleDark }: PromptdAppProps) {
  const { token } = useToken()
  const { message: antMessage } = AntApp.useApp()

  const location = useLocation()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const [navCollapsed, setNavCollapsed] = useState(() => {
    if (typeof window === 'undefined') return false
    return window.localStorage.getItem('promptd.navCollapsed') === 'true'
  })
  const [siderCollapsed, setSiderCollapsed] = useState(() => {
    if (typeof window === 'undefined') return false
    return window.localStorage.getItem('promptd.chatHistoryCollapsed') === 'true'
  })

  const [models, setModels] = useState<ModelInfo[]>([])
  const [modelData, setModelData] = useState<{ source?: string; count: number; updated_at?: string; refresh_interval?: string; global_params?: ModelData['global_params']; providers?: ProviderInfo[] }>({ count: 0 })
  const [uiConfig, setUIConfig] = useState<UIConfig>({})

  const [tools, setTools] = useState<ToolInfo[]>([])
  const [toolsLoading, setToolsLoading] = useState(false)

  const appName = uiConfig.appName || 'Promptd'
  const appIcon = uiConfig.appIcon
  const legacyConversationId = searchParams.get('conversation')
  const legacyScheduleId = searchParams.get('schedule')
  const pathState = getPathState(location.pathname)
  const view: AppView = pathState?.view ?? (legacyScheduleId ? 'scheduler' : 'chat')
  const conversationId = pathState?.conversationId ?? null
  const scheduleId = pathState?.scheduleId ?? null
  const schedulerEditorMode = pathState?.schedulerEditorMode ?? null

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
    if (legacyScheduleId) {
      navigate(`/scheduler/${legacyScheduleId}`, { replace: true })
      return
    }
    if (legacyConversationId) {
      navigate(`/chat/${legacyConversationId}`, { replace: true })
      return
    }
    if (pathState) return
    navigate('/chat/new', { replace: true })
  }, [legacyConversationId, legacyScheduleId, navigate, pathState])

  useEffect(() => {
    window.localStorage.setItem('promptd.navCollapsed', String(navCollapsed))
  }, [navCollapsed])

  useEffect(() => {
    window.localStorage.setItem('promptd.chatHistoryCollapsed', String(siderCollapsed))
  }, [siderCollapsed])

  const handleViewChange = useCallback((nextView: AppView) => {
    navigate(nextView === 'chat' ? '/chat/new' : VIEW_PATHS[nextView])
  }, [navigate])

  const handleConversationChange = useCallback((nextConversationId: string | null) => {
    navigate(nextConversationId ? `/chat/${nextConversationId}` : '/chat/new')
  }, [navigate])

  const handleScheduleChange = useCallback((nextScheduleId: string | null) => {
    navigate(nextScheduleId ? `/scheduler/${nextScheduleId}` : VIEW_PATHS.scheduler)
  }, [navigate])

  const handleScheduleCreate = useCallback(() => {
    navigate('/scheduler/new')
  }, [navigate])

  const handleScheduleEdit = useCallback((id: string) => {
    navigate(`/scheduler/${id}/edit`)
  }, [navigate])

  const handleScheduleEditorClose = useCallback(() => {
    navigate(scheduleId ? `/scheduler/${scheduleId}` : VIEW_PATHS.scheduler)
  }, [navigate, scheduleId])

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

  const handleRefreshModels = useCallback(async (provider?: string) => {
    const data = await apiGetModels(provider, true)
    const tagged = data.models.map((m) => ({ ...m, source: (data.source ?? 'static') as 'static' | 'discovered' }))
    if (!provider) {
      setModels(tagged)
    }
    setModelData({ source: data.source, count: data.count, updated_at: data.updated_at, refresh_interval: data.refresh_interval, global_params: data.global_params, providers: data.providers })
  }, [])

  return (
    <Layout className={`app-root${isDark ? ' app-dark' : ''}`} style={{ background: token.colorBgLayout }}>
      <div
        className="header"
        style={{
          background: token.colorBgContainer,
          borderBottom: `1px solid ${token.colorBorderSecondary}`,
          boxShadow: token.boxShadow,
        }}
      >
        <div className="brand-block">
          <Avatar
            aria-hidden="true"
            src={isImageIcon(appIcon) ? appIcon : undefined}
            icon={!appIcon ? <RobotOutlined /> : undefined}
            style={{
              background: !appIcon ? token.colorPrimary : isImageIcon(appIcon) ? token.colorFillSecondary : token.colorBgContainer,
              color: !appIcon ? '#fff' : token.colorText,
              fontSize: appIcon && !isImageIcon(appIcon) ? 18 : undefined,
              border: isImageIcon(appIcon) ? `1px solid ${token.colorBorderSecondary}` : undefined,
              flexShrink: 0,
            }}
            size={36}
          >
            {appIcon && !isImageIcon(appIcon) ? appIcon : null}
          </Avatar>
          <div className="brand-copy">
            <Text strong className="app-name">Promptd</Text>
            <Text type="secondary" className="app-subtitle">{appName}</Text>
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

      <Layout className="shell-body">
        <div
          className="shell-sidebar"
          style={{
            background: token.colorBgContainer,
            borderRight: `1px solid ${token.colorBorderSecondary}`,
          }}
        >
          <div className="shell-sidebar-header">
            <Button
              type="text"
              icon={navCollapsed ? <MenuUnfoldOutlined /> : <MenuFoldOutlined />}
              onClick={() => setNavCollapsed((prev) => !prev)}
              aria-label={navCollapsed ? 'Expand navigation' : 'Collapse navigation'}
            />
          </div>
          <Menu
            className="shell-menu"
            mode="inline"
            theme={isDark ? 'dark' : 'light'}
            inlineCollapsed={navCollapsed}
            selectedKeys={[view]}
            items={[
              { key: 'chat', icon: <MessageOutlined />, label: 'Chat' },
              { key: 'scheduler', icon: <CalendarOutlined />, label: 'Scheduler' },
              { key: 'tools', icon: <ToolOutlined />, label: 'Available Tools' },
            ]}
            onClick={({ key }) => handleViewChange(key as AppView)}
            style={{ borderInlineEnd: 'none', background: 'transparent' }}
          />
        </div>

        <Layout className="main-col">
          {view === 'chat' ? (
            <ChatPage
              models={models}
              modelData={modelData}
              uiConfig={uiConfig}
              isDark={isDark}
              siderCollapsed={siderCollapsed}
              setSiderCollapsed={setSiderCollapsed}
              onRefreshModels={handleRefreshModels}
              selectedConversationId={conversationId}
              onConversationChange={handleConversationChange}
            />
          ) : view === 'scheduler' ? (
            <div className="scheduler-wrap">
              <SchedulerPage
                models={models}
                tools={tools}
                uiConfig={uiConfig}
                selectedScheduleId={scheduleId}
                schedulerEditorMode={schedulerEditorMode}
                onSelectedScheduleChange={handleScheduleChange}
                onCreateSchedule={handleScheduleCreate}
                onEditSchedule={handleScheduleEdit}
                onCloseEditor={handleScheduleEditorClose}
              />
            </div>
          ) : (
            <ToolsPage tools={tools} loading={toolsLoading} onRefresh={fetchTools} />
          )}
        </Layout>
      </Layout>
    </Layout>
  )
}
