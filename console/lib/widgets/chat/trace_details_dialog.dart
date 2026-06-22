import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../common/app_ui.dart';

part 'trace_content_block.dart';
part 'trace_tool_widgets.dart';
part 'trace_token_widgets.dart';

const _traceBlue = Color(0xff1677ff);
const _traceGreen = Color(0xff52c41a);
const _traceOrange = Color(0xfffa8c16);
const _traceYellow = Color(0xfffaad14);
const _traceMuted = Color(0xff8c8c8c);

Future<void> showTraceDetailsDialog(
  BuildContext context,
  List<Map<String, dynamic>> trace,
) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        SelectionArea(child: TraceDetailsDialog(trace: trace)),
  );
}

class TraceDetailsDialog extends StatefulWidget {
  const TraceDetailsDialog({super.key, required this.trace});

  final List<Map<String, dynamic>> trace;

  @override
  State<TraceDetailsDialog> createState() => _TraceDetailsDialogState();
}

class _TraceDetailsDialogState extends State<TraceDetailsDialog> {
  bool _markdownEnabled = false;

  @override
  Widget build(BuildContext context) {
    final totals = _TraceTotals.from(widget.trace);
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final isSmallScreen = size.width < 400;

    return Dialog(
      insetPadding: EdgeInsets.all(isSmallScreen ? 8 : 18),
      child: SizedBox(
        width: isSmallScreen ? size.width * 0.96 : size.width * 0.92,
        height: isSmallScreen ? size.height * 0.92 : size.height * 0.86,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 520;
                  final title = Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('LLM Trace'),
                      Chip(
                        label: Text(
                          '${widget.trace.length} round${widget.trace.length == 1 ? '' : 's'}',
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  );
                  final toggle = _MarkdownToggle(
                    enabled: _markdownEnabled,
                    onToggle: (v) => setState(() => _markdownEnabled = v),
                  );
                  final closeBtn = IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    mouseCursor: SystemMouseCursors.click,
                    icon: const Icon(Icons.close_rounded),
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (compact)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [Expanded(child: title), closeBtn],
                            ),
                            toggle,
                          ],
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: title),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [toggle, closeBtn],
                            ),
                          ],
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          _InlineMetric(
                            icon: Icons.bolt_rounded,
                            label: 'LLM ${_fmtMs(totals.llmMs)}',
                            color: theme.colorScheme.primary,
                          ),
                          if (totals.toolMs > 0)
                            _InlineMetric(
                              icon: Icons.build_circle_outlined,
                              label:
                                  'Tools ${_fmtMs(totals.toolMs)} · ${totals.toolCalls} call${totals.toolCalls == 1 ? '' : 's'}',
                              color: theme.colorScheme.tertiary,
                            ),
                          if (totals.prompt + totals.completion > 0)
                            _HeaderTokenMetric(
                              prompt: totals.prompt,
                              completion: totals.completion,
                              reasoning: totals.reasoning,
                              cached: totals.cached,
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.trace.isEmpty
                  ? const Center(child: Text('No trace data available'))
                  : ListView.separated(
                      cacheExtent: 900,
                      padding: const EdgeInsets.all(14),
                      itemCount: widget.trace.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return RepaintBoundary(
                          child: _TraceRound(
                            index: index + 1,
                            isLast: index == widget.trace.length - 1,
                            round: widget.trace[index],
                            markdownEnabled: _markdownEnabled,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkdownToggle extends StatelessWidget {
  const _MarkdownToggle({required this.enabled, required this.onToggle});

  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: enabled
          ? 'Show trace messages as plain text'
          : 'Render trace messages as Markdown',
      child: FilterChip(
        avatar: Icon(
          Icons.text_snippet_outlined,
          size: 16,
          color: enabled
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface.withValues(alpha: 0.72),
        ),
        label: const Text('Markdown'),
        selected: enabled,
        onSelected: onToggle,
        visualDensity: VisualDensity.compact,
        mouseCursor: SystemMouseCursors.click,
      ),
    );
  }
}

class _TraceRound extends StatelessWidget {
  const _TraceRound({
    required this.index,
    required this.isLast,
    required this.round,
    required this.markdownEnabled,
  });

  final int index;
  final bool isLast;
  final Map<String, dynamic> round;
  final bool markdownEnabled;

  @override
  Widget build(BuildContext context) {
    final request = _list(round['request']);
    final response = _map(round['response']);
    final availableTools = _list(round['available_tools']);
    final toolResults = _list(round['tool_results']);
    final usage = _map(round['usage']);
    final prompt = _asInt(usage['prompt_tokens']);
    final completion = _asInt(usage['completion_tokens']);
    final llmMs = _asInt(round['llm_duration_ms']);
    final toolMs = toolResults.fold<int>(
      0,
      (sum, item) => sum + _asInt(_map(item)['duration_ms']),
    );
    final hasTools = toolResults.isNotEmpty;
    final theme = Theme.of(context);
    final borderColor = hasTools
        ? _traceOrange.withValues(alpha: 0.55)
        : _traceGreen.withValues(alpha: 0.55);
    final headerColor = borderColor.withValues(alpha: 0.12);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: headerColor,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.start,
              runAlignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  hasTools
                      ? Icons.build_circle_outlined
                      : Icons.check_circle_outline_rounded,
                  size: 18,
                  color: borderColor,
                ),
                Text('Round $index', style: theme.textTheme.titleMedium),
                Text(
                  hasTools
                      ? '${toolResults.length} tool call${toolResults.length == 1 ? '' : 's'}'
                      : 'final answer',
                  style: theme.textTheme.bodySmall,
                ),
                _TraceTag(label: 'LLM ${_fmtMs(llmMs)}', color: _traceBlue),
                if (hasTools)
                  _TraceTag(label: 'tools ${_fmtMs(toolMs)}', color: _traceOrange),
                if (prompt + completion > 0)
                  _TokenMiniMetric(prompt: prompt, completion: completion),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                if (availableTools.isNotEmpty)
                  _TraceSection(
                    title: 'Available Tools',
                    trailing: '(${availableTools.length})',
                    builder: (_) => _AvailableToolsList(tools: availableTools),
                  ),
                _TraceSection(
                  title: 'Messages Sent',
                  trailing: '(${request.length})',
                  builder: (_) => Column(
                    children: [
                      if (request.isEmpty)
                        const _EmptyTraceText('No request messages captured')
                      else
                        for (final item in request)
                          RepaintBoundary(
                            child: _TraceMessageCard(
                              message: _map(item),
                              markdownEnabled: markdownEnabled,
                            ),
                          ),
                    ],
                  ),
                ),
                _TraceSection(
                  title: hasTools ? 'LLM Decision' : 'LLM Response',
                  trailing: _fmtMs(llmMs),
                  builder: (_) => Column(
                    children: [
                      _TraceMessageCard(
                        message: response,
                        markdownEnabled: markdownEnabled,
                      ),
                      if (usage.isNotEmpty) _TokenBar(usage: usage),
                    ],
                  ),
                ),
                if (toolResults.isNotEmpty)
                  _TraceSection(
                    title: 'Tool Execution',
                    trailing:
                        '${toolResults.length} call${toolResults.length == 1 ? '' : 's'} · ${_fmtMs(toolMs)}',
                    builder: (_) => Column(
                      children: [
                        for (final item in toolResults)
                          RepaintBoundary(child: _ToolResultCard(result: _map(item))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TraceSection extends StatefulWidget {
  const _TraceSection({
    required this.title,
    required this.builder,
    this.trailing,
  });

  final String title;
  final String? trailing;
  final WidgetBuilder builder;

  @override
  State<_TraceSection> createState() => _TraceSectionState();
}

class _TraceSectionState extends State<_TraceSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          mouseCursor: SystemMouseCursors.click,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 19,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    widget.trailing!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RepaintBoundary(child: widget.builder(context)),
          ),
      ],
    );
  }
}

class _TraceMessageCard extends StatelessWidget {
  const _TraceMessageCard({
    required this.message,
    required this.markdownEnabled,
  });

  final Map<String, dynamic> message;
  final bool markdownEnabled;

  @override
  Widget build(BuildContext context) {
    final role = message['role'] as String? ?? 'message';
    final content = message['content'] as String?;
    final reasoning = message['reasoning_content'] as String?;
    final refusal = message['refusal'] as String?;
    final toolCalls = _list(message['tool_calls']);
    final name = message['name'] as String?;
    final toolCallId = message['tool_call_id'] as String?;
    final roleColor = _roleColor(context, role);
    final theme = Theme.of(context);
    final fillColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72)
        : const Color(0xfffafafa);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: fillColor,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: roleColor),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 6, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _RoleBadge(role: role, color: roleColor),
                    if (name?.isNotEmpty == true)
                      Text(name!, style: theme.textTheme.bodySmall),
                    if (toolCallId?.isNotEmpty == true)
                      Text(
                        'id:$toolCallId',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
                if (content?.isNotEmpty == true)
                  _ContentBlock(content: content!, markdownEnabled: markdownEnabled),
                if (refusal?.isNotEmpty == true)
                  _ContentBlock(
                    content: '[refusal] $refusal',
                    backgroundColor: appToneFill(theme, AppTone.danger),
                    markdownEnabled: markdownEnabled,
                  ),
                for (final item in toolCalls) _ToolCallCard(call: _map(item)),
                if (reasoning?.isNotEmpty == true)
                  _InlineExpansion(
                    title: 'reasoning · ${reasoning!.length} chars',
                    child: _ContentBlock(
                      content: reasoning,
                      backgroundColor: appToneFill(theme, AppTone.warning),
                      markdownEnabled: markdownEnabled,
                    ),
                  ),
                if ((content == null || content.isEmpty) &&
                    (reasoning == null || reasoning.isEmpty) &&
                    (refusal == null || refusal.isEmpty) &&
                    toolCalls.isEmpty)
                  const _EmptyTraceText('No text content in this message'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCallCard extends StatelessWidget {
  const _ToolCallCard({required this.call});

  final Map<String, dynamic> call;

  @override
  Widget build(BuildContext context) {
    final function = _map(call['function']);
    final args = call['args'] as String? ?? function['arguments'] as String? ?? '';
    final name = call['name'] as String? ?? function['name'] as String?;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                const _SmallTag(label: 'call', color: _traceOrange),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name ?? 'tool call',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    'id:${call['id'] ?? ''}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: _ContentBlock(content: _formatJsonString(args), compact: true),
          ),
        ],
      ),
    );
  }
}

