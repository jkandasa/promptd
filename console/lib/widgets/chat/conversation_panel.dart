import 'package:flutter/material.dart';

import '../../models/promptd_models.dart';
import '../../state/promptd_app_state.dart';
import '../common/app_ui.dart';

class ConversationPanel extends StatefulWidget {
  const ConversationPanel({super.key, required this.state, this.onSelected});

  final PromptdAppState state;
  final VoidCallback? onSelected;

  @override
  State<ConversationPanel> createState() => _ConversationPanelState();
}

class _ConversationPanelState extends State<ConversationPanel> {
  final Set<String> _selected = {};
  bool _selectMode = false;

  void _enterSelectMode() => setState(() => _selectMode = true);

  void _exitSelectMode() => setState(() {
        _selectMode = false;
        _selected.clear();
      });

  void _toggleItem(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _toggleSelectAll(List<ConversationMeta> all) {
    setState(() {
      if (_selected.length == all.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all.map((c) => c.id));
      }
    });
  }

  Future<void> _deleteSelected(BuildContext context) async {
    if (_selected.isEmpty) return;
    final ids = _selected.toList();
    final count = ids.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count conversation${count == 1 ? '' : 's'}?'),
        content: Text(
          count == 1
              ? 'This conversation will be permanently deleted.'
              : '$count conversations will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          AppButton(
            label: 'Delete',
            icon: Icons.delete_outline_rounded,
            onPressed: () => Navigator.of(ctx).pop(true),
            destructive: true,
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.state.deleteConversations(ids);
      _exitSelectMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversations = widget.state.conversations;
    final rows = _conversationRows(conversations);
    final allSelected =
        conversations.isNotEmpty && _selected.length == conversations.length;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            child: _selectMode
                ? _SelectModeHeader(
                    selectedCount: _selected.length,
                    allSelected: allSelected,
                    onToggleAll: () => _toggleSelectAll(conversations),
                    onCancel: _exitSelectMode,
                    onDelete: _selected.isEmpty
                        ? null
                        : () => _deleteSelected(context),
                  )
                : Row(
                    children: [
                      Text(
                        'Conversations',
                        style: theme.textTheme.titleMedium,
                      ),
                      const Spacer(),
                      if (conversations.isNotEmpty)
                        IconButton(
                          tooltip: 'Select conversations',
                          onPressed: _enterSelectMode,
                          icon: const Icon(
                            Icons.checklist_rounded,
                            size: 20,
                          ),
                        ),
                      IconButton.filledTonal(
                        tooltip: 'New chat',
                        onPressed: widget.state.startNewConversation,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: conversations.isEmpty
                ? const _EmptyConversations()
                : ListView.builder(
                    cacheExtent: 900,
                    padding: const EdgeInsets.all(10),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final label = row.label;
                      if (label != null) return _SectionLabel(label: label);
                      final conversation = row.conversation!;
                      return RepaintBoundary(
                        child: _ConversationTile(
                          state: widget.state,
                          conversation: conversation,
                          onSelected: widget.onSelected,
                          selectMode: _selectMode,
                          isChecked: _selected.contains(conversation.id),
                          onToggle: () => _toggleItem(conversation.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SelectModeHeader extends StatelessWidget {
  const _SelectModeHeader({
    required this.selectedCount,
    required this.allSelected,
    required this.onToggleAll,
    required this.onCancel,
    required this.onDelete,
  });

  final int selectedCount;
  final bool allSelected;
  final VoidCallback onToggleAll;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Checkbox(
          value: allSelected,
          tristate: !allSelected && selectedCount > 0,
          onChanged: (_) => onToggleAll(),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        Text(
          selectedCount == 0
              ? 'Select all'
              : '$selectedCount selected',
          style: theme.textTheme.titleMedium,
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Delete selected',
          onPressed: onDelete,
          icon: Icon(
            Icons.delete_outline_rounded,
            color: onDelete != null ? theme.colorScheme.error : null,
          ),
        ),
        IconButton(
          tooltip: 'Cancel',
          onPressed: onCancel,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

List<_ConversationRow> _conversationRows(List<ConversationMeta> conversations) {
  final rows = <_ConversationRow>[];
  final pinned = conversations.where((item) => item.pinned);
  final recent = conversations.where((item) => !item.pinned);
  var hasPinned = false;
  for (final item in pinned) {
    if (!hasPinned) {
      rows.add(const _ConversationRow.label('Pinned'));
      hasPinned = true;
    }
    rows.add(_ConversationRow.conversation(item));
  }
  var hasRecent = false;
  for (final item in recent) {
    if (!hasRecent) {
      rows.add(const _ConversationRow.label('Recent'));
      hasRecent = true;
    }
    rows.add(_ConversationRow.conversation(item));
  }
  return rows;
}

class _ConversationRow {
  const _ConversationRow.label(this.label) : conversation = null;
  const _ConversationRow.conversation(this.conversation) : label = null;

  final String? label;
  final ConversationMeta? conversation;
}

class _ConversationTile extends StatefulWidget {
  const _ConversationTile({
    required this.state,
    required this.conversation,
    this.onSelected,
    required this.selectMode,
    required this.isChecked,
    required this.onToggle,
  });

  final PromptdAppState state;
  final ConversationMeta conversation;
  final VoidCallback? onSelected;
  final bool selectMode;
  final bool isChecked;
  final VoidCallback onToggle;

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversation = widget.conversation;
    final selected = widget.state.selectedConversationId == conversation.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: widget.isChecked
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : selected
                ? theme.colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(8),
          onTap: widget.selectMode
              ? widget.onToggle
              : () async {
                  await widget.state.loadConversation(conversation.id);
                  widget.onSelected?.call();
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
            child: Row(
              children: [
                if (widget.selectMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Checkbox(
                      value: widget.isChecked,
                      onChanged: (_) => widget.onToggle(),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _conversationProviderModel(conversation),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.58),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _conversationTime(conversation),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.45),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.selectMode)
                  PopupMenuButton<String>(
                    tooltip: 'Conversation actions',
                    style: const ButtonStyle(
                      mouseCursor: WidgetStatePropertyAll(
                        WidgetStateMouseCursor.clickable,
                      ),
                    ),
                    onSelected: (value) {
                      if (value == 'pin') {
                        widget.state.togglePinConversation(conversation.id);
                      }
                      if (value == 'delete') {
                        _confirmDelete(context, conversation);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'pin',
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        child: Row(
                          children: [
                            Icon(
                              conversation.pinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                            ),
                            const SizedBox(width: 10),
                            Text(conversation.pinned ? 'Unpin' : 'Pin'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Delete',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ConversationMeta conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          '"${conversation.title}" will be permanently deleted.',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          AppButton(
            label: 'Delete',
            icon: Icons.delete_outline_rounded,
            onPressed: () => Navigator.of(ctx).pop(true),
            destructive: true,
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.state.deleteConversation(conversation.id);
    }
  }

  String _conversationProviderModel(ConversationMeta conversation) {
    final parts = [
      if ((conversation.provider ?? '').isNotEmpty) conversation.provider!,
      if ((conversation.model ?? '').isNotEmpty) conversation.model!,
    ];
    return parts.join(' · ');
  }

  String _conversationTime(ConversationMeta conversation) {
    final date = conversation.updatedAt ?? conversation.createdAt;
    if (date == null) return '';
    return _relativeTime(date);
  }

  String _relativeTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    final mins = diff.inMinutes;
    if (mins < 1) return 'just now';
    if (mins < 60) return '${mins}m ago';
    final hours = diff.inHours;
    if (hours < 24) return '${hours}h ago';
    final days = diff.inDays;
    if (days == 1) return 'yesterday';
    if (days < 7) return '${days}d ago';
    final local = date.toLocal();
    return '${_monthName(local.month)} ${local.day}';
  }

  String _monthName(int month) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return names[month - 1];
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.56),
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _EmptyConversations extends StatelessWidget {
  const _EmptyConversations();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      title: 'No conversations yet',
      message: 'Start a new chat to keep history here.',
      icon: Icons.chat_bubble_outline_rounded,
    );
  }
}
