import 'package:flutter/material.dart';

import '../models/promptd_models.dart';
import '../state/promptd_app_state.dart';
import '../widgets/tools/tool_card.dart';

class ToolsConsolePage extends StatefulWidget {
  const ToolsConsolePage({super.key, required this.state});

  final PromptdAppState state;

  @override
  State<ToolsConsolePage> createState() => _ToolsConsolePageState();
}

class _ToolsConsolePageState extends State<ToolsConsolePage> {
  final _searchController = TextEditingController();
  String _filter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tools = _filteredTools();
    final isNarrow = MediaQuery.sizeOf(context).width < 680;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text('Tools', style: theme.textTheme.headlineMedium),
            ),
            IconButton.outlined(
              tooltip: 'Refresh tools',
              onPressed: widget.state.loadingData
                  ? null
                  : () => widget.state.refreshAppData(),
              icon: widget.state.loadingData
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${tools.length} of ${widget.state.tools.length} tools available from the connected server.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 18),
        Flex(
          direction: isNarrow ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: isNarrow
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: isNarrow ? double.infinity : 320,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search tools',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SizedBox(width: isNarrow ? 0 : 10, height: isNarrow ? 10 : 0),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(
                  value: 'configurable',
                  label: Text('Configurable'),
                ),
                ButtonSegment(value: 'simple', label: Text('Simple')),
              ],
              selected: {_filter},
              onSelectionChanged: (value) {
                setState(() => _filter = value.first);
              },
            ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: widget.state.loadingData && widget.state.tools.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : widget.state.tools.isEmpty
              ? const Center(child: Text('No tools registered'))
              : tools.isEmpty
              ? Center(
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
                )
              : GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _columnCount(context),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: _cardExtent(context),
                  ),
                  itemCount: tools.length,
                  itemBuilder: (context, index) => ToolCard(tool: tools[index]),
                ),
        ),
      ],
    );
  }

  List<ToolInfo> _filteredTools() {
    final query = _searchController.text.trim().toLowerCase();
    return widget.state.tools.where((tool) {
      final configurable = tool.parameterNames.isNotEmpty;
      if (_filter == 'configurable' && !configurable) return false;
      if (_filter == 'simple' && configurable) return false;
      if (query.isEmpty) return true;
      final required = tool.requiredNames.join(' ').toLowerCase();
      return tool.name.toLowerCase().contains(query) ||
          tool.description.toLowerCase().contains(query) ||
          required.contains(query);
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  int _columnCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1400) return 4;
    if (width >= 1000) return 3;
    if (width >= 680) return 2;
    return 1;
  }

  double _cardExtent(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1400) return 312;
    if (width >= 1000) return 326;
    if (width >= 680) return 300;
    return 280;
  }
}
