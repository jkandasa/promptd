import 'package:flutter/material.dart';

import '../models/promptd_models.dart';
import '../state/promptd_app_state.dart';

enum _ToolSortColumn { name, parameters, required, inbuilt }

const double _toolsParamColumnWidth = 112;
const double _toolsRequiredColumnWidth = 96;
const double _toolsInbuiltColumnWidth = 104;

class ToolsConsolePage extends StatefulWidget {
  const ToolsConsolePage({super.key, required this.state});

  final PromptdAppState state;

  @override
  State<ToolsConsolePage> createState() => _ToolsConsolePageState();
}

class _ToolsConsolePageState extends State<ToolsConsolePage> {
  final _searchController = TextEditingController();
  final Map<String, bool> _expandedRows = {};
  String _filter = 'all';
  _ToolSortColumn _sortColumn = _ToolSortColumn.name;
  bool _sortAscending = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tools = _filteredTools();
    final toolsWithParams = widget.state.tools
        .where((t) => t.parameterNames.isNotEmpty)
        .length;
    final simpleTools = widget.state.tools.length - toolsWithParams;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final isSmall = width < 768;
        final isNarrow = width < 900;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ToolsTopBar(compact: isSmall),
            const SizedBox(height: 16),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isSmall ? 12 : 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(isSmall ? 12 : 18),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: theme.shadowColor.withValues(alpha: 0.04),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isSmall ? 12 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ToolsPanelHeader(
                          stacked: isNarrow,
                          shownCount: tools.length,
                          totalCount: widget.state.tools.length,
                          toolsWithParams: toolsWithParams,
                          simpleTools: simpleTools,
                          filter: _filter,
                          searchController: _searchController,
                          loading: widget.state.loadingData,
                          onFilterChanged: (value) {
                            setState(() => _filter = value);
                          },
                          onSearchChanged: () => setState(() {}),
                          onRefresh: widget.state.refreshAppData,
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _buildToolsContent(
                            isSmall: isSmall,
                            tools: tools,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolsContent({
    required bool isSmall,
    required List<ToolInfo> tools,
  }) {
    if (widget.state.loadingData && widget.state.tools.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.state.tools.isEmpty) {
      return const Center(child: Text('No tools registered'));
    }
    if (tools.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No matching tools'),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() => _filter = 'all');
              },
              child: const Text('Clear filters'),
            ),
          ],
        ),
      );
    }

    return KeyedSubtree(
      key: ValueKey(isSmall),
      child: isSmall
          ? _ToolsCardList(
              tools: tools,
              onToggle: _toggleRow,
              expandedRows: _expandedRows,
            )
          : _ToolsTableDesktop(
              tools: tools,
              sortColumn: _sortColumn,
              sortAscending: _sortAscending,
              onSort: _sortBy,
              onToggle: _toggleRow,
              expandedRows: _expandedRows,
            ),
    );
  }

  void _toggleRow(String name) {
    setState(() {
      _expandedRows[name] = !(_expandedRows[name] ?? false);
    });
  }

  void _sortBy(_ToolSortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  List<ToolInfo> _filteredTools() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.state.tools.where((tool) {
      final configurable = tool.parameterNames.isNotEmpty;
      if (_filter == 'configurable' && !configurable) return false;
      if (_filter == 'simple' && configurable) return false;
      if (query.isEmpty) return true;
      final required = tool.requiredNames.join(' ').toLowerCase();
      return tool.name.toLowerCase().contains(query) ||
          tool.description.toLowerCase().contains(query) ||
          required.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final result = switch (_sortColumn) {
        _ToolSortColumn.name => a.name.compareTo(b.name),
        _ToolSortColumn.parameters => a.parameterNames.length.compareTo(
          b.parameterNames.length,
        ),
        _ToolSortColumn.required => a.requiredNames.length.compareTo(
          b.requiredNames.length,
        ),
        _ToolSortColumn.inbuilt => _isInbuilt(a).compareTo(_isInbuilt(b)),
      };
      if (result == 0) return a.name.compareTo(b.name);
      return _sortAscending ? result : -result;
    });

    return filtered;
  }
}

