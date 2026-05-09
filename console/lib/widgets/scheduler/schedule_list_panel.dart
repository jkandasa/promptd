import 'package:flutter/material.dart';

import '../../models/promptd_models.dart';
import '../../state/promptd_app_state.dart';

class ScheduleListPanel extends StatelessWidget {
  const ScheduleListPanel({super.key, required this.state});

  final PromptdAppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!state.me!.permissions.schedulesRead) {
      return const Card(
        child: Center(
          child: Text('Schedule access is not enabled for this user.'),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('Schedules', style: theme.textTheme.titleLarge),
                const Spacer(),
                Text(
                  '${state.schedules.length}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: state.schedules.isEmpty
                ? const Center(child: Text('No schedules configured'))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: state.schedules.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _ScheduleTile(schedule: state.schedules[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(schedule.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  _scheduleLine(schedule),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Chip(
            label: Text(schedule.enabled ? 'Active' : 'Off'),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  String _scheduleLine(Schedule schedule) {
    if (schedule.type == 'once') {
      return schedule.runAt == null
          ? 'Once'
          : 'Once · ${schedule.runAt!.toLocal()}';
    }
    final next = schedule.nextRunAt == null
        ? ''
        : ' · next ${schedule.nextRunAt!.toLocal()}';
    return '${schedule.cronExpr ?? 'cron'}$next';
  }
}
