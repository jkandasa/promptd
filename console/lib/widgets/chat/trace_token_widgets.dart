part of 'trace_details_dialog.dart';

// ---------------------------------------------------------------------------
// Badge / tag widgets
// ---------------------------------------------------------------------------

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

class _SmallTag extends StatelessWidget {
  const _SmallTag({required this.label, required this.color, this.code = false});

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

class _DurationTag extends StatelessWidget {
  const _DurationTag({required this.label, this.error = false});

  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = error ? appToneColor(theme, AppTone.danger) : theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: error ? appToneFill(theme, AppTone.danger) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: error ? appToneBorderColor(theme, AppTone.danger) : theme.colorScheme.outlineVariant,
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

// ---------------------------------------------------------------------------
// Token / metric widgets
// ---------------------------------------------------------------------------

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

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.icon,
    required this.label,
    required this.color,
    this.style,
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
        Text(label, style: style ?? Theme.of(context).textTheme.bodySmall),
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
        _InlineMetric(icon: Icons.arrow_upward_rounded, label: '$prompt', color: _traceBlue, style: style),
        _InlineMetric(icon: Icons.arrow_downward_rounded, label: '$completion tok', color: _traceGreen, style: style),
        if (reasoning > 0)
          _InlineMetric(icon: Icons.psychology_alt_outlined, label: '$reasoning reasoning', color: _traceYellow, style: style),
        if (cached > 0)
          _InlineMetric(icon: Icons.history_rounded, label: '$cached cached', color: _traceMuted, style: style),
      ],
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
              _InlineMetric(icon: Icons.arrow_upward_rounded, label: '$prompt prompt', color: _traceBlue),
              _InlineMetric(icon: Icons.arrow_downward_rounded, label: '$completion completion', color: _traceGreen),
              if (reasoning > 0)
                _InlineMetric(icon: Icons.psychology_alt_outlined, label: '$reasoning reasoning', color: _traceYellow),
              if (cached > 0)
                _InlineMetric(icon: Icons.history_rounded, label: '$cached cached', color: _traceMuted),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                if (cached > 0)
                  Expanded(flex: cached, child: const ColoredBox(color: _traceMuted, child: SizedBox(height: 7))),
                if (promptUncached > 0)
                  Expanded(flex: promptUncached, child: const ColoredBox(color: _traceBlue, child: SizedBox(height: 7))),
                if (completionVisible > 0)
                  Expanded(flex: completionVisible, child: const ColoredBox(color: _traceGreen, child: SizedBox(height: 7))),
                if (reasoning > 0)
                  Expanded(flex: reasoning, child: const ColoredBox(color: _traceYellow, child: SizedBox(height: 7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

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
