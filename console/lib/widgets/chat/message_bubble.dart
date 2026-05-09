import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../../models/promptd_models.dart';
import 'trace_details_dialog.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onDelete,
    required this.onEdit,
  });

  final ChatMessage message;
  final Future<void> Function(ChatMessage message) onDelete;
  final Future<void> Function(ChatMessage message, String content) onEdit;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _editing = false;
  late final TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.message.content);
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final theme = Theme.of(context);
    final isUser = message.role == 'user';
    final isError = message.role == 'error';
    final isCompact = message.compactSummary;
    final color = isCompact
        ? theme.colorScheme.primaryContainer
        : isError
        ? theme.colorScheme.errorContainer
        : isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerLowest;
    final foreground = isUser && !isCompact
        ? Colors.white
        : theme.colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: isUser && !isCompact
                    ? null
                    : Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _editing
                    ? _editForm(context)
                    : _content(context, foreground),
              ),
            ),
            if (!_editing) ...[
              const SizedBox(height: 4),
              _MessageActions(
                message: message,
                onCopy: _copyMessage,
                onEdit: message.role == 'user' && !message.compactSummary
                    ? () => setState(() => _editing = true)
                    : null,
                onDelete: () => _confirmDelete(context),
              ),
              _MessageMeta(message: message),
            ],
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, Color foreground) {
    final message = widget.message;
    final theme = Theme.of(context);
    final isError = message.role == 'error';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _roleIcon(message.role),
              size: 16,
              color: isError ? theme.colorScheme.error : foreground,
            ),
            const SizedBox(width: 6),
            Text(
              message.compactSummary
                  ? 'Compacted summary'
                  : _roleLabel(message.role),
              style: theme.textTheme.labelLarge?.copyWith(
                color: isError ? theme.colorScheme.error : foreground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (message.pending)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (message.role == 'assistant')
          MarkdownBody(
            data: message.content,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyLarge?.copyWith(
                color: foreground,
                height: 1.55,
              ),
              code: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              codeblockDecoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: theme.colorScheme.primary, width: 3),
                ),
              ),
            ),
          )
        else
          SelectableText(
            message.content,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isError ? theme.colorScheme.onErrorContainer : foreground,
              height: 1.55,
            ),
          ),
      ],
    );
  }

  Widget _editForm(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _editController,
          autofocus: true,
          minLines: 4,
          maxLines: 12,
          decoration: const InputDecoration(labelText: 'Edit message'),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _editing = false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _submitEdit,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submitEdit() async {
    final content = _editController.text.trim();
    if (content.isEmpty) return;
    setState(() => _editing = false);
    await widget.onEdit(widget.message, content);
  }

  Future<void> _copyMessage() async {
    await Clipboard.setData(ClipboardData(text: widget.message.content));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onDelete(widget.message);
  }

  IconData _roleIcon(String role) {
    return switch (role) {
      'user' => Icons.person_outline_rounded,
      'error' => Icons.error_outline_rounded,
      _ => Icons.auto_awesome_rounded,
    };
  }

  String _roleLabel(String role) {
    return switch (role) {
      'user' => 'You',
      'error' => 'Error',
      _ => 'Promptd',
    };
  }
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.message,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  final ChatMessage message;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: 'Copy message',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          onPressed: message.pending ? null : onCopy,
          icon: const Icon(Icons.copy_rounded),
        ),
        IconButton(
          tooltip: 'Edit message',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          onPressed: message.pending ? null : onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Delete message',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          onPressed: message.pending ? null : onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

class _MessageMeta extends StatelessWidget {
  const _MessageMeta({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          _formatTime(message.sentAt),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
          ),
        ),
        if (message.provider?.isNotEmpty == true ||
            message.model?.isNotEmpty == true)
          Text(
            [
              message.provider,
              message.model,
            ].where((item) => item?.isNotEmpty == true).join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
        if (message.timeTakenMs != null)
          Text(
            message.timeTakenMs! < 1000
                ? '${message.timeTakenMs}ms'
                : '${(message.timeTakenMs! / 1000).toStringAsFixed(1)}s',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
        if (message.llmCalls != null)
          TextButton(
            onPressed: message.trace.isEmpty
                ? null
                : () => showTraceDetailsDialog(context, message.trace),
            style: _metaButtonStyle(),
            child: Text(
              '${message.llmCalls} LLM call${message.llmCalls == 1 ? '' : 's'}',
            ),
          ),
        if (message.toolCalls != null)
          Text(
            '${message.toolCalls} tool call${message.toolCalls == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
        if (message.trace.isNotEmpty) _TokenSummary(trace: message.trace),
      ],
    );
  }

  ButtonStyle _metaButtonStyle() {
    return TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  String _formatTime(DateTime date) {
    final local = date.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _TokenSummary extends StatelessWidget {
  const _TokenSummary({required this.trace});

  final List<Map<String, dynamic>> trace;

  @override
  Widget build(BuildContext context) {
    var prompt = 0;
    var completion = 0;
    var reasoning = 0;
    var cached = 0;
    for (final round in trace) {
      final usage = round['usage'];
      if (usage is! Map<String, dynamic>) continue;
      prompt += usage['prompt_tokens'] as int? ?? 0;
      completion += usage['completion_tokens'] as int? ?? 0;
      reasoning += usage['reasoning_tokens'] as int? ?? 0;
      cached += usage['cached_tokens'] as int? ?? 0;
    }
    if (prompt == 0 && completion == 0) return const SizedBox.shrink();
    final extra = [
      if (reasoning > 0) '$reasoning reasoning',
      if (cached > 0) '$cached cached',
    ].join(', ');
    final color = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.58);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.arrow_upward_rounded, size: 13, color: color),
        Text(
          '$prompt',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
        const SizedBox(width: 4),
        Icon(Icons.arrow_downward_rounded, size: 13, color: color),
        Text(
          '$completion tok${extra.isEmpty ? '' : ' ($extra)'}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
