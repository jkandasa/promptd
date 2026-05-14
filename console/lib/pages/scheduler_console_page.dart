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
    final canWrite = state.me?.permissions.schedulesWrite ?? false;

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
            if (canWrite && !showForm)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: FilledButton.icon(
                  onPressed: () => setState(() {
                    _creating = true;
                    _editing = null;
                  }),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New schedule'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;

              Widget listPanel = ScheduleListPanel(
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

              Widget detailPanel;
              if (showForm) {
                detailPanel = ScheduleFormPanel(
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
                );
              } else if (selected != null) {
                detailPanel = ScheduleDetailPanel(
                  state: state,
                  schedule: selected,
                  canWrite: canWrite,
                  onTrigger: () => state.triggerSchedule(selected.id),
                  onEdit: () => setState(() {
                    _editing = selected;
                    _creating = false;
                  }),
                  onRefresh: () async {
                    await state.refreshSchedules();
                    if (!mounted) return;
                    setState(() {});
                  },
                  onDelete: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete schedule?'),
                        content: Text('Delete "${selected.name}"?'),
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
                              backgroundColor: WidgetStatePropertyAll(theme.colorScheme.error),
                              foregroundColor: WidgetStatePropertyAll(theme.colorScheme.onError),
                              mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !mounted) return;
                    await state.deleteSchedule(selected.id);
                    if (!mounted) return;
                    setState(() {
                      _selectedId = null;
                      _editing = null;
                      _creating = false;
                    });
                  },
                );
              } else {
                detailPanel = Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.event_repeat_rounded,
                        size: 64,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Select a schedule to view details',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (!wide) {
                final screenHeight = MediaQuery.sizeOf(context).height;
                final listHeight = (screenHeight * 0.32).clamp(180.0, 300.0);
                return Column(
                  children: [
                    SizedBox(height: listHeight, child: listPanel),
                    const SizedBox(height: 14),
                    Expanded(child: detailPanel),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: listPanel),
                  const SizedBox(width: 16),
                  Expanded(flex: 7, child: detailPanel),
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
