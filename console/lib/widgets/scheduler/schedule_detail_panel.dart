import 'package:flutter/material.dart';

import '../../models/promptd_models.dart';

class ScheduleDetailPanel extends StatelessWidget {
  const ScheduleDetailPanel({
    super.key,
    required this.schedule,
    required this.canWrite,
    required this.onTrigger,
  });

  final Schedule? schedule;
  final bool canWrite;
  final VoidCallback? onTrigger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = schedule;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: current == null
            ? const Center(child: Text('Select a schedule to inspect'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          current.name,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Run now',
                        onPressed: canWrite ? onTrigger : null,
                        icon: const Icon(Icons.play_arrow_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _DetailRow(label: 'Type', value: current.type),
                  _DetailRow(
                    label: current.type == 'once' ? 'Run at' : 'Cron',
                    value: current.type == 'once'
                        ? _date(current.runAt)
                        : current.cronExpr ?? '',
                  ),
                  _DetailRow(label: 'Provider', value: current.provider ?? ''),
                  _DetailRow(label: 'Model', value: current.modelId ?? ''),
                  _DetailRow(
                    label: 'System prompt',
                    value: current.systemPrompt ?? '',
                  ),
                  _DetailRow(
                    label: 'Retain history',
                    value: current.retainHistory == 0
                        ? 'Keep all'
                        : current.retainHistory.toString(),
                  ),
                  const SizedBox(height: 10),
                  Text('Prompt', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        current.prompt,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _date(DateTime? date) => date == null ? '' : date.toLocal().toString();
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
