import 'package:flutter/material.dart';

import '../../models/promptd_models.dart';
import '../../state/promptd_app_state.dart';
import '../common/app_ui.dart';

class ScheduleListPanel extends StatefulWidget {
  const ScheduleListPanel({
    super.key,
    required this.state,
    required this.selectedId,
    required this.onSelected,
    required this.onOpen,
    required this.onCreate,
    this.onRefresh,
  });

  final PromptdAppState state;
  final String? selectedId;
  final ValueChanged<Schedule> onSelected;
  final ValueChanged<Schedule> onOpen;
  final VoidCallback onCreate;
  final Future<void> Function()? onRefresh;

  @override
  State<ScheduleListPanel> createState() => _ScheduleListPanelState();
}

class _ScheduleListPanelState extends State<ScheduleListPanel> {
  final _searchController = TextEditingController();
  String _statusFilter = 'all';
  String _sortKey = 'default';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.state.me!.permissions.schedulesRead) {
      return const Card(
        child: Center(
          child: Text('Schedule access is not enabled for this user.'),
        ),
      );
    }

    final schedules = _filteredSchedules();

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ListHeader(
            total: widget.state.schedules.length,
            visible: schedules.length,
            canWrite: widget.state.me?.permissions.schedulesWrite ?? false,
            onCreate: widget.onCreate,
            onRefresh: widget.onRefresh,
          ),
          const Divider(height: 1),
          _ScheduleToolbar(
            controller: _searchController,
            statusFilter: _statusFilter,
            sortKey: _sortKey,
            totalCount: widget.state.schedules.length,
            enabledCount: widget.state.schedules.where((s) => s.enabled).length,
            disabledCount: widget.state.schedules.where((s) => !s.enabled).length,
            onSearchChanged: (_) => setState(() {}),
            onStatusChanged: (value) => setState(() => _statusFilter = value),
            onSortChanged: (value) => setState(() => _sortKey = value),
          ),
          Expanded(
            child: widget.state.schedules.isEmpty
                ? _EmptySchedules(onCreate: widget.onCreate)
                : schedules.isEmpty
                ? _NoFilterMatches(onClear: _clearFilters)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 640;
                      return ListView.separated(
                        padding: EdgeInsets.all(compact ? 10 : 12),
                        itemCount: schedules.length,
                        separatorBuilder: (_, _) =>
                            SizedBox(height: compact ? 8 : 10),
                        itemBuilder: (context, index) {
                          final schedule = schedules[index];
                          return _ScheduleTile(
                            schedule: schedule,
                            compact: compact,
                            selected: schedule.id == widget.selectedId,
                            onTap: () => widget.onSelected(schedule),
                            onDoubleTap: () => widget.onOpen(schedule),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<Schedule> _filteredSchedules() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.state.schedules.where((schedule) {
      if (query.isNotEmpty &&
          !schedule.name.toLowerCase().contains(query) &&
          !schedule.prompt.toLowerCase().contains(query)) {
        return false;
      }
      if (_statusFilter == 'enabled' && !schedule.enabled) return false;
      if (_statusFilter == 'disabled' && schedule.enabled) return false;
      return true;
    }).toList();

    if (_sortKey == 'name') {
      filtered.sort((a, b) => a.name.compareTo(b.name));
    } else if (_sortKey == 'lastRun') {
      filtered.sort(
        (a, b) => (b.lastRunAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.lastRunAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    } else if (_sortKey == 'nextRun') {
      filtered.sort(
        (a, b) => (a.nextRunAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.nextRunAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    }
    return filtered;
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _statusFilter = 'all';
      _sortKey = 'default';
    });
  }
}

class _ListHeader extends StatefulWidget {
  const _ListHeader({
    required this.total,
    required this.visible,
    required this.canWrite,
    required this.onCreate,
    required this.onRefresh,
  });

  final int total;
  final int visible;
  final bool canWrite;
  final VoidCallback onCreate;
  final Future<void> Function()? onRefresh;

  @override
  State<_ListHeader> createState() => _ListHeaderState();
}

class _ListHeaderState extends State<_ListHeader> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            compact ? 12 : 16,
            compact ? 8 : 12,
            compact ? 10 : 14,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Schedules', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 3),
                    Text(
                      widget.visible == widget.total
                          ? '${widget.total} schedule${widget.total == 1 ? '' : 's'}'
                          : '${widget.visible} of ${widget.total} schedules',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.64,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onRefresh != null)
                IconButton(
                  tooltip: 'Refresh schedules',
                  onPressed: _refreshing ? null : _refresh,
                  mouseCursor: SystemMouseCursors.click,
                  icon: _refreshing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              if (widget.canWrite) ...[
                SizedBox(width: compact ? 2 : 6),
                compact
                    ? IconButton.filledTonal(
                        tooltip: 'Create schedule',
                        onPressed: widget.onCreate,
                        mouseCursor: SystemMouseCursors.click,
                        icon: const Icon(Icons.add_rounded),
                      )
                    : AppButton(
                        label: 'New schedule',
                        icon: Icons.add_rounded,
                        onPressed: widget.onCreate,
                      ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh?.call();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }
}

class _ScheduleToolbar extends StatelessWidget {
  const _ScheduleToolbar({
    required this.controller,
    required this.statusFilter,
    required this.sortKey,
    required this.totalCount,
    required this.enabledCount,
    required this.disabledCount,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onSortChanged,
  });

  final TextEditingController controller;
  final String statusFilter;
  final String sortKey;
  final int totalCount;
  final int enabledCount;
  final int disabledCount;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final useWrappedChips = constraints.maxWidth < 520;
        final search = TextField(
          controller: controller,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Search schedules...',
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      controller.clear();
                      onSearchChanged('');
                    },
                    mouseCursor: SystemMouseCursors.click,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        );
        final filterControl = useWrappedChips
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppChoiceChip(
                    label: 'All',
                    count: totalCount,
                    selected: statusFilter == 'all',
                    onSelected: () => onStatusChanged('all'),
                  ),
                  AppChoiceChip(
                    label: 'Active',
                    count: enabledCount,
                    selected: statusFilter == 'enabled',
                    onSelected: () => onStatusChanged('enabled'),
                  ),
                  AppChoiceChip(
                    label: 'Disabled',
                    count: disabledCount,
                    selected: statusFilter == 'disabled',
                    onSelected: () => onStatusChanged('disabled'),
                  ),
                ],
              )
            : SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'all', label: Text('All ($totalCount)')),
                  ButtonSegment(
                    value: 'enabled',
                    label: Text('Active ($enabledCount)'),
                  ),
                  ButtonSegment(
                    value: 'disabled',
                    label: Text('Disabled ($disabledCount)'),
                  ),
                ],
                selected: {statusFilter},
                onSelectionChanged: (value) => onStatusChanged(value.first),
              );
        final sort = MouseRegion(
          cursor: SystemMouseCursors.click,
          child: PopupMenuButton<String>(
            tooltip: 'Sort schedules',
            initialValue: sortKey,
            onSelected: onSortChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'default', child: Text('Default order')),
              PopupMenuItem(value: 'name', child: Text('Name')),
              PopupMenuItem(value: 'lastRun', child: Text('Last run')),
              PopupMenuItem(value: 'nextRun', child: Text('Next run')),
            ],
            child: _SortButton(label: _sortLabel(sortKey)),
          ),
        );
        final filters = Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            filterControl,
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: sort,
            ),
          ],
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            12,
            compact ? 12 : 16,
            10,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [search, const SizedBox(height: 10), filters],
                )
              : Row(
                  children: [
                    SizedBox(width: 340, child: search),
                    const SizedBox(width: 12),
                    Expanded(child: filters),
                  ],
                ),
        );
      },
    );
  }

  String _sortLabel(String value) {
    return switch (value) {
      'name' => 'Name',
      'lastRun' => 'Last run',
      'nextRun' => 'Next run',
      _ => 'Default',
    };
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 16),
            const SizedBox(width: 6),
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({
    required this.schedule,
    required this.compact,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
  });

  final Schedule schedule;
  final bool compact;
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
          padding: EdgeInsets.all(compact ? 11 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.42)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: compact ? _compactContent(context) : _wideContent(context),
        ),
      ),
    );
  }

  Widget _wideContent(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
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
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(schedule.name, style: theme.textTheme.titleMedium),
                  AppPill(
                    label: schedule.enabled ? 'enabled' : 'disabled',
                    tone: schedule.enabled ? AppTone.success : AppTone.warning,
                  ),
                  AppPill(
                    label: schedule.type,
                    tone: schedule.type == 'cron'
                        ? AppTone.primary
                        : AppTone.warning,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                schedule.prompt,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.66),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _MetaText('Schedule', _scheduleLine(schedule)),
                  _MetaText('Last', _relativeTime(schedule.lastRunAt) ?? '-'),
                  _MetaText(
                    'Next',
                    schedule.enabled
                        ? _relativeTime(schedule.nextRunAt) ?? '-'
                        : '-',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.chevron_right_rounded,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
        ),
      ],
    );
  }

  Widget _compactContent(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(schedule.name, style: theme.textTheme.titleSmall),
                      AppPill(
                        label: schedule.enabled ? 'enabled' : 'disabled',
                        tone: schedule.enabled
                            ? AppTone.success
                            : AppTone.warning,
                      ),
                      AppPill(
                        label: schedule.type,
                        tone: schedule.type == 'cron'
                            ? AppTone.primary
                            : AppTone.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    schedule.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.68,
                      ),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 5,
          children: [
            _MetaText('Schedule', _scheduleLine(schedule)),
            _MetaText('Last', _relativeTime(schedule.lastRunAt) ?? '-'),
            _MetaText(
              'Next',
              schedule.enabled ? _relativeTime(schedule.nextRunAt) ?? '-' : '-',
            ),
          ],
        ),
      ],
    );
  }

  String _scheduleLine(Schedule schedule) {
    if (schedule.type == 'once') {
      return schedule.runAt == null
          ? 'Once'
          : 'Once · ${schedule.runAt!.toLocal()}';
    }
    return schedule.cronExpr ?? 'cron';
  }

  String? _relativeTime(DateTime? date) {
    if (date == null) return null;
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
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _EmptySchedules extends StatelessWidget {
  const _EmptySchedules({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: 'No schedules configured',
      message: 'Create a scheduled prompt to run it automatically.',
      icon: Icons.event_repeat_rounded,
      action: AppButton(
        label: 'Create first schedule',
        icon: Icons.add_rounded,
        onPressed: onCreate,
      ),
    );
  }
}

class _NoFilterMatches extends StatelessWidget {
  const _NoFilterMatches({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: 'No schedules match the current filters',
      message: 'Try a different search, status, or sort option.',
      icon: Icons.search_off_rounded,
      action: TextButton(
        onPressed: onClear,
        child: const Text('Clear filters'),
      ),
    );
  }
}
