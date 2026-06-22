import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/promptd_models.dart';
import '../../services/file_downloader.dart';
import '../../theme/app_theme.dart';

class MessageFiles extends StatelessWidget {
  const MessageFiles({super.key, required this.files, required this.loadFileBytes});

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
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            text,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: AppTheme.codeFontFamily,
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded $savedTo')));
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $err')));
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
    final imageWidth = (MediaQuery.sizeOf(context).width - 56).clamp(220.0, 360.0);
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
      mouseCursor: SystemMouseCursors.click,
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
                              if (snapshot.connectionState != ConnectionState.done) {
                                return const CircularProgressIndicator();
                              }
                              if (snapshot.hasError || snapshot.data == null) {
                                return _ImageError(filename: widget.file.filename);
                              }
                              return SvgPicture.memory(snapshot.data!, fit: BoxFit.contain);
                            },
                          )
                        : FutureBuilder<Uint8List>(
                            future: _bytesFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState != ConnectionState.done) {
                                return const CircularProgressIndicator();
                              }
                              if (snapshot.hasError || snapshot.data == null) {
                                return _ImageError(filename: widget.file.filename);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded $savedTo')));
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $err')));
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

bool _canPreviewFile(UploadedFile file) => _isPdfFile(file) || _isTextFile(file);

bool _isPdfFile(UploadedFile file) {
  final type = file.contentType?.toLowerCase() ?? '';
  return type == 'application/pdf' || file.filename.toLowerCase().endsWith('.pdf');
}

bool _isTextFile(UploadedFile file) {
  final type = file.contentType?.toLowerCase() ?? '';
  if (type.startsWith('text/')) return true;
  const extensions = [
    '.txt', '.md', '.json', '.csv', '.log', '.yaml', '.yml', '.xml',
    '.html', '.css', '.js', '.ts', '.dart', '.go', '.py', '.rs', '.java',
    '.kt', '.sh',
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
  if (lower.endsWith('.zip') || lower.endsWith('.tar') || lower.endsWith('.gz')) {
    return Icons.folder_zip_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

String _fmtFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
