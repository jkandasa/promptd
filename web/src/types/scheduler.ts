import type { LLMParamsOverride, LLMRound } from './chat'

export type ScheduleType = 'cron' | 'once'
export type ExecutionStatus = 'running' | 'success' | 'error'

export interface Schedule {
  id: string
  name: string
  enabled: boolean
  type: ScheduleType
  cronExpr?: string
  runAt?: string        // ISO datetime string
  prompt: string
  modelId?: string
  provider?: string
  systemPrompt?: string
  allowedTools?: string[] | null
  params?: LLMParamsOverride | null
  traceEnabled?: boolean | null   // null/undefined = follow global default
  retainHistory: number  // 0 = keep all
  createdAt: string
  updatedAt: string
  lastRunAt?: string
  nextRunAt?: string
}

export interface Execution {
  id: string
  scheduleId: string
  triggeredAt: string
  completedAt?: string
  status: ExecutionStatus
  error?: string
  response?: string
  trace?: LLMRound[]
  modelUsed?: string
  providerUsed?: string
  llmCalls?: number
  toolCalls?: number
  durationMs?: number
}
