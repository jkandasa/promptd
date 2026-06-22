import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/promptd_models.dart';
import '../../theme/app_theme.dart';
import '../common/app_ui.dart';
import 'message_attachments.dart';
import 'trace_details_dialog.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onDelete,
    required this.onEdit,
    required this.loadFileBytes,
  });

  final ChatMessage message;
  final Future<void> Function(ChatMessage message) onDelete;
  final Future<void> Function(ChatMessage message, String content) onEdit;
  final Future<Uint8List> Function(String url) loadFileBytes;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

// Messages longer than this are collapsed by default.
const int _collapseThreshold = 5000;
// Number of characters shown in collapsed mode.
const int _collapseLength = 4000;

class _MessageBubbleState extends State<MessageBubble> {
  bool _editing = false;
  bool _submittingEdit = false;
  bool _expanded = false;
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
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.message.content != widget.message.content) {
      _editController.text = widget.message.content;
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final theme = Theme.of(context);
    final isUser = message.role == 'user';
    final isError = message.role == 'error';
    final isCompact = message.compactSummary;
    final color = _editing
        ? theme.colorScheme.surfaceContainerLowest
        : isCompact
        ? _compactBubbleColor(theme)
        : isError
        ? appToneFill(theme, AppTone.danger)
        : isUser
        ? _userBubbleColor(theme)
        : theme.colorScheme.surfaceContainerLowest;
    final foreground = theme.colorScheme.onSurface;
    final borderColor = isError
        ? appToneBorderColor(theme, AppTone.danger)
        : isCompact
        ? _compactBorderColor(theme)
        : isUser && !_editing
        ? _userBorderColor(theme)
        : theme.colorScheme.outlineVariant;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isUser ? 860 : double.infinity),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Stack(
                children: [
                  if (isCompact && !_editing)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 5,
                        decoration: BoxDecoration(
                          color: _compactAccentColor(theme),
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isCompact && !_editing ? 19 : 14,
                      14,
                      14,
                      14,
                    ),
                    child: _editing
                        ? _editForm(context)
                        : _content(context, foreground),
                  ),
                ],
              ),
            ),
            if (!_editing && message.files.isNotEmpty) ...[
              const SizedBox(height: 8),
              MessageFiles(
                files: message.files,
                loadFileBytes: widget.loadFileBytes,
              ),
            ],
            if (!_editing) ...[
              const SizedBox(height: 4),
              _MessageActions(
                message: message,
                onCopy: _copyMessage,
                onEdit: message.role == 'user' && !message.compactSummary
                    ? _startEdit
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
    final isCompact = message.compactSummary;
    final isUser = message.role == 'user';
    final errorAccent = appToneColor(theme, AppTone.danger);
    final compactAccent = _compactAccentColor(theme);
    final userAccent = _userAccentColor(theme);

    final isLong = message.content.length > _collapseThreshold;
    final displayContent = isLong && !_expanded
        ? '${message.content.substring(0, _collapseLength)}…'
        : message.content;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _roleIcon(message.role),
              size: 16,
              color: isError
                  ? errorAccent
                  : isCompact
                  ? compactAccent
                  : isUser
                  ? userAccent
                  : foreground,
            ),
            const SizedBox(width: 6),
            if (isCompact)
              const AppPill(label: 'Compacted summary', tone: AppTone.warning)
            else
              Text(
                _roleLabel(message.role),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isError
                      ? errorAccent
                      : isUser
                      ? userAccent
                      : foreground,
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
          RepaintBoundary(
            child: MarkdownBody(
              data: displayContent,
              // Render each block as a SelectableText so multi-line and
              // multi-paragraph selection works reliably. flutter_markdown lays
              // inline spans out in a Wrap, which an ancestor SelectionArea
              // cannot extend a selection across line-by-line.
              selectable: true,
              onTapLink: (text, href, title) => _openLink(href),
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                a: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  height: 1.55,
                ),
                p: theme.textTheme.bodyLarge?.copyWith(
                  color: foreground,
                  height: 1.55,
                ),
                code: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: AppTheme.codeFontFamily,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                codeblockDecoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          RepaintBoundary(
            child: SelectableText(
              displayContent,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: foreground,
                height: 1.55,
              ),
            ),
          ),
        if (isLong) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 18,
            ),
            label: Text(_expanded ? 'Show less' : 'Show more'),
          ),
        ],
      ],
    );
  }

  Widget _editForm(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 64).clamp(260.0, 640.0);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _editController,
            style: Theme.of(context).textTheme.bodyLarge,
            autofocus: true,
            enabled: !_submittingEdit,
            minLines: 4,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Edit message',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _submittingEdit ? null : _cancelEdit,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel'),
              ),
              AppButton(
                label: 'Send',
                icon: Icons.send_rounded,
                onPressed: _submitEdit,
                loading: _submittingEdit,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _startEdit() {
    _editController.text = widget.message.content;
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    _editController.text = widget.message.content;
    setState(() => _editing = false);
  }

  Future<void> _submitEdit() async {
    final content = _editController.text.trim();
    if (content.isEmpty) return;
    setState(() => _submittingEdit = true);
    try {
      await widget.onEdit(widget.message, content);
    } finally {
      if (mounted) {
        setState(() {
          _editing = false;
          _submittingEdit = false;
        });
      }
    }
  }

  Future<void> _copyMessage() async {
    await Clipboard.setData(ClipboardData(text: widget.message.content));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  Future<void> _openLink(String? href) async {
    if (href == null || href.isEmpty) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete message?',
      confirmIcon: Icons.delete_outline_rounded,
    );
    if (confirmed) await widget.onDelete(widget.message);
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

Color _userBubbleColor(ThemeData theme) {
  return Color.lerp(
    theme.colorScheme.surface,
    theme.colorScheme.primary,
    theme.brightness == Brightness.dark ? 0.22 : 0.1,
  )!;
}

Color _userBorderColor(ThemeData theme) {
  return theme.colorScheme.primary.withValues(
    alpha: theme.brightness == Brightness.dark ? 0.38 : 0.2,
  );
}

Color _userAccentColor(ThemeData theme) {
  return Color.lerp(
    theme.colorScheme.primary,
    theme.colorScheme.onSurface,
    theme.brightness == Brightness.dark ? 0.14 : 0.04,
  )!;
}

Color _compactBubbleColor(ThemeData theme) {
  if (theme.brightness == Brightness.dark) {
    return Color.lerp(
      theme.colorScheme.surface,
      const Color(0xfffaad14),
      0.22,
    )!;
  }
  return const Color(0xfffff7e6);
}

Color _compactBorderColor(ThemeData theme) {
  if (theme.brightness == Brightness.dark) {
    return const Color(0xfffaad14).withValues(alpha: 0.48);
  }
  return const Color(0xffffd591);
}

Color _compactAccentColor(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? const Color(0xffffc53d)
      : const Color(0xffad6800);
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
    final theme = Theme.of(context);
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
        if (onEdit != null)
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
          color: theme.colorScheme.error.withValues(alpha: 0.72),
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
        Tooltip(
          message: _formatDateTime(message.sentAt),
          child: Text(
            _formatTime(message.sentAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
            ),
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
    ).copyWith(
      mouseCursor: const WidgetStatePropertyAll(
        WidgetStateMouseCursor.clickable,
      ),
    );
  }

  String _formatTime(DateTime date) {
    final local = date.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
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
