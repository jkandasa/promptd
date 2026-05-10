import 'package:flutter/material.dart';

import '../state/promptd_app_state.dart';
import '../widgets/chat/chat_workspace.dart';
import '../widgets/chat/conversation_panel.dart';

class ChatConsolePage extends StatelessWidget {
  const ChatConsolePage({super.key, required this.state});

  final PromptdAppState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;

        if (wide) {
          return Row(
            children: [
              SizedBox(width: 300, child: ConversationPanel(state: state)),
              const SizedBox(width: 16),
              Expanded(child: ChatWorkspace(state: state)),
            ],
          );
        }

        return ChatWorkspace(
          state: state,
          leading: Builder(
            builder: (context) => IconButton.filledTonal(
              tooltip: 'Conversation history',
              onPressed: () => _showHistory(context),
              icon: const Icon(Icons.history_rounded),
            ),
          ),
        );
      },
    );
  }

  void _showHistory(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ConversationPanel(
            state: state,
            onSelected: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}
