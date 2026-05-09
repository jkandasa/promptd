import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> showTraceDetailsDialog(
  BuildContext context,
  List<Map<String, dynamic>> trace,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => TraceDetailsDialog(trace: trace),
  );
}

class TraceDetailsDialog extends StatelessWidget {
  const TraceDetailsDialog({super.key, required this.trace});

  final List<Map<String, dynamic>> trace;

  @override
  Widget build(BuildContext context) {
    final totals = _TraceTotals.from(trace);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('LLM Trace'),
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  '${trace.length} round${trace.length == 1 ? '' : 's'}',
                ),
                visualDensity: VisualDensity.compact,
              ),
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
                _HeaderMetric(
                  icon: Icons.token_rounded,
                  label:
                      '${totals.prompt} up ${totals.completion} down tok'
                      '${totals.reasoning > 0 ? ' · ${totals.reasoning} reasoning' : ''}'
                      '${totals.cached > 0 ? ' · ${totals.cached} cached' : ''}',
                  color: theme.colorScheme.secondary,
                ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 900,
        height: 680,
        child: trace.isEmpty
            ? const Center(child: Text('No trace data available'))
            : ListView.separated(
                itemCount: trace.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return _TraceRound(
                    index: index + 1,
                    isLast: index == trace.length - 1,
                    round: trace[index],
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _TraceRound extends StatelessWidget {
  const _TraceRound({
    required this.index,
    required this.isLast,
    required this.round,
  });

  final int index;
  final bool isLast;
  final Map<String, dynamic> round;

  @override
  Widget build(BuildContext context) {
    final request = _list(round['request']);
    final response = _map(round['response']);
    final availableTools = _list(round['available_tools']);
    final toolResults = _list(round['tool_results']);
    final usage = _map(round['usage']);
    final llmMs = round['llm_duration_ms'] as int? ?? 0;
    final toolMs = toolResults.fold<int>(
      0,
      (sum, item) => sum + ((_map(item)['duration_ms'] as int?) ?? 0),
    );
    final hasTools = toolResults.isNotEmpty;
    final theme = Theme.of(context);
    final borderColor = hasTools
        ? theme.colorScheme.tertiary.withValues(alpha: 0.55)
        : theme.colorScheme.primary.withValues(alpha: 0.55);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: borderColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasTools
                      ? Icons.build_circle_outlined
                      : Icons.check_circle_outline_rounded,
                  size: 18,
                  color: borderColor,
                ),
                const SizedBox(width: 8),
                Text('Round $index', style: theme.textTheme.titleMedium),
                const SizedBox(width: 6),
                Text(
                  hasTools
                      ? '${toolResults.length} tool call${toolResults.length == 1 ? '' : 's'}'
                      : 'final answer',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                Chip(
                  label: Text('LLM ${_fmtMs(llmMs)}'),
                  visualDensity: VisualDensity.compact,
                ),
                if (hasTools) ...[
                  const SizedBox(width: 6),
                  Chip(
                    label: Text('tools ${_fmtMs(toolMs)}'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
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
                    title: 'Available tools (${availableTools.length})',
                    child: _AvailableToolsList(tools: availableTools),
                  ),
                _TraceSection(
                  initiallyExpanded: !isLast,
                  title: 'Messages sent (${request.length})',
                  child: Column(
                    children: [
                      for (final item in request)
                        _TraceMessageCard(message: _map(item)),
                    ],
                  ),
                ),
                _TraceSection(
                  initiallyExpanded: true,
                  title: hasTools ? 'LLM decision' : 'LLM response',
                  trailing: _fmtMs(llmMs),
                  child: Column(
                    children: [
                      _TraceMessageCard(message: response),
                      if (usage.isNotEmpty) _TokenBar(usage: usage),
                    ],
                  ),
                ),
                if (toolResults.isNotEmpty)
                  _TraceSection(
                    initiallyExpanded: true,
                    title: 'Tool execution (${toolResults.length})',
                    trailing: _fmtMs(toolMs),
                    child: Column(
                      children: [
                        for (final item in toolResults)
                          _ToolResultCard(result: _map(item)),
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

class _TraceSection extends StatelessWidget {
  const _TraceSection({
    required this.title,
    required this.child,
    this.trailing,
    this.initiallyExpanded = false,
  });

  final String title;
  final String? trailing;
  final bool initiallyExpanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: initiallyExpanded,
      title: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      children: [child],
    );
  }
}

class _TraceMessageCard extends StatelessWidget {
  const _TraceMessageCard({required this.message});

  final Map<String, dynamic> message;

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

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: roleColor, width: 3),
          top: BorderSide(color: theme.colorScheme.outlineVariant),
          right: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _RoleBadge(role: role, color: roleColor),
              if (name?.isNotEmpty == true)
                Text(
                  name!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              if (toolCallId?.isNotEmpty == true)
                Text(
                  'id:$toolCallId',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
            ],
          ),
          if (content?.isNotEmpty == true)
            _ContentBlock(label: 'Content', content: content!),
          if (reasoning?.isNotEmpty == true)
            _ContentBlock(label: 'Reasoning', content: reasoning!),
          if (refusal?.isNotEmpty == true)
            _ContentBlock(label: 'Refusal', content: refusal!),
          for (final item in toolCalls) _ToolCallCard(call: _map(item)),
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
    final args = call['args'] as String? ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                const Icon(Icons.call_made_rounded, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    call['name'] as String? ?? 'tool call',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
                Text(
                  'id:${call['id'] ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          _ContentBlock(content: _formatJsonString(args), compact: true),
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
    final isError = output.toLowerCase().contains('error');
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError
              ? theme.colorScheme.error.withValues(alpha: 0.45)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: isError
                ? theme.colorScheme.errorContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  Icons.build_circle_outlined,
                  size: 16,
                  color: isError
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result['name'] as String? ?? 'tool',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                Chip(
                  label: Text(_fmtMs(result['duration_ms'] as int? ?? 0)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                _ContentBlock(
                  label: 'Input',
                  content: _formatJsonString(result['args'] as String? ?? ''),
                ),
                _ContentBlock(label: 'Output', content: output),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableToolsList extends StatelessWidget {
  const _AvailableToolsList({required this.tools});

  final List<dynamic> tools;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in tools)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Builder(
              builder: (context) {
                final tool = _map(item);
                final params = _map(_map(tool['parameters'])['properties']);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool['name'] as String? ?? 'tool',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(fontFamily: 'monospace'),
                    ),
                    if ((tool['description'] as String? ?? '').isNotEmpty)
                      Text(tool['description'] as String),
                    if (params.isNotEmpty)
                      Text(
                        '${params.length} param${params.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

class _TokenBar extends StatelessWidget {
  const _TokenBar({required this.usage});

  final Map<String, dynamic> usage;

  @override
  Widget build(BuildContext context) {
    final prompt = usage['prompt_tokens'] as int? ?? 0;
    final completion = usage['completion_tokens'] as int? ?? 0;
    final reasoning = usage['reasoning_tokens'] as int? ?? 0;
    final cached = usage['cached_tokens'] as int? ?? 0;
    final total = prompt + completion;
    if (total == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final promptWidth = (prompt / total).clamp(0, 1).toDouble();
    final completionWidth = (completion / total).clamp(0, 1).toDouble();

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
                color: theme.colorScheme.primary,
              ),
              _TokenLegend(
                icon: Icons.arrow_downward_rounded,
                label: '$completion completion',
                color: theme.colorScheme.secondary,
              ),
              if (reasoning > 0)
                _TokenLegend(
                  icon: Icons.psychology_alt_outlined,
                  label: '$reasoning reasoning',
                  color: theme.colorScheme.tertiary,
                ),
              if (cached > 0)
                _TokenLegend(
                  icon: Icons.history_rounded,
                  label: '$cached cached',
                  color: theme.colorScheme.outline,
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Expanded(
                  flex: (promptWidth * 1000).round().clamp(1, 1000),
                  child: ColoredBox(
                    color: theme.colorScheme.primary,
                    child: const SizedBox(height: 7),
                  ),
                ),
                Expanded(
                  flex: (completionWidth * 1000).round().clamp(1, 1000),
                  child: ColoredBox(
                    color: theme.colorScheme.secondary,
                    child: const SizedBox(height: 7),
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

class _ContentBlock extends StatelessWidget {
  const _ContentBlock({
    required this.content,
    this.label,
    this.compact = false,
  });

  final String content;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: compact ? 0 : 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 38, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null)
                  Text(label!, style: theme.textTheme.labelSmall),
                SelectableText(
                  content,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              tooltip: 'Copy',
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              onPressed: () => Clipboard.setData(ClipboardData(text: content)),
              icon: const Icon(Icons.copy_rounded),
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        role.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
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
      llmMs += round['llm_duration_ms'] as int? ?? 0;
      for (final result in _list(round['tool_results'])) {
        toolCalls++;
        toolMs += _map(result)['duration_ms'] as int? ?? 0;
      }
      final usage = _map(round['usage']);
      prompt += usage['prompt_tokens'] as int? ?? 0;
      completion += usage['completion_tokens'] as int? ?? 0;
      reasoning += usage['reasoning_tokens'] as int? ?? 0;
      cached += usage['cached_tokens'] as int? ?? 0;
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
  final scheme = Theme.of(context).colorScheme;
  return switch (role) {
    'system' => scheme.outline,
    'user' => scheme.primary,
    'assistant' => scheme.secondary,
    'tool' => scheme.tertiary,
    _ => scheme.onSurface,
  };
}

List<dynamic> _list(Object? value) {
  return value is List<dynamic> ? value : const [];
}

Map<String, dynamic> _map(Object? value) {
  return value is Map<String, dynamic> ? value : const {};
}

String _fmtMs(int ms) {
  return ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(1)}s';
}

String _formatJsonString(String raw) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
  } catch (_) {
    return raw;
  }
}
