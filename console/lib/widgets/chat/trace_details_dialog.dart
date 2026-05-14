import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../common/app_ui.dart';

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
                  final actions = Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Tooltip(
                        message: _markdownEnabled
                            ? 'Show trace messages as plain text'
                            : 'Render trace messages as Markdown',
                        child: FilterChip(
                          avatar: Icon(
                            Icons.text_snippet_outlined,
                            size: 16,
                            color: _markdownEnabled
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.72,
                                  ),
                          ),
                          label: const Text('Markdown'),
                          selected: _markdownEnabled,
                          onSelected: (value) {
                            setState(() => _markdownEnabled = value);
                          },
                          visualDensity: VisualDensity.compact,
                          mouseCursor: SystemMouseCursors.click,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        mouseCursor: SystemMouseCursors.click,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
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
                              children: [
                                Expanded(child: title),
                                IconButton(
                                  tooltip: 'Close',
                                  onPressed: () => Navigator.of(context).pop(),
                                  mouseCursor: SystemMouseCursors.click,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            Tooltip(
                              message: _markdownEnabled
                                  ? 'Show trace messages as plain text'
                                  : 'Render trace messages as Markdown',
                              child: FilterChip(
                                avatar: Icon(
                                  Icons.text_snippet_outlined,
                                  size: 16,
                                  color: _markdownEnabled
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurface.withValues(
                                          alpha: 0.72,
                                        ),
                                ),
                                label: const Text('Markdown'),
                                selected: _markdownEnabled,
                                onSelected: (value) {
                                  setState(() => _markdownEnabled = value);
                                },
                                visualDensity: VisualDensity.compact,
                                mouseCursor: SystemMouseCursors.click,
                              ),
                            ),
                          ],
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: title),
                            actions,
                          ],
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          _HeaderMetric(
                            icon: Icons.bolt_rounded,
                            label: 'LLM ${_fmtMs(totals.llmMs)}',
                            color: theme.colorScheme.primary,
                          ),
                          if (totals.toolMs > 0)
                            _HeaderMetric(
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
                  _TraceTag(
                    label: 'tools ${_fmtMs(toolMs)}',
                    color: _traceOrange,
                  ),
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
                    initiallyExpanded: false,
                    title: 'Available Tools',
                    trailing: '(${availableTools.length})',
                    builder: (_) => _AvailableToolsList(tools: availableTools),
                  ),
                _TraceSection(
                  initiallyExpanded: false,
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
                  initiallyExpanded: false,
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
                    initiallyExpanded: false,
                    title: 'Tool Execution',
                    trailing:
                        '${toolResults.length} call${toolResults.length == 1 ? '' : 's'} · ${_fmtMs(toolMs)}',
                    builder: (_) => Column(
                      children: [
                        for (final item in toolResults)
                          RepaintBoundary(
                            child: _ToolResultCard(result: _map(item)),
                          ),
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
    this.initiallyExpanded = false,
  });

  final String title;
  final String? trailing;
  final bool initiallyExpanded;
  final WidgetBuilder builder;

  @override
  State<_TraceSection> createState() => _TraceSectionState();
}

class _TraceSectionState extends State<_TraceSection> {
  late bool _expanded = widget.initiallyExpanded;

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
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.58,
                      ),
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

class _TraceTag extends StatelessWidget {
  const _TraceTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _DurationTag extends StatelessWidget {
  const _DurationTag({required this.label, this.error = false});

  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = error
        ? _softErrorAccentColor(theme)
        : theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: error ? _softErrorColor(theme) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: error
              ? _softErrorBorderColor(theme)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color.withValues(alpha: error ? 1 : 0.72),
          fontSize: 10,
          height: 1.2,
        ),
      ),
    );
  }
}

class _TokenMiniMetric extends StatelessWidget {
  const _TokenMiniMetric({required this.prompt, required this.completion});

