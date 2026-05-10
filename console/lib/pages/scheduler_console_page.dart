import 'package:flutter/material.dart';

import '../state/promptd_app_state.dart';
import '../widgets/scheduler/schedule_detail_panel.dart';
import '../widgets/scheduler/schedule_list_panel.dart';

class SchedulerConsolePage extends StatelessWidget {
  const SchedulerConsolePage({super.key, required this.state});

  final PromptdAppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scheduler', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Scheduled prompts from the connected Promptd server.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final selected = state.schedules.isNotEmpty
                  ? state.schedules.first
                  : null;

              final detail = ScheduleDetailPanel(
                schedule: selected,
                canWrite: state.me?.permissions.schedulesWrite ?? false,
                onTrigger: selected == null
                    ? null
                    : () => state.triggerSchedule(selected.id),
              );

              if (!wide) {
                return ListView(
                  children: [
                    SizedBox(
                      height: 330,
                      child: ScheduleListPanel(state: state),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(height: 460, child: detail),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: ScheduleListPanel(state: state)),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: detail),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
