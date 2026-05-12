import 'package:flutter/material.dart';

class SearchSelectOption<T> {
  const SearchSelectOption({
    required this.value,
    required this.label,
    this.subtitle,
  });

  final T value;
  final String label;
  final String? subtitle;
}

class SearchSelectField<T> extends StatelessWidget {
  const SearchSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.width = 220,
    this.enabled = true,
    this.emptyText = 'No options',
  });

  final String label;
  final List<SearchSelectOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final double width;
  final bool enabled;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedOption;

    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onTap: enabled ? () => _openPicker(context) : null,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.search_rounded),
            enabled: enabled,
          ),
          child: Text(
            selected?.label ?? emptyText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: enabled
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.42),
            ),
          ),
        ),
      ),
    );
  }

  SearchSelectOption<T>? get _selectedOption {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return null;
  }

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showDialog<T>(
      context: context,
      builder: (context) {
        return _SearchSelectDialog<T>(
          title: label,
          options: options,
          emptyText: emptyText,
        );
      },
    );
    if (selected != null) onChanged(selected);
  }
}

class _SearchSelectDialog<T> extends StatefulWidget {
  const _SearchSelectDialog({
    required this.title,
    required this.options,
    required this.emptyText,
  });

  final String title;
  final List<SearchSelectOption<T>> options;
  final String emptyText;

  @override
  State<_SearchSelectDialog<T>> createState() => _SearchSelectDialogState<T>();
}

class _SearchSelectDialogState<T> extends State<_SearchSelectDialog<T>> {
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryController.text.trim().toLowerCase();
    final filtered = widget.options.where((option) {
      if (query.isEmpty) return true;
      return option.label.toLowerCase().contains(query) ||
          (option.subtitle?.toLowerCase().contains(query) ?? false);
    }).toList();

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _queryController,
              style: Theme.of(context).textTheme.bodyLarge,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(widget.emptyText))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final option = filtered[index];
                        return ListTile(
                          mouseCursor: SystemMouseCursors.click,
                          title: Text(option.label),
                          subtitle: option.subtitle == null
                              ? null
                              : Text(option.subtitle!),
                          onTap: () => Navigator.of(context).pop(option.value),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
