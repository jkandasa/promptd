import 'package:flutter/material.dart';

import '../../models/promptd_models.dart';

class ToolCard extends StatelessWidget {
  const ToolCard({super.key, required this.tool});

  final ToolInfo tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parameters = _parameters(tool);
    final requiredNames = tool.requiredNames.toSet();
    final parameterCount = parameters.length;
    final requiredCount = requiredNames.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.1,
                  ),
                  child: Icon(
                    parameterCount > 0
                        ? Icons.tune_rounded
                        : Icons.check_circle_outline_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tool.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tool.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text('$parameterCount params'),
                  visualDensity: VisualDensity.compact,
                ),
                if (requiredCount > 0)
                  Chip(
                    label: Text('$requiredCount required'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (parameters.isNotEmpty) ...[
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: parameters.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final entry = parameters[index];
                    return _ToolParameter(
                      name: entry.name,
                      schema: entry.schema,
                      required: requiredNames.contains(entry.name),
                    );
                  },
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }

  List<({String name, Map<String, dynamic> schema})> _parameters(
    ToolInfo tool,
  ) {
    final properties = tool.parameters?['properties'];
    if (properties is! Map<String, dynamic>) return const [];
    return [
      for (final entry in properties.entries)
        (name: entry.key, schema: _schema(entry.value)),
    ];
  }

  Map<String, dynamic> _schema(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }
}

class _ToolParameter extends StatelessWidget {
  const _ToolParameter({
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                name,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
              Text(type, style: theme.textTheme.bodySmall),
              if (required)
                Icon(
                  Icons.error_outline_rounded,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
