import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../models/promptd_models.dart';
import '../../state/promptd_app_state.dart';
import '../common/app_ui.dart';
import 'admin_card.dart';

class AdminPromptsCard extends StatefulWidget {
  const AdminPromptsCard({super.key, required this.state});

  final PromptdAppState state;

  @override
  State<AdminPromptsCard> createState() => _AdminPromptsCardState();
}

class _AdminPromptsCardState extends State<AdminPromptsCard> {
  final _filterCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.state.managedSystemPrompts;
    final prompts = _filter.isEmpty
        ? all
        : all.where((p) => p.name.toLowerCase().contains(_filter)).toList();

    return AdminCard(
      title: 'System Prompts',
      icon: Icons.article_outlined,
      action: AppButton(
        label: 'Prompt',
        icon: Icons.add_rounded,
        onPressed: () => _showPromptDialog(context),
      ),
      filter: AdminFilterField(
        controller: _filterCtrl,
        hint: 'Filter prompts…',
        active: _filter.isNotEmpty,
        onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
        onClear: () {
          _filterCtrl.clear();
          setState(() => _filter = '');
        },
      ),
      emptyMessage: all.isEmpty ? 'No system prompts' : 'No matches for "$_filter"',
      children: [
        for (final prompt in prompts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(prompt.name),
            subtitle: Text(prompt.content, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'Edit',
                  mouseCursor: SystemMouseCursors.click,
                  onPressed: () => _showPromptDialog(context, prompt: prompt),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete',
                  mouseCursor: SystemMouseCursors.click,
                  onPressed: () => _deletePrompt(context, prompt.name),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _deletePrompt(BuildContext context, String name) async {
    final ok = await showConfirmDialog(context, title: 'Delete prompt?', message: 'Delete "$name"?');
    if (ok) await widget.state.deleteSystemPrompt(name);
  }

  Future<void> _showPromptDialog(BuildContext context, {ManagedSystemPrompt? prompt}) async {
    final isCreate = prompt == null;
    final nameCtrl = TextEditingController(text: prompt?.name ?? '');
    final contentCtrl = TextEditingController(text: prompt?.content ?? '');
    var previewMode = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final canSave = nameCtrl.text.trim().isNotEmpty && contentCtrl.text.trim().isNotEmpty;
          final theme = Theme.of(context);
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isCreate ? 'Create system prompt' : 'Edit system prompt',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          mouseCursor: SystemMouseCursors.click,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context, false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      enabled: isCreate,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'e.g. assistant-v1',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const AdminFormSectionLabel('Prompt content'),
                        const Spacer(),
                        SegmentedButton<bool>(
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Edit'),
                              icon: Icon(Icons.edit_outlined, size: 15),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('Preview'),
                              icon: Icon(Icons.visibility_outlined, size: 15),
                            ),
                          ],
                          selected: {previewMode},
                          onSelectionChanged: (s) => setState(() => previewMode = s.first),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: previewMode
                          ? _MarkdownPreview(text: contentCtrl.text)
                          : TextField(
                              controller: contentCtrl,
                              expands: true,
                              maxLines: null,
                              onChanged: (_) => setState(() {}),
                              textAlignVertical: TextAlignVertical.top,
                              decoration: const InputDecoration(
                                hintText: 'Enter system prompt text…',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.all(12),
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        AppButton(
                          label: 'Save',
                          onPressed: canSave ? () => Navigator.pop(context, true) : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (result == true) {
      await widget.state.saveSystemPrompt(
        ManagedSystemPrompt(name: nameCtrl.text.trim(), content: contentCtrl.text),
      );
    }
  }
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: text.trim().isEmpty
          ? Center(
              child: Text(
                'Nothing to preview',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: MarkdownBody(data: text),
            ),
    );
  }
}
