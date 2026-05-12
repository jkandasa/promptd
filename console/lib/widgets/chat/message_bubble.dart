import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _submittingEdit = false;
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
        ? _softErrorColor(theme)
        : isUser
        ? _userBubbleColor(theme)
        : theme.colorScheme.surfaceContainerLowest;
    final foreground = theme.colorScheme.onSurface;
    final borderColor = isError
        ? _softErrorBorderColor(theme)
        : isCompact
        ? _compactBorderColor(theme)
        : isUser && !_editing
        ? _userBorderColor(theme)
        : theme.colorScheme.outlineVariant;

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
    final errorAccent = _softErrorAccentColor(theme);
    final compactAccent = _compactAccentColor(theme);
    final userAccent = _userAccentColor(theme);

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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: compactAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: compactAccent.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  'Compacted summary',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: compactAccent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              )
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
              data: message.content,
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
            ),
          )
        else
          RepaintBoundary(
            child: SelectableText(
              message.content,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: foreground,
                height: 1.55,
              ),
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
              FilledButton.icon(
                onPressed: _submittingEdit ? null : _submitEdit,
                icon: _submittingEdit
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Send'),
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

Color _softErrorColor(ThemeData theme) {
  return Color.lerp(
    theme.colorScheme.surface,
    theme.colorScheme.error,
    theme.brightness == Brightness.dark ? 0.16 : 0.08,
  )!;
}

Color _softErrorBorderColor(ThemeData theme) {
  return theme.colorScheme.error.withValues(
    alpha: theme.brightness == Brightness.dark ? 0.34 : 0.22,
  );
}

Color _softErrorAccentColor(ThemeData theme) {
  return Color.lerp(
    theme.colorScheme.error,
    theme.colorScheme.onSurface,
    theme.brightness == Brightness.dark ? 0.18 : 0.08,
  )!;
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

class _MessageFiles extends StatelessWidget {
  const _MessageFiles({required this.files, required this.loadFileBytes});

  final List<UploadedFile> files;
  final Future<Uint8List> Function(String url) loadFileBytes;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final file in files)
          file.isImage
              ? _ImageAttachment(file: file, loadFileBytes: loadFileBytes)
              : _FileAttachment(file: file, loadFileBytes: loadFileBytes),
      ],
    );
  }
}

class _FileAttachment extends StatefulWidget {
  const _FileAttachment({required this.file, required this.loadFileBytes});

  final UploadedFile file;
  final Future<Uint8List> Function(String url) loadFileBytes;

  @override
  State<_FileAttachment> createState() => _FileAttachmentState();
}

class _FileAttachmentState extends State<_FileAttachment> {
  Future<Uint8List>? _bytesFuture;

  Future<Uint8List> _bytes() {
    return _bytesFuture ??= widget.loadFileBytes(widget.file.url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewable = _canPreviewFile(widget.file);
    return Container(
      width: 320,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(_fileIcon(widget.file), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.file.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  _fmtFileSize(widget.file.size),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          ),
          if (previewable)
            IconButton(
              tooltip: 'Preview file',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showPreview(context),
              icon: const Icon(Icons.visibility_outlined, size: 18),
            ),
          IconButton(
            tooltip: 'Download file',
            visualDensity: VisualDensity.compact,
            onPressed: () => _download(context),
            icon: const Icon(Icons.download_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  void _showPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
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
                      tooltip: 'Download file',
                      onPressed: () => _download(context),
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
                  child: FutureBuilder<Uint8List>(
                    future: _bytes(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError || snapshot.data == null) {
                        return _FilePreviewMessage(
                          message: 'Unable to load preview',
                          filename: widget.file.filename,
                        );
                      }
                      if (_isPdfFile(widget.file)) {
                        return _FilePreviewMessage(
                          message:
                              'PDF preview is not embedded yet. Use download to open it with your system PDF viewer.',
                          filename: widget.file.filename,
                        );
                      }
                      final text = _decodePreviewText(snapshot.data!);
                      if (text == null) {
                        return _FilePreviewMessage(
                          message: 'Preview is not available for this file',
                          filename: widget.file.filename,
                        );
                      }
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            text,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontFamily: 'monospace',
                                  height: 1.45,
                                ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _download(BuildContext context) async {
    try {
      final bytes = await _bytes();
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
            ? RepaintBoundary(
                child: SvgPicture.memory(
                  snapshot.data!,
                  width: imageWidth,
                  height: 260,
                  fit: BoxFit.contain,
                ),
              )
            : RepaintBoundary(
                child: Image.memory(
                  snapshot.data!,
                  width: imageWidth,
                  height: 260,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      _ImageError(filename: widget.file.filename),
                ),
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

class _FilePreviewMessage extends StatelessWidget {
  const _FilePreviewMessage({required this.message, required this.filename});

  final String message;
  final String filename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_fileIconName(filename), size: 34),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              filename,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _canPreviewFile(UploadedFile file) {
  return _isPdfFile(file) || _isTextFile(file);
}

bool _isPdfFile(UploadedFile file) {
  final type = file.contentType?.toLowerCase() ?? '';
  return type == 'application/pdf' ||
      file.filename.toLowerCase().endsWith('.pdf');
}

bool _isTextFile(UploadedFile file) {
  final type = file.contentType?.toLowerCase() ?? '';
  if (type.startsWith('text/')) return true;
  const extensions = [
    '.txt',
    '.md',
    '.json',
    '.csv',
    '.log',
    '.yaml',
    '.yml',
    '.xml',
    '.html',
    '.css',
    '.js',
    '.ts',
    '.dart',
    '.go',
    '.py',
    '.rs',
    '.java',
    '.kt',
    '.sh',
  ];
  final name = file.filename.toLowerCase();
  return extensions.any(name.endsWith);
}

String? _decodePreviewText(Uint8List bytes) {
  if (bytes.length > 1024 * 1024) {
    return 'Preview is limited to files up to 1 MB. Use download for this file.';
  }
  try {
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  }
}

IconData _fileIcon(UploadedFile file) => _fileIconName(file.filename);

IconData _fileIconName(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (lower.endsWith('.csv')) return Icons.table_chart_outlined;
  if (lower.endsWith('.zip') ||
      lower.endsWith('.tar') ||
      lower.endsWith('.gz')) {
    return Icons.folder_zip_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

String _fmtFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
