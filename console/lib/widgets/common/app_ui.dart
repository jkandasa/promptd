import 'package:flutter/material.dart';

enum AppTone { neutral, primary, success, warning, danger }

class AppBreakpoints {
  const AppBreakpoints._();

  static const double compact = 640;
  static const double medium = 900;
  static const double wide = 1080;
}

class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius,
    this.elevated = false,
    this.clip = Clip.none,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? radius;
  final bool elevated;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(radius ?? 12);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: borderRadius,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      clipBehavior: clip,
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final Widget? actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: compact
              ? theme.textTheme.titleLarge
              : theme.textTheme.titleMedium,
        ),
        if (subtitle?.isNotEmpty == true) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
        ],
      ],
    );

    if (actions == null) return copy;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppBreakpoints.compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              copy,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: actions!),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: 12),
            actions!,
          ],
        );
      },
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 54,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (message?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    this.icon,
    this.tone = AppTone.neutral,
    this.selected = false,
    this.compact = true,
  });

  final String label;
  final IconData? icon;
  final AppTone tone;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = appToneColor(theme, tone);
    final foreground = selected ? theme.colorScheme.onPrimary : color;
    final background = selected
        ? theme.colorScheme.primary
        : color.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.18 : 0.10,
          );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : color.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.36 : 0.28,
                ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 13 : 15, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChoiceChip(
      showCheckmark: false,
      selected: selected,
      onSelected: (_) => onSelected(),
      mouseCursor: SystemMouseCursors.click,
      visualDensity: VisualDensity.compact,
      selectedColor: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surface,
      side: BorderSide(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant,
      ),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: selected
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.onPrimary.withValues(alpha: 0.18)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.68),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilterChip(
      showCheckmark: false,
      selected: selected,
      onSelected: onSelected,
      mouseCursor: SystemMouseCursors.click,
      visualDensity: VisualDensity.compact,
      selectedColor: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surface,
      side: BorderSide(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant,
      ),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: selected
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      label: Text(label),
    );
  }
}

class AppNotice extends StatelessWidget {
  const AppNotice({
    super.key,
    required this.message,
    this.tone = AppTone.neutral,
    this.icon,
  });

  final String message;
  final AppTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = appToneColor(theme, tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: appToneFill(theme, tone),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? _toneIcon(tone), size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _toneIcon(AppTone tone) {
    return switch (tone) {
      AppTone.success => Icons.check_circle_outline_rounded,
      AppTone.warning => Icons.info_outline_rounded,
      AppTone.danger => Icons.error_outline_rounded,
      AppTone.primary => Icons.info_outline_rounded,
      AppTone.neutral => Icons.info_outline_rounded,
    };
  }
}

/// A button that shows an inline spinner when [loading] is true and disables
/// itself. Use [icon] for an icon-prefixed [FilledButton]; omit it for a
/// text-only button. Set [destructive] for error-colored actions.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool destructive;

  static const _spinner = SizedBox.square(
    dimension: 16,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveOnPressed = loading ? null : onPressed;
    final effectiveIcon = loading ? _spinner : (icon != null ? Icon(icon) : null);

    final style = destructive
        ? FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          )
        : null;

    if (effectiveIcon != null) {
      return FilledButton.icon(
        onPressed: effectiveOnPressed,
        style: style,
        icon: effectiveIcon,
        label: Text(label),
      );
    }
    return FilledButton(
      onPressed: effectiveOnPressed,
      style: style,
      child: Text(label),
    );
  }
}

Color appToneColor(ThemeData theme, AppTone tone) {
  return switch (tone) {
    AppTone.primary => theme.colorScheme.primary,
    AppTone.success =>
      theme.brightness == Brightness.dark
          ? const Color(0xFF86EFAC)
          : const Color(0xFF15803D),
    AppTone.warning =>
      theme.brightness == Brightness.dark
          ? const Color(0xFFFCD34D)
          : const Color(0xFFB45309),
    AppTone.danger => theme.colorScheme.error,
    AppTone.neutral => theme.colorScheme.onSurface.withValues(alpha: 0.66),
  };
}

Color appToneFill(ThemeData theme, AppTone tone) {
  final color = appToneColor(theme, tone);
  final amount = theme.brightness == Brightness.dark ? 0.18 : 0.09;
  return Color.lerp(theme.colorScheme.surface, color, amount)!;
}