int _isInbuilt(ToolInfo tool) => tool.name == 'get_current_datetime' ? 1 : 0;

class _ToolsTopBar extends StatelessWidget {
  const _ToolsTopBar({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Text(
      'Available Tools',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: compact
          ? theme.textTheme.titleLarge
          : theme.textTheme.headlineMedium,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: title)],
    );
  }
}

class _ToolsPanelHeader extends StatelessWidget {
  const _ToolsPanelHeader({
    required this.stacked,
    required this.shownCount,
    required this.totalCount,
    required this.toolsWithParams,
    required this.simpleTools,
    required this.filter,
    required this.searchController,
    required this.loading,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onRefresh,
  });

  final bool stacked;
  final int shownCount;
  final int totalCount;
  final int toolsWithParams;
  final int simpleTools;
  final String filter;
  final TextEditingController searchController;
  final bool loading;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onSearchChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Catalog',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$shownCount tool${shownCount == 1 ? '' : 's'} shown',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );

    final controls = _ToolsPanelControls(
      stacked: stacked,
      totalCount: totalCount,
      toolsWithParams: toolsWithParams,
      simpleTools: simpleTools,
      filter: filter,
      searchController: searchController,
      loading: loading,
      onFilterChanged: onFilterChanged,
      onSearchChanged: onSearchChanged,
      onRefresh: onRefresh,
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [copy, const SizedBox(height: 12), controls],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: copy),
        const SizedBox(width: 16),
        Expanded(flex: 2, child: controls),
      ],
    );
  }
}

class _ToolsPanelControls extends StatelessWidget {
  const _ToolsPanelControls({
    required this.stacked,
    required this.totalCount,
    required this.toolsWithParams,
    required this.simpleTools,
    required this.filter,
    required this.searchController,
    required this.loading,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onRefresh,
  });

  final bool stacked;
  final int totalCount;
  final int toolsWithParams;
  final int simpleTools;
  final String filter;
  final TextEditingController searchController;
  final bool loading;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onSearchChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final filterControl = LayoutBuilder(
      builder: (context, constraints) {
        final useWrappedChips = stacked && constraints.maxWidth < 520;
        if (useWrappedChips) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ToolFilterChip(
                label: 'All',
                count: totalCount,
                selected: filter == 'all',
                onSelected: () => onFilterChanged('all'),
              ),
              _ToolFilterChip(
                label: 'Configurable',
                count: toolsWithParams,
                selected: filter == 'configurable',
                onSelected: () => onFilterChanged('configurable'),
              ),
              _ToolFilterChip(
                label: 'Simple',
                count: simpleTools,
                selected: filter == 'simple',
                onSelected: () => onFilterChanged('simple'),
              ),
            ],
          );
        }

        return SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'all', label: Text('All ($totalCount)')),
            ButtonSegment(
              value: 'configurable',
              label: Text('Configurable ($toolsWithParams)'),
            ),
            ButtonSegment(
              value: 'simple',
              label: Text('Simple ($simpleTools)'),
            ),
          ],
          selected: {filter},
          onSelectionChanged: (value) => onFilterChanged(value.first),
        );
      },
    );
    final search = TextField(
      controller: searchController,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      decoration: InputDecoration(
        hintText: 'Search tools',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  searchController.clear();
                  onSearchChanged();
                },
                icon: const Icon(Icons.close_rounded),
              ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onChanged: (_) => onSearchChanged(),
    );
    final refresh = _CatalogRefreshButton(
      loading: loading,
      onRefresh: onRefresh,
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filterControl,
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              refresh,
            ],
          ),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        filterControl,
        SizedBox(width: 280, child: search),
        refresh,
      ],
    );
  }
}

