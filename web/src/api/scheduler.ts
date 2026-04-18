import type { Schedule, Execution } from '../types/scheduler'

export async function apiListSchedules(): Promise<Schedule[]> {
  const res = await fetch('/schedules')
  if (!res.ok) return []
  const data = await res.json()
  return data.schedules ?? []
}

export async function apiGetSchedule(id: string): Promise<Schedule | null> {
  const res = await fetch(`/schedules/${id}`)
  if (!res.ok) return null
  return res.json()
}

export async function apiCreateSchedule(sc: Omit<Schedule, 'id' | 'createdAt' | 'updatedAt'>): Promise<Schedule> {
  const res = await fetch('/schedules', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(sc),
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'Failed to create schedule')
  return data as Schedule
}

export async function apiUpdateSchedule(id: string, sc: Partial<Schedule>): Promise<Schedule> {
  const res = await fetch(`/schedules/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(sc),
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'Failed to update schedule')
  return data as Schedule
}

export async function apiDeleteSchedule(id: string): Promise<void> {
  await fetch(`/schedules/${id}`, { method: 'DELETE' })
}

export async function apiTriggerSchedule(id: string): Promise<void> {
  const res = await fetch(`/schedules/${id}/trigger`, { method: 'POST' })
  if (!res.ok) {
    const data = await res.json()
    throw new Error(data.error || 'Failed to trigger schedule')
  }
}

export async function apiListExecutions(scheduleId: string): Promise<Execution[]> {
  const res = await fetch(`/schedules/${scheduleId}/executions`)
  if (!res.ok) return []
  const data = await res.json()
  return data.executions ?? []
}

export async function apiDeleteExecution(scheduleId: string, execId: string): Promise<void> {
  await fetch(`/schedules/${scheduleId}/executions/${execId}`, { method: 'DELETE' })
}
