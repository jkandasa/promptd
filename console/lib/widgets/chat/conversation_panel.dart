import 'package:flutter/material.dart';

import '../../models/promptd_models.dart';
import '../../state/promptd_app_state.dart';
import '../common/app_ui.dart';

class ConversationPanel extends StatelessWidget {
  const ConversationPanel({super.key, required this.state, this.onSelected});

  final PromptdAppState state;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _conversationRows(state.conversations);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Text('Conversations', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: 'New chat',
                  onPressed: state.startNewConversation,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: state.conversations.isEmpty
                ? const _EmptyConversations()
                : ListView.builder(
                    cacheExtent: 900,
                    padding: const EdgeInsets.all(10),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final label = row.label;
                      if (label != null) return _SectionLabel(label: label);
                      return RepaintBoundary(
                        child: _ConversationTile(
                          state: state,
                          conversation: row.conversation!,
                          onSelected: onSelected,
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
  });

  final PromptdAppState state;
  final ConversationMeta conversation;
  final VoidCallback? onSelected;

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
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            await widget.state.loadConversation(conversation.id);
            widget.onSelected?.call();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
            child: Row(
              children: [
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
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _conversationTime(conversation),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Conversation actions',
                  style: const ButtonStyle(
                    mouseCursor: WidgetStatePropertyAll(WidgetStateMouseCursor.clickable),
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
                          Icon(conversation.pinned ? Icons.push_pin : Icons.push_pin_outlined),
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
                          Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                          const SizedBox(width: 10),
                          Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
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

  Future<void> _confirmDelete(BuildContext context, ConversationMeta conversation) async {
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
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.56),
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