class _ToolResultCard extends StatelessWidget {
  const _ToolResultCard({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final output = result['result'] as String? ?? '';
    final lowerOutput = output.toLowerCase();
    final isError = lowerOutput.startsWith('error') ||
        lowerOutput.contains('"error"') ||
        lowerOutput.contains('error:');
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? appToneBorderColor(theme, AppTone.danger) : theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isError ? appToneFill(theme, AppTone.danger) : theme.colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(
                  color: isError ? appToneBorderColor(theme, AppTone.danger) : theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.build_outlined,
                  size: 15,
                  color: isError ? appToneColor(theme, AppTone.danger) : _traceOrange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result['name'] as String? ?? 'tool',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _DurationTag(label: _fmtMs(_asInt(result['duration_ms'])), error: isError),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ContentBlock(
                  label: 'Input',
                  content: _formatJsonString(result['args'] as String? ?? ''),
                ),
                const SizedBox(height: 6),
                _ContentBlock(
                  label: 'Output',
                  content: output,
                  backgroundColor: isError ? appToneFill(theme, AppTone.danger) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Color _roleColor(BuildContext context, String role) {
  return switch (role) {
    'system' => const Color(0xff8c8c8c),
    'user' => const Color(0xff1677ff),
    'assistant' => const Color(0xff52c41a),
    'tool' => const Color(0xfffa8c16),
    _ => Theme.of(context).colorScheme.onSurface,
  };
}

List<dynamic> _list(Object? value) =>
    value is List<dynamic> ? value : const [];

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return const {};
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return 0;
}

String _fmtMs(int ms) =>
    ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(1)}s';

String _formatJsonString(String raw) {
  if (raw.length > 24000) return raw;
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
  } catch (_) {
    return raw;
  }
}
