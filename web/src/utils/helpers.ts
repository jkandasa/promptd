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
    return url
  } catch {
    return '#'
  }
}

export function isImageIcon(icon?: string): boolean {
  if (!icon) return false
  return /^(https?:\/\/|\/|data:image\/)/.test(icon)
}
