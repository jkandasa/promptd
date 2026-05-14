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
  bool _narrowDetailOpen = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final showForm = _creating || _editing != null;
    final canWrite = state.me?.permissions.schedulesWrite ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1080;
              final selected = _selectedSchedule(
                state.schedules,
                autoSelect: wide,
              );
              final showNarrowDetail =
                  !wide &&
                  (showForm || (_narrowDetailOpen && selected != null));

              Widget listPanel = ScheduleListPanel(
                state: state,
                selectedId: selected?.id,
                onSelected: (schedule) => setState(() {
                  _selectedId = schedule.id;
                  _creating = false;
                  _editing = null;
                  if (!wide) _narrowDetailOpen = true;
                }),
                onOpen: (schedule) => setState(() {
                  _selectedId = schedule.id;
                  _creating = false;
                  _editing = null;
                  if (!wide) _narrowDetailOpen = true;
                }),
                onCreate: () => setState(() {
                  _creating = true;
                  _editing = null;
                  _narrowDetailOpen = true;
                }),
                onRefresh: state.refreshSchedules,
              );

              Widget detailPanel;
              if (showForm) {
                detailPanel = ScheduleFormPanel(
                  state: state,
                  initial: _editing,
                  onBack: !wide
                      ? () => setState(() {
                          _creating = false;
                          _editing = null;
                          _narrowDetailOpen = false;
                        })
                      : null,
                  onSaved: (schedule) {
                    setState(() {
                      _selectedId = schedule.id;
                      _creating = false;
                      _editing = null;
                      _narrowDetailOpen = !wide;
                    });
                  },
                  onCancel: () => setState(() {
                    _creating = false;
                    _editing = null;
                    if (!wide && selected == null) _narrowDetailOpen = false;
                  }),
                );
              } else if (selected != null) {
                detailPanel = ScheduleDetailPanel(
                  state: state,
                  schedule: selected,
                  canWrite: canWrite,
                  onBack: !wide
                      ? () => setState(() => _narrowDetailOpen = false)
                      : null,
                  onTrigger: () => state.triggerSchedule(selected.id),
                  onEdit: () => setState(() {
                    _editing = selected;
                    _creating = false;
                    _narrowDetailOpen = true;
                  }),
                  onRefresh: () async {
                    await state.refreshSchedules();
                    if (!mounted) return;
                    setState(() {});
                  },
                  onDelete: () async {
                    await state.deleteSchedule(selected.id);
                    if (!mounted) return;
                    setState(() {
                      _selectedId = null;
                      _editing = null;
                      _creating = false;
                      _narrowDetailOpen = false;
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
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Select a schedule to view details',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (!wide) {
                return showNarrowDetail ? detailPanel : listPanel;
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

  Schedule? _selectedSchedule(
    List<Schedule> schedules, {
    required bool autoSelect,
  }) {
    if (schedules.isEmpty) return null;
    if (_selectedId != null) {
      for (final schedule in schedules) {
        if (schedule.id == _selectedId) return schedule;
      }
    }
    return autoSelect ? schedules.first : null;
  }
}
