import type { ComponentPropsWithoutRef } from 'react'
import { theme } from 'antd'
import { CodeBlock } from '../CodeBlock'
import { safeUrl } from '../../utils/helpers'

const { useToken } = theme

export function buildMarkdownComponents(token: ReturnType<typeof useToken>['token']) {
  return {
    code({ className, children, ...props }: ComponentPropsWithoutRef<'code'> & { className?: string }) {
      const match = /language-(\w+)/.exec(className || '')
      const codeStr = String(children).replace(/\n$/, '')
      if (match) {
        return <CodeBlock language={match[1]} code={codeStr} />
      }
      return (
        <code
          style={{
            background: token.colorFillSecondary,
            padding: '2px 6px',
            borderRadius: 4,
            fontSize: '0.9em',
            fontFamily: token.fontFamilyCode,
          }}
          {...props}
        >
          {children}
        </code>
      )
    },
    pre({ children }: ComponentPropsWithoutRef<'pre'>) {
      return <>{children}</>
    },
    p({ children }: ComponentPropsWithoutRef<'p'>) {
      return <p style={{ margin: '0.5em 0' }}>{children}</p>
    },
    ul({ children }: ComponentPropsWithoutRef<'ul'>) {
      return <ul style={{ margin: '0.5em 0', paddingLeft: '1.5em' }}>{children}</ul>
    },
    ol({ children }: ComponentPropsWithoutRef<'ol'>) {
      return <ol style={{ margin: '0.5em 0', paddingLeft: '1.5em' }}>{children}</ol>
    },
    li({ children }: ComponentPropsWithoutRef<'li'>) {
      return <li style={{ margin: '0.25em 0' }}>{children}</li>
    },
    blockquote({ children }: ComponentPropsWithoutRef<'blockquote'>) {
      return (
        <blockquote
          style={{
            margin: '0.5em 0',
            paddingLeft: '1em',
            borderLeft: `3px solid ${token.colorPrimary}`,
            color: token.colorTextSecondary,
          }}
        >
          {children}
        </blockquote>
      )
    },
    table({ children }: ComponentPropsWithoutRef<'table'>) {
      return (
        <div style={{ overflowX: 'auto', margin: '0.5em 0' }}>
          <table style={{ borderCollapse: 'collapse', width: '100%', fontSize: 13 }}>
            {children}
          </table>
        </div>
      )
    },
    th({ children }: ComponentPropsWithoutRef<'th'>) {
      return (
        <th
          style={{
            border: `1px solid ${token.colorBorder}`,
            padding: '6px 10px',
            background: token.colorFillSecondary,
            fontWeight: 600,
            textAlign: 'left',
          }}
        >
          {children}
        </th>
      )
    },
    td({ children }: ComponentPropsWithoutRef<'td'>) {
      return (
        <td style={{ border: `1px solid ${token.colorBorder}`, padding: '6px 10px' }}>
          {children}
        </td>
      )
    },
    a({ href, children }: ComponentPropsWithoutRef<'a'>) {
      return (
        <a
          href={safeUrl(href)}
          target="_blank"
          rel="noopener noreferrer"
          style={{ color: token.colorPrimary }}
        >
          {children}
        </a>
      )
    },
    h1({ children }: ComponentPropsWithoutRef<'h1'>) {
      return <h1 style={{ margin: '0.75em 0 0.4em', fontSize: '1.3em', fontWeight: 700 }}>{children}</h1>
    },
    h2({ children }: ComponentPropsWithoutRef<'h2'>) {
      return <h2 style={{ margin: '0.7em 0 0.35em', fontSize: '1.15em', fontWeight: 600 }}>{children}</h2>
    },
    h3({ children }: ComponentPropsWithoutRef<'h3'>) {
      return <h3 style={{ margin: '0.6em 0 0.3em', fontSize: '1.05em', fontWeight: 600 }}>{children}</h3>
    },
    hr() {
      return <hr style={{ border: 'none', borderTop: `1px solid ${token.colorBorder}`, margin: '0.75em 0' }} />
    },
  }
}