  final int prompt;
  final int completion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
      fontSize: 11,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.arrow_upward_rounded, size: 13, color: _traceBlue),
        const SizedBox(width: 2),
        Text('$prompt', style: style),
        const SizedBox(width: 6),
        Icon(Icons.arrow_downward_rounded, size: 13, color: _traceGreen),
        const SizedBox(width: 2),
        Text('$completion tok', style: style),
      ],
    );
  }
}

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
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ),
                  ],
                ),
                if (content?.isNotEmpty == true)
                  _ContentBlock(
                    content: content!,
                    markdownEnabled: markdownEnabled,
                  ),
                if (refusal?.isNotEmpty == true)
                  _ContentBlock(
                    content: '[refusal] $refusal',
                    backgroundColor: _softErrorColor(theme),
                    markdownEnabled: markdownEnabled,
                  ),
                for (final item in toolCalls) _ToolCallCard(call: _map(item)),
                if (reasoning?.isNotEmpty == true)
                  _ReasoningBlock(
                    content: reasoning!,
                    markdownEnabled: markdownEnabled,
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
    final args =
        call['args'] as String? ?? function['arguments'] as String? ?? '';
    final name = call['name'] as String? ?? function['name'] as String?;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 0),
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
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
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
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.55,
                      ),
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: _ContentBlock(
              content: _formatJsonString(args),
              compact: true,
            ),
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
    final isError =
        lowerOutput.startsWith('error') ||
        lowerOutput.contains('"error"') ||
        lowerOutput.contains('error:');
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError
              ? _softErrorBorderColor(theme)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isError
                  ? _softErrorColor(theme)
                  : theme.colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(
                  color: isError
                      ? _softErrorBorderColor(theme)
                      : theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.build_outlined,
                  size: 15,
                  color: isError ? _softErrorAccentColor(theme) : _traceOrange,
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
                _DurationTag(
                  label: _fmtMs(_asInt(result['duration_ms'])),
                  error: isError,
                ),
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
                  backgroundColor: isError ? _softErrorColor(theme) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableToolsList extends StatefulWidget {
  const _AvailableToolsList({required this.tools});

  final List<dynamic> tools;

  @override
  State<_AvailableToolsList> createState() => _AvailableToolsListState();
}

class _AvailableToolsListState extends State<_AvailableToolsList> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final tools = widget.tools.where((item) {
      if (query.isEmpty) return true;
      final tool = _map(item);
      final name = (tool['name'] as String? ?? '').toLowerCase();
      final description = (tool['description'] as String? ?? '').toLowerCase();
      return name.contains(query) || description.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.tools.length > 5) ...[
          SizedBox(
            height: 36,
            child: TextField(
              controller: _searchController,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: 'Filter tools...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear filter',
                        iconSize: 16,
                        visualDensity: VisualDensity.compact,
                        mouseCursor: SystemMouseCursors.click,
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (tools.isEmpty)
          const _EmptyTraceText('No matching tools')
        else if (tools.length <= 4)
          Column(
            children: [
              for (final item in tools)
                RepaintBoundary(child: _AvailableToolCard(tool: _map(item))),
            ],
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.48,
            ),
            child: ListView.separated(
              cacheExtent: 700,
              itemCount: tools.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                return RepaintBoundary(
                  child: _AvailableToolCard(tool: _map(tools[index])),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _AvailableToolCard extends StatelessWidget {
  const _AvailableToolCard({required this.tool});

  final Map<String, dynamic> tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parameters = _map(tool['parameters']);
    final params = _map(parameters['properties']);
    final requiredNames = (_list(
      parameters['required'],
    )).whereType<String>().toSet();
    final description = tool['description'] as String? ?? '';
    final name = tool['name'] as String? ?? 'tool';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SmallTag(label: name, color: _traceBlue, code: true),
              if (params.isNotEmpty)
                Text(
                  '${params.length} param${params.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          if (params.isNotEmpty)
            _InlineExpansion(
              title: 'Parameters',
              child: _ParametersView(
                params: params,
                requiredNames: requiredNames,
              ),
            ),
        ],
      ),
    );
  }
}

class _ParametersView extends StatelessWidget {
  const _ParametersView({required this.params, required this.requiredNames});

  final Map<String, dynamic> params;
  final Set<String> requiredNames;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final entries = params.entries.toList();
        if (constraints.maxWidth >= 680) {
          return _ParameterTable(
            entries: entries,
            requiredNames: requiredNames,
          );
        }
        return Column(
          children: [
            for (final entry in entries)
              _ParameterCard(
                name: entry.key,
                schema: _map(entry.value),
                required: requiredNames.contains(entry.key),
              ),
          ],
        );
      },
    );
  }
}

class _ParameterTable extends StatelessWidget {
  const _ParameterTable({required this.entries, required this.requiredNames});

  final List<MapEntry<String, dynamic>> entries;
  final Set<String> requiredNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(160),
        1: FixedColumnWidth(70),
        2: FlexColumnWidth(),
      },
      border: TableBorder.all(color: theme.colorScheme.outlineVariant),
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          children: const [
            _ParameterCell('Parameter', header: true),
            _ParameterCell('Type', header: true),
            _ParameterCell('Description', header: true),
          ],
        ),
        for (final entry in entries)
          _parameterTableRow(context, entry, requiredNames.contains(entry.key)),
      ],
    );
  }

  TableRow _parameterTableRow(
    BuildContext context,
    MapEntry<String, dynamic> entry,
    bool required,
  ) {
    final schema = _map(entry.value);
    final type = schema['type'] as String? ?? 'value';
    final description = schema['description'] as String? ?? '';
    return TableRow(
      children: [
        _ParameterNameCell(name: entry.key, required: required),
        _ParameterTypeCell(type: type),
        _ParameterCell(description.isEmpty ? '-' : description),
      ],
    );
  }
}

