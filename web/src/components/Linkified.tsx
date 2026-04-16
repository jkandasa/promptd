import type { ReactNode } from 'react'
import { safeUrl } from '../utils/helpers'

const URL_RE = /https?:\/\/[^\s<>"')\]]+/g

export function Linkified({ text, linkColor }: { text: string; linkColor: string }) {
  const parts: ReactNode[] = []
  let last = 0
  let match: RegExpExecArray | null
  URL_RE.lastIndex = 0
  while ((match = URL_RE.exec(text)) !== null) {
    if (match.index > last) parts.push(text.slice(last, match.index))
    const url = match[0]
    parts.push(
      <a
        key={match.index}
        href={safeUrl(url)}
        target="_blank"
        rel="noopener noreferrer"
        style={{ color: linkColor, textDecoration: 'underline', wordBreak: 'break-all' }}
      >
        {url}
      </a>
    )
    last = match.index + url.length
  }
  if (last < text.length) parts.push(text.slice(last))
  return <>{parts}</>
}
