import 'package:flutter/material.dart';

import '../../models/promptd_models.dart';
import '../../state/promptd_app_state.dart';

class ScheduleListPanel extends StatelessWidget {
  const ScheduleListPanel({
    super.key,
    required this.state,
    required this.selectedId,
    required this.onSelected,
    required this.onOpen,
    required this.onCreate,
  });

  final PromptdAppState state;
  final String? selectedId;
  final ValueChanged<Schedule> onSelected;
  final ValueChanged<Schedule> onOpen;
  final VoidCallback onCreate;

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
                if (state.me?.permissions.schedulesWrite ?? false)
                  IconButton.filledTonal(
                    tooltip: 'Create schedule',
                    onPressed: onCreate,
                    mouseCursor: SystemMouseCursors.click,
                    icon: const Icon(Icons.add_rounded),
                  ),
                const SizedBox(width: 8),
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
                      final schedule = state.schedules[index];
                      return _ScheduleTile(
                        schedule: schedule,
                        selected: schedule.id == selectedId,
                        onTap: () => onSelected(schedule),
                        onDoubleTap: () => onOpen(schedule),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({
    required this.schedule,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
  });

  final Schedule schedule;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.42)
                  : theme.colorScheme.outlineVariant,
            ),
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
        ),
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
