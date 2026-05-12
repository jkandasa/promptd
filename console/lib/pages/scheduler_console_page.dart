import 'package:flutter/material.dart';

import '../models/promptd_models.dart';
import '../state/promptd_app_state.dart';
import '../widgets/scheduler/schedule_detail_panel.dart';
import '../widgets/scheduler/schedule_form_panel.dart';
import '../widgets/scheduler/schedule_list_panel.dart';

class SchedulerConsolePage extends StatefulWidget {
  const SchedulerConsolePage({super.key, required this.state});

  final PromptdAppState state;

  @override
  State<SchedulerConsolePage> createState() => _SchedulerConsolePageState();
}

class _SchedulerConsolePageState extends State<SchedulerConsolePage> {
  String? _selectedId;
  Schedule? _editing;
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final selected = _selectedSchedule(state.schedules);
    final showForm = _creating || _editing != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
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
                ],
              ),
            ),
            if (state.me?.permissions.schedulesWrite ?? false)
              FilledButton.icon(
                onPressed: () => setState(() {
                  _creating = true;
                  _editing = null;
                }),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New schedule'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final list = ScheduleListPanel(
                state: state,
                selectedId: selected?.id,
                onSelected: (schedule) => setState(() {
                  _selectedId = schedule.id;
                  _creating = false;
                  _editing = null;
                }),
                onOpen: (schedule) => setState(() {
                  _selectedId = schedule.id;
                  _creating = false;
                  _editing = null;
                }),
                onCreate: () => setState(() {
                  _creating = true;
                  _editing = null;
                }),
              );
              final detail = showForm
                  ? ScheduleFormPanel(
                      state: state,
                      initial: _editing,
                      onSaved: (schedule) {
                        setState(() {
                          _selectedId = schedule.id;
                          _creating = false;
                          _editing = null;
                        });
                      },
                      onCancel: () => setState(() {
                        _creating = false;
                        _editing = null;
                      }),
                    )
                  : ScheduleDetailPanel(
                      state: state,
                      schedule: selected,
                      canWrite: state.me?.permissions.schedulesWrite ?? false,
                      onTrigger: selected == null
                          ? null
                          : () => state.triggerSchedule(selected.id),
                      onEdit: selected == null
                          ? null
                          : () => setState(() {
                              _editing = selected;
                              _creating = false;
                            }),
                      onDelete: selected == null
                          ? null
                          : () async {
                              await state.deleteSchedule(selected.id);
                              setState(() {
                                _selectedId = null;
                                _editing = null;
                                _creating = false;
                              });
                            },
                    );

              if (!wide) {
                return Column(
                  children: [
                    SizedBox(height: 260, child: list),
                    const SizedBox(height: 14),
                    Expanded(child: detail),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: list),
                  const SizedBox(width: 16),
                  Expanded(flex: 7, child: detail),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Schedule? _selectedSchedule(List<Schedule> schedules) {
    if (schedules.isEmpty) return null;
    if (_selectedId != null) {
      for (final schedule in schedules) {
        if (schedule.id == _selectedId) return schedule;
      }
    }
    return schedules.first;
  }
}