class _CatalogRefreshButton extends StatelessWidget {
  const _CatalogRefreshButton({required this.loading, required this.onRefresh});

  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Refresh tools',
      child: SizedBox.square(
        dimension: 40,
        child: IconButton.outlined(
          onPressed: loading ? null : onRefresh,
          iconSize: 18,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ),
    );
  }
}

class _ToolFilterChip extends StatelessWidget {
  const _ToolFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedBackground = theme.colorScheme.primaryContainer.withValues(
      alpha: 0.72,
    );
    final selectedForeground = theme.colorScheme.onPrimaryContainer;

    return ChoiceChip(
      showCheckmark: false,
      selected: selected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.14)
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? selectedForeground
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: selected ? selectedForeground : theme.colorScheme.onSurface,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      backgroundColor: theme.colorScheme.surface,
      selectedColor: selectedBackground,
      side: BorderSide(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.42)
            : theme.colorScheme.outlineVariant,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      visualDensity: VisualDensity.compact,
      onSelected: (_) => onSelected(),
    );
  }
}

class _ToolsCardList extends StatelessWidget {
  const _ToolsCardList({
    required this.tools,
    required this.expandedRows,
    required this.onToggle,
  });

  final List<ToolInfo> tools;
  final Map<String, bool> expandedRows;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: tools.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final tool = tools[index];
        final expanded = expandedRows[tool.name] ?? false;
        return _ToolCard(
          tool: tool,
          expanded: expanded,
          onToggle: () => onToggle(tool.name),
        );
      },
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.tool,
    required this.expanded,
    required this.onToggle,
  });

  final ToolInfo tool;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parameters = tool.parameterNames;
    final requiredNames = tool.requiredNames.toSet();
    final parameterCount = parameters.length;
    final requiredCount = requiredNames.length;
    final isInbuilt = tool.name == 'get_current_datetime';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tool.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (tool.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          tool.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.45,
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.68,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isInbuilt)
                  Icon(
                    Icons.check_circle_rounded,
                    color: theme.colorScheme.primary,
                    size: 18,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ParamChip(label: '$parameterCount params'),
                if (requiredCount > 0)
                  _ParamChip(
                    label: '$requiredCount required',
                    color: theme.colorScheme.error,
                    background: theme.colorScheme.error.withValues(alpha: 0.1),
                  ),
              ],
            ),
            if (parameters.isNotEmpty) ...[
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text('Parameters', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded)
                SizedBox(
                  width: double.infinity,
                  child: _ParamsTable(
                    parameters: parameters,
                    requiredNames: requiredNames,
                    tool: tool,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolsTableDesktop extends StatelessWidget {
  const _ToolsTableDesktop({
    required this.tools,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.expandedRows,
    required this.onToggle,
  });

  final List<ToolInfo> tools;
  final _ToolSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<_ToolSortColumn> onSort;
  final Map<String, bool> expandedRows;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const SizedBox(width: 32),
              Expanded(
                flex: 5,
                child: _SortableHeader(
                  label: 'Name',
                  column: _ToolSortColumn.name,
                  activeColumn: sortColumn,
                  ascending: sortAscending,
                  style: headerStyle,
                  onSort: onSort,
                ),
              ),
              SizedBox(
                width: _toolsParamColumnWidth,
                child: Center(
                  child: _SortableHeader(
                    label: 'Parameters',
                    column: _ToolSortColumn.parameters,
                    activeColumn: sortColumn,
                    ascending: sortAscending,
                    style: headerStyle,
                    onSort: onSort,
                  ),
                ),
              ),
              SizedBox(
                width: _toolsRequiredColumnWidth,
                child: Center(
                  child: _SortableHeader(
                    label: 'Required',
                    column: _ToolSortColumn.required,
                    activeColumn: sortColumn,
                    ascending: sortAscending,
                    style: headerStyle,
                    onSort: onSort,
                  ),
                ),
              ),
              SizedBox(
                width: _toolsInbuiltColumnWidth,
                child: Center(
                  child: _SortableHeader(
                    label: 'Is Inbuilt',
                    column: _ToolSortColumn.inbuilt,
                    activeColumn: sortColumn,
                    ascending: sortAscending,
                    style: headerStyle,
                    onSort: onSort,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.separated(
            itemCount: tools.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final tool = tools[index];
              final expanded = expandedRows[tool.name] ?? false;
              return _ToolRowItem(
                tool: tool,
                expanded: expanded,
                onToggle: () => onToggle(tool.name),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ToolRowItem extends StatelessWidget {
  const _ToolRowItem({
    required this.tool,
    required this.expanded,
    required this.onToggle,
  });

  final ToolInfo tool;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parameters = tool.parameterNames;
    final requiredNames = tool.requiredNames.toSet();
    final parameterCount = parameters.length;
    final requiredCount = requiredNames.length;
    final isInbuilt = tool.name == 'get_current_datetime';

    return InkWell(
      onTap: parameterCount > 0 ? onToggle : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 32,
                  child: parameterCount > 0
                      ? Icon(
                          expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        )
                      : null,
                ),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tool.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (tool.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          tool.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: _toolsParamColumnWidth,
                  child: Center(child: _ParamChip(label: '$parameterCount')),
                ),
                SizedBox(
                  width: _toolsRequiredColumnWidth,
                  child: Center(
                    child: requiredCount > 0
                        ? _ParamChip(
                            label: '$requiredCount',
                            color: theme.colorScheme.error,
                            background: theme.colorScheme.error.withValues(
                              alpha: 0.1,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                SizedBox(
                  width: _toolsInbuiltColumnWidth,
                  child: Center(
                    child: isInbuilt
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: theme.colorScheme.primary,
                            size: 18,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
            if (expanded && parameterCount > 0) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: SizedBox(
                  width: double.infinity,
                  child: _ParamsTable(
                    parameters: parameters,
                    requiredNames: requiredNames,
                    tool: tool,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SortableHeader extends StatelessWidget {
  const _SortableHeader({
    required this.label,
    required this.column,
    required this.activeColumn,
    required this.ascending,
    required this.style,
    required this.onSort,
  });

  final String label;
  final _ToolSortColumn column;
  final _ToolSortColumn activeColumn;
  final bool ascending;
  final TextStyle? style;
  final ValueChanged<_ToolSortColumn> onSort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = column == activeColumn;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onSort(column),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(
                  color: active ? theme.colorScheme.primary : style?.color,
                  fontWeight: active ? FontWeight.w700 : style?.fontWeight,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              active
                  ? (ascending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded)
                  : Icons.unfold_more_rounded,
              size: active ? 13 : 12,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.36),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParamsTable extends StatelessWidget {
  const _ParamsTable({
    required this.parameters,
    required this.requiredNames,
    required this.tool,
  });

  final List<String> parameters;
  final Set<String> requiredNames;
  final ToolInfo tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Name', style: headerStyle)),
                Expanded(
                  flex: 5,
                  child: Text('Description', style: headerStyle),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (int i = 0; i < parameters.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _ParamTableRow(
              name: parameters[i],
              tool: tool,
              isRequired: requiredNames.contains(parameters[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ParamTableRow extends StatelessWidget {
  const _ParamTableRow({
    required this.name,
    required this.tool,
    required this.isRequired,
  });

  final String name;
  final ToolInfo tool;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final properties = tool.parameters?['properties'] as Map<String, dynamic>?;
    final schema = properties?[name] as Map<String, dynamic>?;
    final type = schema?['type'] as String? ?? 'value';
    final description = schema?['description'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  name,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  type,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    fontSize: 11,
                  ),
                ),
                if (isRequired)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'required',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              description.isNotEmpty ? description : '—',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParamChip extends StatelessWidget {
  const _ParamChip({required this.label, this.color, this.background});

  final String label;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 11,
          height: 1.2,
        ),
      ),
    );
  }
}
