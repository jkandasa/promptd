part of 'trace_details_dialog.dart';

// Collapsible inline section (lighter weight than _TraceSection).
class _InlineExpansion extends StatefulWidget {
  const _InlineExpansion({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_InlineExpansion> createState() => _InlineExpansionState();
}

class _InlineExpansionState extends State<_InlineExpansion> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(6),
          mouseCursor: SystemMouseCursors.click,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(padding: const EdgeInsets.only(top: 4), child: widget.child),
      ],
    );
  }
}

class _ContentBlock extends StatefulWidget {
  const _ContentBlock({
    required this.content,
    this.label,
    this.compact = false,
    this.backgroundColor,
    this.markdownEnabled = false,
  });

  final String content;
  final String? label;
  final bool compact;
  final Color? backgroundColor;
  final bool markdownEnabled;

  @override
  State<_ContentBlock> createState() => _ContentBlockState();
}

class _ContentBlockState extends State<_ContentBlock> {
  static const _previewLines = 8;
  bool _expanded = false;
  bool _copied = false;
  late _ContentPreview _preview = _ContentPreview.from(widget.content);

  @override
  void didUpdateWidget(covariant _ContentBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _expanded = false;
      _preview = _ContentPreview.from(widget.content);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canCollapse = _preview.lineCount > _previewLines + 2;
    final displayed = canCollapse && !_expanded ? _preview.preview : widget.content;
    final textStyle = theme.textTheme.bodySmall?.copyWith(fontSize: 13, height: 1.55);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.label!.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
        ],
        Container(
          width: double.infinity,
          margin: EdgeInsets.only(top: widget.compact || widget.label != null ? 2 : 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: widget.backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 7, 38, 7),
                    child: widget.markdownEnabled
                        ? _buildMarkdown(theme, displayed, textStyle)
                        : SelectableText(displayed, style: textStyle),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: IconButton(
                      tooltip: _copied ? 'Copied' : 'Copy',
                      iconSize: 15,
                      visualDensity: VisualDensity.compact,
                      mouseCursor: SystemMouseCursors.click,
                      onPressed: _copy,
                      icon: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        color: _copied ? theme.colorScheme.primary : null,
                      ),
                    ),
                  ),
                ],
              ),
              if (canCollapse)
                InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _expanded
                              ? 'Show less'
                              : '${_preview.lineCount - _previewLines} more lines',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 13,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMarkdown(ThemeData theme, String data, TextStyle? textStyle) {
    Color? textColor = theme.brightness == Brightness.dark ? Colors.white : null;
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: textStyle?.copyWith(color: textColor),
        h1: theme.textTheme.titleLarge?.copyWith(color: textColor),
        h2: theme.textTheme.titleMedium?.copyWith(color: textColor),
        h3: theme.textTheme.titleSmall?.copyWith(color: textColor),
        listBullet: textStyle?.copyWith(color: textColor),
        blockSpacing: 8,
        code: textStyle?.copyWith(
          color: textColor,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
        ),
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.content));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }
}

class _ContentPreview {
  const _ContentPreview({required this.preview, required this.lineCount});

  final String preview;
  final int lineCount;

  static _ContentPreview from(String content) {
    const maxLines = _ContentBlockState._previewLines;
    final buffer = StringBuffer();
    var lineCount = 1;
    var copiedLines = 1;

    for (var i = 0; i < content.length; i++) {
      final char = content.codeUnitAt(i);
      if (char == 10) {
        lineCount++;
        if (copiedLines < maxLines) {
          buffer.writeCharCode(char);
          copiedLines++;
        }
        continue;
      }
      if (copiedLines <= maxLines) buffer.writeCharCode(char);
    }

    return _ContentPreview(
      preview: buffer.toString(),
      lineCount: content.isEmpty ? 0 : lineCount,
    );
  }
}

class _EmptyTraceText extends StatelessWidget {
  const _EmptyTraceText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
