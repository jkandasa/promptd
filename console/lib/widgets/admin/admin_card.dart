import 'package:flutter/material.dart';

import '../common/app_ui.dart';

class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.title,
    required this.icon,
    required this.action,
    required this.children,
    this.filter,
    this.emptyMessage = 'No records',
  });

  final String title;
  final IconData icon;
  final Widget action;
  final List<Widget> children;
  final Widget? filter;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppSurface(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
                action,
              ],
            ),
            if (filter != null) ...[
              const SizedBox(height: 10),
              filter!,
            ],
            const SizedBox(height: 8),
            if (children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  emptyMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AdminFilterField extends StatelessWidget {
  const AdminFilterField({
    super.key,
    required this.controller,
    required this.hint,
    required this.active,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final bool active;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: active
            ? IconButton(
                mouseCursor: SystemMouseCursors.click,
                icon: const Icon(Icons.clear_rounded, size: 16),
                onPressed: onClear,
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      ),
    );
  }
}

class AdminFormSectionLabel extends StatelessWidget {
  const AdminFormSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }
}
