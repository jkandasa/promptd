import 'dart:async';

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
    required this.onRefresh,
    this.onBack,
  });

  final PromptdAppState state;
  final Schedule? schedule;
  final bool canWrite;
  final FutureOr<void> Function()? onTrigger;
  final VoidCallback? onEdit;
  final Future<void> Function()? onDelete;
  final Future<void> Function() onRefresh;
  final VoidCallback? onBack;

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
                  onBack: widget.onBack,
                  onTrigger: _triggerNow,
                  onEdit: widget.onEdit,
                  onDelete: () => _confirmDelete(context),
                  onRefresh: () async {
                    await widget.onRefresh();
                    if (!mounted) return;
                    setState(() {
                      _executionsFuture = _loadExecutions();
                    });
                  },
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
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete execution?'),
                              content: Text(
                                'Delete execution from ${_date(execution.triggeredAt)}?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  style: const ButtonStyle(
                                    mouseCursor: WidgetStatePropertyAll(
                                      SystemMouseCursors.click,
                                    ),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  style: ButtonStyle(
                                    backgroundColor: WidgetStatePropertyAll(
                                      Theme.of(context).colorScheme.error,
                                    ),
                                    foregroundColor: WidgetStatePropertyAll(
                                      Theme.of(context).colorScheme.onError,
                                    ),
                                    mouseCursor: const WidgetStatePropertyAll(
                                      SystemMouseCursors.click,
                                    ),
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true || !mounted) return;
                          await widget.state.deleteScheduleExecution(
                            scheduleId: current.id,
                            executionId: execution.id,
                          );
                          await _refreshAfterMutation();
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
            style: const ButtonStyle(
              mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.error,
              ),
              foregroundColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.onError,
              ),
              mouseCursor: const WidgetStatePropertyAll(
                SystemMouseCursors.click,
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onDelete?.call();
  }

  String _date(DateTime? date) =>
      date == null ? '-' : date.toLocal().toString();

  Future<void> _triggerNow() async {
    await widget.onTrigger?.call();
    if (!mounted) return;
    setState(() => _executionsFuture = _loadExecutions());
    unawaited(
      Future<void>.delayed(const Duration(seconds: 2)).then((_) {
        if (!mounted) return;
        setState(() => _executionsFuture = _loadExecutions());
      }),
    );
  }

  Future<void> _refreshAfterMutation() async {
    await widget.onRefresh();
    if (!mounted) return;
    setState(() => _executionsFuture = _loadExecutions());
  }
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({
    required this.schedule,
    required this.canWrite,
    required this.onBack,
    required this.onTrigger,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
  });

  final Schedule schedule;
  final bool canWrite;
  final VoidCallback? onBack;
  final Future<void> Function()? onTrigger;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = schedule.enabled
        ? theme.colorScheme.primary
        : Colors.orange;
    final title = Row(
      children: [
        if (onBack != null) ...[
          IconButton(
            tooltip: 'Back to schedules',
            onPressed: onBack,
            mouseCursor: SystemMouseCursors.click,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
        ],
        Icon(
          schedule.enabled
              ? Icons.event_available_outlined
              : Icons.event_busy_outlined,
          color: statusColor,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                schedule.name,
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                schedule.enabled ? 'Enabled' : 'Disabled',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 2,
      runSpacing: 2,
      alignment: WrapAlignment.end,
      children: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: onRefresh,
          mouseCursor: SystemMouseCursors.click,
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton.filledTonal(
          tooltip: 'Run now',
          onPressed: canWrite && onTrigger != null
              ? () => unawaited(onTrigger!())
              : null,
          mouseCursor: SystemMouseCursors.click,
          icon: const Icon(Icons.play_arrow_rounded),
        ),
        IconButton(
          tooltip: 'Edit',
          onPressed: canWrite ? onEdit : null,
          mouseCursor: SystemMouseCursors.click,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Delete',
          onPressed: canWrite ? onDelete : null,
          mouseCursor: SystemMouseCursors.click,
          color: theme.colorScheme.error,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 16,
            compact ? 10 : 14,
            compact ? 8 : 10,
            compact ? 10 : 12,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 10),
                    actions,
                  ],
                ),
        );
      },
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
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.68,
            ),
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
              mouseCursor: SystemMouseCursors.click,
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

