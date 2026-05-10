import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/promptd_models.dart';
import '../../services/file_downloader.dart';
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
    final color = _editing
        ? theme.colorScheme.surfaceContainerLowest
        : isCompact
        ? theme.colorScheme.primaryContainer
        : isError
        ? theme.colorScheme.errorContainer
        : isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerLowest;
    final foreground = isUser && !isCompact && !_editing
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
                border: isUser && !isCompact && !_editing
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
            if (!_editing && message.files.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MessageFiles(
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
    final width = (MediaQuery.sizeOf(context).width - 64).clamp(260.0, 640.0);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _editController,
            autofocus: true,
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
                onPressed: () => setState(() => _editing = false),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: _submitEdit,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
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
    final theme = Theme.of(context);
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
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
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

class _MessageFiles extends StatelessWidget {
  const _MessageFiles({required this.files, required this.loadFileBytes});

  final List<UploadedFile> files;
  final Future<Uint8List> Function(String url) loadFileBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final file in files)
          file.isImage
              ? _ImageAttachment(file: file, loadFileBytes: loadFileBytes)
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        file.filename,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
      ],
    );
  }
}

class _ImageAttachment extends StatefulWidget {
  const _ImageAttachment({required this.file, required this.loadFileBytes});

  final UploadedFile file;
  final Future<Uint8List> Function(String url) loadFileBytes;

  @override
  State<_ImageAttachment> createState() => _ImageAttachmentState();
}

class _ImageAttachmentState extends State<_ImageAttachment> {
  late final Future<Uint8List> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = widget.loadFileBytes(widget.file.url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageWidth = (MediaQuery.sizeOf(context).width - 56).clamp(
      220.0,
      360.0,
    );
    final image = FutureBuilder<Uint8List>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: imageWidth,
            height: 220,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _ImageError(filename: widget.file.filename);
        }
        return widget.file.isSvg
            ? SvgPicture.memory(
                snapshot.data!,
                width: imageWidth,
                height: 260,
                fit: BoxFit.contain,
              )
            : Image.memory(
                snapshot.data!,
                width: imageWidth,
                height: 260,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    _ImageError(filename: widget.file.filename),
              );
      },
    );

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showImagePreview(context),
      child: Container(
        constraints: BoxConstraints(maxWidth: imageWidth),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                image,
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filledTonal(
                    tooltip: 'Download image',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _downloadImage(context),
                    icon: const Icon(Icons.download_rounded, size: 18),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Text(
                widget.file.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.file.filename,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Download image',
                      onPressed: () => _downloadImage(context),
                      icon: const Icon(Icons.download_rounded),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Flexible(
                  child: Center(
                    child: widget.file.isSvg
                        ? FutureBuilder<Uint8List>(
                            future: _bytesFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState !=
                                  ConnectionState.done) {
                                return const CircularProgressIndicator();
                              }
                              if (snapshot.hasError || snapshot.data == null) {
                                return _ImageError(
                                  filename: widget.file.filename,
                                );
                              }
                              return SvgPicture.memory(
                                snapshot.data!,
                                fit: BoxFit.contain,
                              );
                            },
                          )
                        : FutureBuilder<Uint8List>(
                            future: _bytesFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState !=
                                  ConnectionState.done) {
                                return const CircularProgressIndicator();
                              }
                              if (snapshot.hasError || snapshot.data == null) {
                                return _ImageError(
                                  filename: widget.file.filename,
                                );
                              }
                              return Image.memory(
                                snapshot.data!,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    _ImageError(filename: widget.file.filename),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadImage(BuildContext context) async {
    try {
      final bytes = await _bytesFuture;
      final savedTo = await saveDownloadedFile(
        bytes: bytes,
        filename: widget.file.filename,
        contentType: widget.file.contentType,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Downloaded $savedTo')));
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $err')));
    }
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError({required this.filename});

  final String filename;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 160,
      child: Center(
        child: Text(
          'Unable to load $filename',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
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
