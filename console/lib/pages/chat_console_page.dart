import 'package:flutter/material.dart';

import '../state/promptd_app_state.dart';
import '../widgets/chat/chat_workspace.dart';
import '../widgets/chat/conversation_panel.dart';

class ChatConsolePage extends StatefulWidget {
  const ChatConsolePage({super.key, required this.state});

  final PromptdAppState state;

  @override
  State<ChatConsolePage> createState() => _ChatConsolePageState();
}

class _ChatConsolePageState extends State<ChatConsolePage> {
  double _historyWidth = 300;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;

        if (wide) {
          final historyWidth = _historyWidth.clamp(
            240.0,
            (constraints.maxWidth * 0.45).clamp(240.0, 520.0),
          );
          return Row(
            children: [
              SizedBox(
                width: historyWidth,
                child: ConversationPanel(state: widget.state),
              ),
              _SplitHandle(
                direction: Axis.horizontal,
                onDrag: (delta) {
                  setState(() {
                    _historyWidth = (_historyWidth + delta).clamp(
                      240.0,
                      (constraints.maxWidth * 0.45).clamp(240.0, 520.0),
                    );
                  });
                },
              ),
              Expanded(child: ChatWorkspace(state: widget.state)),
            ],
          );
        }

        return ChatWorkspace(
          state: widget.state,
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
            state: widget.state,
            onSelected: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

class _SplitHandle extends StatelessWidget {
  const _SplitHandle({required this.direction, required this.onDrag});

  final Axis direction;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final horizontal = direction == Axis.horizontal;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: horizontal
            ? (details) => onDrag(details.delta.dx)
            : null,
        onVerticalDragUpdate: horizontal
            ? null
            : (details) => onDrag(details.delta.dy),
        child: SizedBox(
          width: horizontal ? 16 : double.infinity,
          height: horizontal ? double.infinity : 16,
          child: Center(
            child: Container(
              width: horizontal ? 4 : 44,
              height: horizontal ? 44 : 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
