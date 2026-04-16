import { Avatar, theme } from 'antd'
import { RobotOutlined } from '@ant-design/icons'
import { TYPING_DOTS } from '../utils/helpers'

const { useToken } = theme

export function TypingIndicator() {
  const { token } = useToken()
  return (
    <div className="typing-indicator" style={{ display: 'flex', alignItems: 'flex-end', gap: 10 }}>
      <Avatar
        aria-hidden="true"
        size={32}
        icon={<RobotOutlined />}
        style={{ background: token.colorPrimary, flexShrink: 0 }}
      />
      <div
        style={{
          background: token.colorBgContainer,
          border: `1px solid ${token.colorBorderSecondary}`,
          borderRadius: '18px 18px 18px 4px',
          padding: '12px 16px',
          display: 'flex',
          gap: 5,
          alignItems: 'center',
        }}
      >
        <span className="sr-only">Assistant is typing…</span>
        {TYPING_DOTS.map((i) => (
          <span
            key={i}
            aria-hidden="true"
            className="typing-dot"
            style={{ animationDelay: `${i * 0.18}s` }}
          />
        ))}
      </div>
    </div>
  )
}
