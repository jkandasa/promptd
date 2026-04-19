import { Alert, App as AntApp, Button, Card, ConfigProvider, Form, Input, Spin, Typography, theme } from 'antd'
import { useEffect, useState } from 'react'
import { apiGetMe, apiLogin, apiLogout, type AuthMe } from './api/client'
import { PromptdApp } from './pages'

const { Title, Text } = Typography

function LoginView({ onLogin }: { onLogin: (me: AuthMe) => void }) {
	const [loading, setLoading] = useState(false)
	const [error, setError] = useState('')
	const [form] = Form.useForm<{ userId: string; password: string }>()
	const { token: designToken } = theme.useToken()

	const handleFinish = async (values: { userId: string; password: string }) => {
		setLoading(true)
		setError('')
		try {
			const me = await apiLogin(values.userId, values.password)
			onLogin(me)
		} catch (err) {
			setError(err instanceof Error ? err.message : 'Login failed')
		} finally {
			setLoading(false)
		}
	}

	return (
		<div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', padding: 24, background: designToken.colorBgLayout }}>
			<Card style={{ width: '100%', maxWidth: 420 }}>
				<Title level={3} style={{ marginTop: 0, marginBottom: 8 }}>Sign in</Title>
				<Text type="secondary">Use your promptd user ID and password.</Text>
				<Form form={form} layout="vertical" onFinish={handleFinish} style={{ marginTop: 24 }}>
					<Form.Item label="User ID" name="userId" rules={[{ required: true, message: 'User ID is required' }]}>
						<Input autoComplete="username" />
					</Form.Item>
					<Form.Item label="Password" name="password" rules={[{ required: true, message: 'Password is required' }]}>
						<Input.Password autoComplete="current-password" />
					</Form.Item>
					{error ? <Alert type="error" showIcon message={error} style={{ marginBottom: 16 }} /> : null}
					<Button type="primary" htmlType="submit" block loading={loading}>Sign in</Button>
				</Form>
			</Card>
		</div>
	)
}

export default function App() {
	const [isDark, setIsDark] = useState(
		() => typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches,
	)
	const [authLoading, setAuthLoading] = useState(true)
	const [me, setMe] = useState<AuthMe | null>(null)

	useEffect(() => {
		let cancelled = false
		apiGetMe().then((current) => {
			if (cancelled) return
			setMe(current)
		}).catch(() => {
			if (cancelled) return
			setMe(null)
		}).finally(() => {
			if (cancelled) return
			setAuthLoading(false)
		})
		return () => { cancelled = true }
	}, [])

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
				{authLoading ? (
					<div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center' }}><Spin size="large" /></div>
				) : me ? (
					<PromptdApp
						isDark={isDark}
						onToggleDark={() => setIsDark(!isDark)}
						me={me}
						onLogout={async () => {
							await apiLogout()
							setMe(null)
						}}
					/>
				) : (
					<LoginView onLogin={setMe} />
				)}
			</AntApp>
		</ConfigProvider>
	)
}
