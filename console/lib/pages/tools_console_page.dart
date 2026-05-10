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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tools', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          '${tools.length} of ${widget.state.tools.length} tools available from the connected server.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search tools',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
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
          child: widget.state.tools.isEmpty
              ? const Center(child: Text('No tools registered'))
              : tools.isEmpty
              ? const Center(child: Text('No matching tools'))
              : GridView.count(
                  crossAxisCount: _columnCount(context),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: _cardAspectRatio(context),
                  children: [for (final tool in tools) ToolCard(tool: tool)],
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
      return tool.name.toLowerCase().contains(query) ||
          tool.description.toLowerCase().contains(query) ||
          tool.parameterNames.join(' ').toLowerCase().contains(query);
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  int _columnCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1400) return 4;
    if (width >= 1000) return 3;
    if (width >= 680) return 2;
    return 1;
  }

  double _cardAspectRatio(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1400) return 1.12;
    if (width >= 1000) return 1.04;
    if (width >= 680) return 1.08;
    return 1.18;
  }
}