class _ParameterCell extends StatelessWidget {
  const _ParameterCell(this.text, {this.header = false});

  final String text;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final style = header
        ? Theme.of(context).textTheme.labelSmall
        : Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Text(text, style: style),
    );
  }
}

class _ParameterNameCell extends StatelessWidget {
  const _ParameterNameCell({required this.name, required this.required});

  final String name;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(name, style: theme.textTheme.bodySmall),
          if (required) const _RequiredTag(),
        ],
      ),
    );
  }
}

class _ParameterTypeCell extends StatelessWidget {
  const _ParameterTypeCell({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: type.isEmpty ? const SizedBox.shrink() : _TypeTag(type),
    );
  }
}

class _ParameterCard extends StatelessWidget {
  const _ParameterCard({
    required this.name,
    required this.schema,
    required this.required,
  });

  final String name;
  final Map<String, dynamic> schema;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = schema['type'] as String? ?? 'value';
    final description = schema['description'] as String? ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(name, style: theme.textTheme.labelMedium),
          if (required) const _RequiredTag(),
          if (type.isNotEmpty) _TypeTag(type),
          if (description.isNotEmpty)
            Text(description, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RequiredTag extends StatelessWidget {
  const _RequiredTag();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        'req',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 10,
          height: 1.35,
        ),
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  const _TypeTag(this.type);

  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        type,
        style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, height: 1.2),
      ),
    );
  }
}

class _TokenBar extends StatelessWidget {
  const _TokenBar({required this.usage});

  final Map<String, dynamic> usage;

  @override
  Widget build(BuildContext context) {
    final prompt = _asInt(usage['prompt_tokens']);
    final completion = _asInt(usage['completion_tokens']);
    final reasoning = _asInt(usage['reasoning_tokens']);
    final cached = _asInt(usage['cached_tokens']);
    final total = prompt + completion;
    if (total == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final promptUncached = (prompt - cached).clamp(0, prompt);
    final completionVisible = (completion - reasoning).clamp(0, completion);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _TokenLegend(
                icon: Icons.arrow_upward_rounded,
                label: '$prompt prompt',
                color: _traceBlue,
              ),
              _TokenLegend(
                icon: Icons.arrow_downward_rounded,
                label: '$completion completion',
                color: _traceGreen,
              ),
              if (reasoning > 0)
                _TokenLegend(
                  icon: Icons.psychology_alt_outlined,
                  label: '$reasoning reasoning',
                  color: _traceYellow,
                ),
              if (cached > 0)
                _TokenLegend(
                  icon: Icons.history_rounded,
                  label: '$cached cached',
                  color: _traceMuted,
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                if (cached > 0)
                  Expanded(
                    flex: cached,
                    child: const ColoredBox(
                      color: _traceMuted,
                      child: SizedBox(height: 7),
                    ),
                  ),
                if (promptUncached > 0)
                  Expanded(
                    flex: promptUncached,
                    child: const ColoredBox(
                      color: _traceBlue,
                      child: SizedBox(height: 7),
                    ),
                  ),
                if (completionVisible > 0)
                  Expanded(
                    flex: completionVisible,
                    child: const ColoredBox(
                      color: _traceGreen,
                      child: SizedBox(height: 7),
                    ),
                  ),
                if (reasoning > 0)
                  Expanded(
                    flex: reasoning,
                    child: const ColoredBox(
                      color: _traceYellow,
                      child: SizedBox(height: 7),
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

class _TokenLegend extends StatelessWidget {
  const _TokenLegend({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
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

class _ReasoningBlock extends StatelessWidget {
  const _ReasoningBlock({required this.content, required this.markdownEnabled});

  final String content;
  final bool markdownEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _InlineExpansion(
      title: 'reasoning · ${content.length} chars',
      child: _ContentBlock(
        content: content,
        backgroundColor: _warningWellColor(theme),
        markdownEnabled: markdownEnabled,
      ),
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
    final displayed = canCollapse && !_expanded
        ? _preview.preview
        : widget.content;
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      height: 1.55,
    );

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
          margin: EdgeInsets.only(
            top: widget.compact || widget.label != null ? 2 : 6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color:
                widget.backgroundColor ??
                theme.colorScheme.surfaceContainerHighest,
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
                        ? MarkdownBody(
                            data: displayed,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet.fromTheme(theme)
                                .copyWith(
                                  p: textStyle?.copyWith(
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.white
                                        : null,
                                  ),
                                  h1: theme.textTheme.titleLarge?.copyWith(
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.white
                                        : null,
                                  ),
                                  h2: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.white
                                        : null,
                                  ),
                                  h3: theme.textTheme.titleSmall?.copyWith(
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.white
                                        : null,
                                  ),
                                  listBullet: textStyle?.copyWith(
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.white
                                        : null,
                                  ),
                                  blockSpacing: 8,
                                  code: textStyle?.copyWith(
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.white
                                        : null,
                                    backgroundColor: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                  codeblockDecoration: BoxDecoration(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: theme.colorScheme.outlineVariant,
                                    ),
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
                          )
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
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
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
      if (copiedLines <= maxLines) {
        buffer.writeCharCode(char);
      }
    }

    return _ContentPreview(
      preview: buffer.toString(),
      lineCount: content.isEmpty ? 0 : lineCount,
    );
  }
}

class _SmallTag extends StatelessWidget {
  const _SmallTag({
    required this.label,
    required this.color,
    this.code = false,
  });

  final String label;
  final Color color;
  final bool code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: code ? 12 : 10,
          height: 1.2,
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role, required this.color});

  final String role;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        role.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 10,
          letterSpacing: 0.5,
          height: 1.2,
        ),
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _HeaderTokenMetric extends StatelessWidget {
  const _HeaderTokenMetric({
    required this.prompt,
    required this.completion,
    required this.reasoning,
    required this.cached,
  });

  final int prompt;
  final int completion;
  final int reasoning;
  final int cached;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 7,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _InlineMetric(
          icon: Icons.arrow_upward_rounded,
          label: '$prompt',
          color: _traceBlue,
          style: style,
        ),
        _InlineMetric(
          icon: Icons.arrow_downward_rounded,
          label: '$completion tok',
          color: _traceGreen,
          style: style,
        ),
        if (reasoning > 0)
          _InlineMetric(
            icon: Icons.psychology_alt_outlined,
            label: '$reasoning reasoning',
            color: _traceYellow,
            style: style,
          ),
        if (cached > 0)
          _InlineMetric(
            icon: Icons.history_rounded,
            label: '$cached cached',
            color: _traceMuted,
            style: style,
          ),
      ],
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.icon,
    required this.label,
    required this.color,
    required this.style,
  });

  final IconData icon;
  final String label;
  final Color color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(label, style: style),
      ],
    );
  }
}

class _TraceTotals {
  const _TraceTotals({
    required this.llmMs,
    required this.toolMs,
    required this.toolCalls,
    required this.prompt,
    required this.completion,
    required this.reasoning,
    required this.cached,
  });

