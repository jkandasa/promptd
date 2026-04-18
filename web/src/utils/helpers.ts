export function uid(): string {
  return crypto.randomUUID()
}

export function formatMessageTime(d: Date): string {
  if (isNaN(d.getTime())) return ''
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

export const MAX_FILE_SIZE = 10 * 1024 * 1024 // 10 MB — matches server limit
export const MAX_FILES_PER_MESSAGE = 10
export const MAX_MESSAGE_LENGTH = 4000
export const TYPING_DOTS = [0, 1, 2]

export function safeUrl(url: string | undefined): string {
  if (!url) return '#'
  try {
    const u = new URL(url, window.location.href)
    if (u.protocol === 'javascript:' || u.protocol === 'data:') return '#'
    if (u.pathname.startsWith('/files/')) return `${u.origin}/api${u.pathname}${u.search}`
    return u.toString()
  } catch {
    return '#'
  }
}

export function isImageIcon(icon?: string): boolean {
  if (!icon) return false
  return /^(https?:\/\/|\/|data:image\/)/.test(icon)
}

export function relativeTime(dateStr: string): string {
  const then = new Date(dateStr).getTime()
  if (isNaN(then)) return ''
  const diff = Date.now() - then
  const mins = Math.floor(diff / 60_000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hours = Math.floor(diff / 3_600_000)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(diff / 86_400_000)
  if (days === 1) return 'yesterday'
  if (days < 7) return `${days}d ago`
  return new Date(dateStr).toLocaleDateString([], { month: 'short', day: 'numeric' })
}
