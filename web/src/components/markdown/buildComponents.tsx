import { Children, Fragment, isValidElement } from 'react'
import type { ComponentPropsWithoutRef, ReactElement, ReactNode } from 'react'
import { CodeBlock } from '../CodeBlock'
import { safeUrl } from '../../utils/helpers'
import './buildComponents.scss'

export function buildMarkdownComponents() {
  return {
    code({ className, children, ...props }: ComponentPropsWithoutRef<'code'> & { className?: string }) {
      const match = /language-(\w+)/.exec(className || '')
      const codeStr = String(children).replace(/\n$/, '')
      if (match) {
        return <CodeBlock language={match[1]} code={codeStr} />
      }
      return (
        <code className="md-inline-code" {...props}>
          {children}
        </code>
      )
    },
    pre({ children }: ComponentPropsWithoutRef<'pre'>) {
      return <>{children}</>
    },
    p({ children }: ComponentPropsWithoutRef<'p'>) {
      return <p>{children}</p>
    },
    ul({ children }: ComponentPropsWithoutRef<'ul'>) {
      return <ul>{children}</ul>
    },
    ol({ children }: ComponentPropsWithoutRef<'ol'>) {
      return <ol>{children}</ol>
    },
    li({ children }: ComponentPropsWithoutRef<'li'>) {
      const normalizedChildren = Children.map(children, (child) => {
        if (!isValidElement(child) || child.type !== 'p') return child
        const paragraph = child as ReactElement<{ children?: ReactNode }>
        return <Fragment>{paragraph.props.children}</Fragment>
      })
      return <li>{normalizedChildren}</li>
    },
    blockquote({ children }: ComponentPropsWithoutRef<'blockquote'>) {
      return <blockquote>{children}</blockquote>
    },
    table({ children }: ComponentPropsWithoutRef<'table'>) {
      return (
        <div className="md-table-wrap">
          <table>
            {children}
          </table>
        </div>
      )
    },
    th({ children }: ComponentPropsWithoutRef<'th'>) {
      return <th>{children}</th>
    },
    td({ children }: ComponentPropsWithoutRef<'td'>) {
      return <td>{children}</td>
    },
    a({ href, children }: ComponentPropsWithoutRef<'a'>) {
      return (
        <a
          href={safeUrl(href)}
          target="_blank"
          rel="noopener noreferrer"
        >
          {children}
        </a>
      )
    },
    h1({ children }: ComponentPropsWithoutRef<'h1'>) {
      return <h1>{children}</h1>
    },
    h2({ children }: ComponentPropsWithoutRef<'h2'>) {
      return <h2>{children}</h2>
    },
    h3({ children }: ComponentPropsWithoutRef<'h3'>) {
      return <h3>{children}</h3>
    },
    hr() {
      return <hr />
    },
  }
}