class _ExecutionCard extends StatefulWidget {
  const _ExecutionCard({required this.execution, required this.onDelete});

  final ScheduleExecution execution;
  final Future<void> Function() onDelete;

  @override
  State<_ExecutionCard> createState() => _ExecutionCardState();
}

class _ExecutionCardState extends State<_ExecutionCard> {
  bool _responseExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (widget.execution.status) {
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
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 360;
                final statusLine = Row(
                  mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 9, color: statusColor),
                    const SizedBox(width: 7),
                    Text(
                      widget.execution.status,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Tooltip(
                        message: _date(widget.execution.triggeredAt),
                        child: Text(
                          _relativeTime(widget.execution.triggeredAt),
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.execution.trace.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => showTraceDetailsDialog(
                          context,
                          widget.execution.trace,
                        ),
                        icon: const Icon(Icons.bolt_rounded, size: 16),
                        label: const Text('LLM Trace'),
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          mouseCursor: WidgetStatePropertyAll(
                            SystemMouseCursors.click,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Delete execution',
                      onPressed: widget.onDelete,
                      visualDensity: VisualDensity.compact,
                      mouseCursor: SystemMouseCursors.click,
                      color: theme.colorScheme.error,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      statusLine,
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: statusLine),
                    const SizedBox(width: 6),
                    actions,
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (widget.execution.providerUsed?.isNotEmpty == true ||
                    widget.execution.modelUsed?.isNotEmpty == true)
                  _MiniMeta(
                    [
                      widget.execution.providerUsed,
                      widget.execution.modelUsed,
                    ].where((value) => value?.isNotEmpty == true).join(' · '),
                  ),
                if (widget.execution.durationMs != null)
                  _MiniMeta(_duration(widget.execution.durationMs!)),
                if (widget.execution.llmCalls != null)
                  _MiniMeta('${widget.execution.llmCalls} LLM calls'),
                if (widget.execution.toolCalls != null)
                  _MiniMeta('${widget.execution.toolCalls} tool calls'),
              ],
            ),
            if (widget.execution.error?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                widget.execution.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (widget.execution.response?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: () =>
                    setState(() => _responseExpanded = !_responseExpanded),
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(8),
                child: Container(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _responseExpanded
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.keyboard_arrow_right_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.62,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Response',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (_responseExpanded) ...[
                        const SizedBox(height: 10),
                        MarkdownBody(
                          data: widget.execution.response!,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet.fromTheme(theme)
                              .copyWith(
                                p: theme.textTheme.bodySmall?.copyWith(
                                  height: 1.55,
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.white
                                      : null,
                                ),
                                h1: theme.textTheme.titleLarge?.copyWith(
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.white
                                      : null,
                                ),
                                h2: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.white
                                      : null,
                                ),
                                h3: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.white
                                      : null,
                                ),
                                listBullet: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.white
                                      : null,
                                ),
                                code: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.white
                                      : null,
                                ),
                              ),
                        ),
                      ],
                    ],
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

  String _relativeTime(DateTime? date) {
    if (date == null) return '';
    final diffMs = date.difference(DateTime.now()).inMilliseconds;
    final future = diffMs > 0;
    final seconds = (diffMs.abs() / 1000).floor();
    if (seconds < 60) return future ? 'in ${seconds}s' : '${seconds}s ago';
    final minutes = (seconds / 60).floor();
    if (minutes < 60) return future ? 'in ${minutes}m' : '${minutes}m ago';
    final hours = (minutes / 60).floor();
    if (hours < 24) return future ? 'in ${hours}h' : '${hours}h ago';
    final days = (hours / 24).floor();
    return future ? 'in ${days}d' : '${days}d ago';
  }

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