  final int llmMs;
  final int toolMs;
  final int toolCalls;
  final int prompt;
  final int completion;
  final int reasoning;
  final int cached;

  static _TraceTotals from(List<Map<String, dynamic>> trace) {
    var llmMs = 0;
    var toolMs = 0;
    var toolCalls = 0;
    var prompt = 0;
    var completion = 0;
    var reasoning = 0;
    var cached = 0;
    for (final round in trace) {
      llmMs += _asInt(round['llm_duration_ms']);
      for (final result in _list(round['tool_results'])) {
        toolCalls++;
        toolMs += _asInt(_map(result)['duration_ms']);
      }
      final usage = _map(round['usage']);
      prompt += _asInt(usage['prompt_tokens']);
      completion += _asInt(usage['completion_tokens']);
      reasoning += _asInt(usage['reasoning_tokens']);
      cached += _asInt(usage['cached_tokens']);
    }
    return _TraceTotals(
      llmMs: llmMs,
      toolMs: toolMs,
      toolCalls: toolCalls,
      prompt: prompt,
      completion: completion,
      reasoning: reasoning,
      cached: cached,
    );
  }
}

Color _roleColor(BuildContext context, String role) {
  return switch (role) {
    'system' => const Color(0xff8c8c8c),
    'user' => const Color(0xff1677ff),
    'assistant' => const Color(0xff52c41a),
    'tool' => const Color(0xfffa8c16),
    _ => Theme.of(context).colorScheme.onSurface,
  };
}

Color _warningWellColor(ThemeData theme) {
  if (theme.brightness == Brightness.dark) {
    return _traceYellow.withValues(alpha: 0.16);
  }
  return const Color(0xfffffbe6);
}

Color _softErrorColor(ThemeData theme) {
  return appToneFill(theme, AppTone.danger);
}

Color _softErrorBorderColor(ThemeData theme) {
  return appToneColor(
    theme,
    AppTone.danger,
  ).withValues(alpha: theme.brightness == Brightness.dark ? 0.34 : 0.22);
}

Color _softErrorAccentColor(ThemeData theme) {
  return appToneColor(theme, AppTone.danger);
}

List<dynamic> _list(Object? value) {
  return value is List<dynamic> ? value : const [];
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return 0;
}

String _fmtMs(int ms) {
  return ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(1)}s';
}

String _formatJsonString(String raw) {
  if (raw.length > 24000) return raw;
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
  } catch (_) {
    return raw;
  }
}
