part of 'trace_details_dialog.dart';

class _AvailableToolsList extends StatefulWidget {
  const _AvailableToolsList({required this.tools});

  final List<dynamic> tools;

  @override
  State<_AvailableToolsList> createState() => _AvailableToolsListState();
}

class _AvailableToolsListState extends State<_AvailableToolsList> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final tools = widget.tools.where((item) {
      if (query.isEmpty) return true;
      final tool = _map(item);
      final name = (tool['name'] as String? ?? '').toLowerCase();
      final description = (tool['description'] as String? ?? '').toLowerCase();
      return name.contains(query) || description.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.tools.length > 5) ...[
          SizedBox(
            height: 36,
            child: TextField(
              controller: _searchController,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: 'Filter tools...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear filter',
                        iconSize: 16,
                        visualDensity: VisualDensity.compact,
                        mouseCursor: SystemMouseCursors.click,
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (tools.isEmpty)
          const _EmptyTraceText('No matching tools')
        else if (tools.length <= 4)
          Column(
            children: [
              for (final item in tools)
                RepaintBoundary(child: _AvailableToolCard(tool: _map(item))),
            ],
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.48,
            ),
            child: ListView.separated(
              cacheExtent: 700,
              itemCount: tools.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) => RepaintBoundary(
                child: _AvailableToolCard(tool: _map(tools[index])),
              ),
            ),
          ),
      ],
    );
  }
}

class _AvailableToolCard extends StatelessWidget {
  const _AvailableToolCard({required this.tool});

  final Map<String, dynamic> tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parameters = _map(tool['parameters']);
    final params = _map(parameters['properties']);
    final requiredNames = (_list(parameters['required'])).whereType<String>().toSet();
    final description = tool['description'] as String? ?? '';
    final name = tool['name'] as String? ?? 'tool';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SmallTag(label: name, color: _traceBlue, code: true),
              if (params.isNotEmpty)
                Text(
                  '${params.length} param${params.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          if (params.isNotEmpty)
            _InlineExpansion(
              title: 'Parameters',
              child: _ParametersView(params: params, requiredNames: requiredNames),
            ),
        ],
      ),
    );
  }
}

class _ParametersView extends StatelessWidget {
  const _ParametersView({required this.params, required this.requiredNames});

  final Map<String, dynamic> params;
  final Set<String> requiredNames;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final entries = params.entries.toList();
        if (constraints.maxWidth >= 680) {
          return _ParameterTable(entries: entries, requiredNames: requiredNames);
        }
        return Column(
          children: [
            for (final entry in entries)
              _ParameterCard(
                name: entry.key,
                schema: _map(entry.value),
                required: requiredNames.contains(entry.key),
              ),
          ],
        );
      },
    );
  }
}

class _ParameterTable extends StatelessWidget {
  const _ParameterTable({required this.entries, required this.requiredNames});

  final List<MapEntry<String, dynamic>> entries;
  final Set<String> requiredNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(160),
        1: FixedColumnWidth(70),
        2: FlexColumnWidth(),
      },
      border: TableBorder.all(color: theme.colorScheme.outlineVariant),
      children: [
        TableRow(
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
          children: const [
            _ParameterCell('Parameter', header: true),
            _ParameterCell('Type', header: true),
            _ParameterCell('Description', header: true),
          ],
        ),
        for (final entry in entries)
          _parameterRow(context, entry, requiredNames.contains(entry.key)),
      ],
    );
  }

  TableRow _parameterRow(
    BuildContext context,
    MapEntry<String, dynamic> entry,
    bool required,
  ) {
    final schema = _map(entry.value);
    final type = schema['type'] as String? ?? 'value';
    final description = schema['description'] as String? ?? '';
    final theme = Theme.of(context);

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(entry.key, style: theme.textTheme.bodySmall),
              if (required) const _RequiredTag(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: type.isEmpty ? const SizedBox.shrink() : _TypeTag(type),
        ),
        _ParameterCell(description.isEmpty ? '-' : description),
      ],
    );
  }
}

class _ParameterCell extends StatelessWidget {
  const _ParameterCell(this.text, {this.header = false});

  final String text;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Text(
        text,
        style: header
            ? Theme.of(context).textTheme.labelSmall
            : Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _ParameterCard extends StatelessWidget {
  const _ParameterCard({
    required this.name,
    required this.schema,
    required this.required,
  });

  final String name;
  final Map<String, dynamic> schema;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = schema['type'] as String? ?? 'value';
    final description = schema['description'] as String? ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(name, style: theme.textTheme.labelMedium),
          if (required) const _RequiredTag(),
          if (type.isNotEmpty) _TypeTag(type),
          if (description.isNotEmpty) Text(description, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RequiredTag extends StatelessWidget {
  const _RequiredTag();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        'req',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 10,
          height: 1.35,
        ),
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  const _TypeTag(this.type);

  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        type,
        style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, height: 1.2),
      ),
    );
  }
}
