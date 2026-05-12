import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../models/promptd_models.dart';
import '../../state/promptd_app_state.dart';
import '../chat/trace_details_dialog.dart';

class ScheduleDetailPanel extends StatefulWidget {
  const ScheduleDetailPanel({
    super.key,
    required this.state,
    required this.schedule,
    required this.canWrite,
    required this.onTrigger,
    required this.onEdit,
    required this.onDelete,
  });

  final PromptdAppState state;
  final Schedule? schedule;
  final bool canWrite;
  final VoidCallback? onTrigger;
  final VoidCallback? onEdit;
  final Future<void> Function()? onDelete;

  @override
  State<ScheduleDetailPanel> createState() => _ScheduleDetailPanelState();
}

class _ScheduleDetailPanelState extends State<ScheduleDetailPanel> {
  late Future<List<ScheduleExecution>>? _executionsFuture;

  @override
  void initState() {
    super.initState();
    _executionsFuture = _loadExecutions();
  }

  @override
  void didUpdateWidget(covariant ScheduleDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schedule?.id != widget.schedule?.id) {
      _executionsFuture = _loadExecutions();
    }
  }

  Future<List<ScheduleExecution>>? _loadExecutions() {
    final id = widget.schedule?.id;
    if (id == null || id.isEmpty) return null;
    return widget.state.scheduleExecutions(id);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.schedule;
    return Card(
      child: current == null
          ? const Center(child: Text('Select a schedule to inspect'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScheduleHeader(
                  schedule: current,
                  canWrite: widget.canWrite,
                  onTrigger: widget.onTrigger,
                  onEdit: widget.onEdit,
                  onDelete: () => _confirmDelete(context),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _ScheduleSummary(schedule: current),
                      const SizedBox(height: 14),
                      _PromptWell(prompt: current.prompt),
                      const SizedBox(height: 18),
                      _ExecutionHistory(
                        future: _executionsFuture,
                        onRefresh: () => setState(() {
                          _executionsFuture = _loadExecutions();
                        }),
                        onDelete: (execution) async {
                          await widget.state.deleteScheduleExecution(
                            scheduleId: current.id,
                            executionId: execution.id,
                          );
                          setState(() => _executionsFuture = _loadExecutions());
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete schedule?'),
        content: Text('Delete "${widget.schedule?.name ?? 'schedule'}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onDelete?.call();
  }
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({
    required this.schedule,
    required this.canWrite,
    required this.onTrigger,
    required this.onEdit,
    required this.onDelete,
  });

  final Schedule schedule;
  final bool canWrite;
  final VoidCallback? onTrigger;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      child: Row(
        children: [
          Icon(
            schedule.enabled
                ? Icons.event_available_outlined
                : Icons.event_busy_outlined,
            color: schedule.enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.48),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(schedule.name, style: theme.textTheme.titleLarge),
                const SizedBox(height: 3),
                Text(
                  schedule.enabled ? 'Enabled' : 'Disabled',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Run now',
            onPressed: canWrite ? onTrigger : null,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: canWrite ? onEdit : null,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: canWrite ? onDelete : null,
            color: theme.colorScheme.error,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _ScheduleSummary extends StatelessWidget {
  const _ScheduleSummary({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context) {
    final params = schedule.params;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _InfoChip(Icons.repeat_rounded, schedule.type),
        _InfoChip(
          Icons.schedule_rounded,
          schedule.type == 'once'
              ? _date(schedule.runAt)
              : schedule.cronExpr ?? '-',
        ),
        _InfoChip(Icons.cloud_queue_rounded, schedule.provider ?? 'Auto'),
        _InfoChip(Icons.memory_rounded, schedule.modelId ?? 'Auto'),
        if (schedule.systemPrompt?.isNotEmpty == true)
          _InfoChip(Icons.psychology_outlined, schedule.systemPrompt!),
        _InfoChip(
          Icons.build_outlined,
          schedule.allowedTools?.isNotEmpty == true
              ? '${schedule.allowedTools!.length} tools'
              : 'All tools',
        ),
        _InfoChip(
          Icons.timeline_rounded,
          schedule.traceEnabled == null
              ? 'Trace default'
              : schedule.traceEnabled!
              ? 'Trace on'
              : 'Trace off',
        ),
        _InfoChip(
          Icons.history_rounded,
          schedule.retainHistory == 0
              ? 'Keep all'
              : 'Keep ${schedule.retainHistory}',
        ),
        if (params != null && !params.isEmpty)
          _InfoChip(Icons.tune_rounded, _params(params)),
      ],
    );
  }

  String _date(DateTime? date) =>
      date == null ? '-' : date.toLocal().toString();

  String _params(LlmParams params) {
    return [
      if (params.temperature != null) 'temp=${params.temperature}',
      if (params.maxTokens != null) 'max=${params.maxTokens}',
      if (params.topP != null) 'top_p=${params.topP}',
      if (params.topK != null) 'top_k=${params.topK}',
    ].join(' · ');
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 5),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PromptWell extends StatelessWidget {
  const _PromptWell({required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Prompt', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: SelectableText(
            prompt,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _ExecutionHistory extends StatelessWidget {
  const _ExecutionHistory({
    required this.future,
    required this.onRefresh,
    required this.onDelete,
  });

  final Future<List<ScheduleExecution>>? future;
  final VoidCallback onRefresh;
  final Future<void> Function(ScheduleExecution execution) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Previous executions', style: theme.textTheme.titleMedium),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh executions',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (future == null)
          const Text('No schedule selected')
        else
          FutureBuilder<List<ScheduleExecution>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final executions = snapshot.data ?? const [];
              if (executions.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('No executions yet'),
                );
              }
              return Column(
                children: [
                  for (final execution in executions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ExecutionCard(
                        execution: execution,
                        onDelete: () => onDelete(execution),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _ExecutionCard extends StatelessWidget {
  const _ExecutionCard({required this.execution, required this.onDelete});

  final ScheduleExecution execution;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (execution.status) {
      'success' => Colors.green,
      'error' => theme.colorScheme.error,
      _ => theme.colorScheme.primary,
    };
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.42)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 9, color: statusColor),
                const SizedBox(width: 7),
                Text(execution.status, style: theme.textTheme.labelLarge),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _date(execution.triggeredAt),
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (execution.trace.isNotEmpty)
                  TextButton.icon(
                    onPressed: () =>
                        showTraceDetailsDialog(context, execution.trace),
                    icon: const Icon(Icons.bolt_rounded, size: 16),
                    label: const Text('LLM Trace'),
                  ),
                IconButton(
                  tooltip: 'Delete execution',
                  onPressed: onDelete,
                  color: theme.colorScheme.error,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (execution.providerUsed?.isNotEmpty == true ||
                    execution.modelUsed?.isNotEmpty == true)
                  _MiniMeta(
                    [
                      execution.providerUsed,
                      execution.modelUsed,
                    ].where((value) => value?.isNotEmpty == true).join(' · '),
                  ),
                if (execution.durationMs != null)
                  _MiniMeta(_duration(execution.durationMs!)),
                if (execution.llmCalls != null)
                  _MiniMeta('${execution.llmCalls} LLM calls'),
                if (execution.toolCalls != null)
                  _MiniMeta('${execution.toolCalls} tool calls'),
              ],
            ),
            if (execution.error?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                execution.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (execution.response?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  ),
                ),
                child: MarkdownBody(
                  data: execution.response!,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodySmall?.copyWith(height: 1.55),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _date(DateTime? date) =>
      date == null ? '-' : date.toLocal().toString();

  String _duration(int ms) =>
      ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(1)}s';
}

class _MiniMeta extends StatelessWidget {
  const _MiniMeta(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
      ),
    );
  }
}
