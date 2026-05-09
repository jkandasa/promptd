import 'package:flutter/material.dart';

import '../../models/promptd_models.dart';

class ToolCard extends StatelessWidget {
  const ToolCard({super.key, required this.tool});

  final ToolInfo tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parameterCount = tool.parameterNames.length;
    final requiredCount = tool.requiredNames.length;

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
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const Spacer(),
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
          ],
        ),
      ),
    );
  }
}
