import 'package:flutter/material.dart';

import '../../models/promptd_models.dart';
import '../../state/promptd_app_state.dart';

class ConversationPanel extends StatelessWidget {
  const ConversationPanel({super.key, required this.state, this.onSelected});

  final PromptdAppState state;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pinned = state.conversations.where((item) => item.pinned).toList();
    final recent = state.conversations.where((item) => !item.pinned).toList();

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
                : ListView(
                    padding: const EdgeInsets.all(10),
                    children: [
                      if (pinned.isNotEmpty) ...[
                        _SectionLabel(label: 'Pinned'),
                        for (final item in pinned)
                          _ConversationTile(
                            state: state,
                            conversation: item,
                            onSelected: onSelected,
                          ),
                      ],
                      if (recent.isNotEmpty) ...[
                        _SectionLabel(label: 'Recent'),
                        for (final item in recent)
                          _ConversationTile(
                            state: state,
                            conversation: item,
                            onSelected: onSelected,
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.state,
    required this.conversation,
    this.onSelected,
  });

  final PromptdAppState state;
  final ConversationMeta conversation;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = state.selectedConversationId == conversation.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            await state.loadConversation(conversation.id);
            onSelected?.call();
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
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.58,
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _conversationTime(conversation),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.45,
                          ),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Conversation actions',
                  onSelected: (value) {
                    if (value == 'pin') {
                      state.togglePinConversation(conversation.id);
                    }
                    if (value == 'delete') {
                      state.deleteConversation(conversation.id);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'pin',
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
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded),
                          SizedBox(width: 10),
                          Text('Delete'),
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

  String _conversationProviderModel(ConversationMeta conversation) {
    final provider = conversation.provider ?? '';
    final model = conversation.model ?? '';
    final parts = [
      if (provider.isNotEmpty) provider,
      if (model.isNotEmpty) model,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No conversations yet',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
