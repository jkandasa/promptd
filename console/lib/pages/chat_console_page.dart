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
        final showHistory = constraints.maxWidth >= 1100;

        return Row(
          children: [
            if (showHistory)
              SizedBox(width: 300, child: ConversationPanel(state: state)),
            if (showHistory) const SizedBox(width: 16),
            Expanded(child: ChatWorkspace(state: state)),
          ],
        );
      },
    );
  }
}
