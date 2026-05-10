import 'package:flutter/material.dart';

import '../models/promptd_models.dart';
import '../theme/app_theme.dart';
import 'brand_mark.dart';

enum ConsoleSection { chat, scheduler, tools }

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.section,
    required this.themeMode,
    required this.me,
    required this.serverUrl,
    required this.loading,
    required this.onSectionSelected,
    required this.onThemeModeChanged,
    required this.onRefresh,
    required this.onLogout,
    required this.child,
  });

  final ConsoleSection section;
  final ThemeMode themeMode;
  final AuthMe me;
  final String serverUrl;
  final bool loading;
  final ValueChanged<ConsoleSection> onSectionSelected;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLogout;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 960;
        final useExtendedRail = constraints.maxWidth >= 1280;

        return Scaffold(
          drawer: useRail
              ? null
              : Drawer(
                  child: SafeArea(
                    child: _SectionNav(
                      section: section,
                      extended: true,
                      onSectionSelected: onSectionSelected,
                    ),
                  ),
                ),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.scaffoldBackgroundColor,
                  theme.colorScheme.surfaceContainerLowest,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    height: 72,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.9),
                      border: Border(
                        bottom: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!useRail)
                          Builder(
                            builder: (context) {
                              return IconButton(
                                onPressed: () =>
                                    Scaffold.of(context).openDrawer(),
                                icon: const Icon(Icons.menu_rounded),
                              );
                            },
                          ),
                        const BrandMark(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Promptd',
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                'AI Assistant Console',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.65,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: loading ? null : onRefresh,
                          icon: loading
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<ThemeMode>(
                          tooltip: 'Theme',
                          icon: Icon(_themeIcon(themeMode)),
                          onSelected: onThemeModeChanged,
                          itemBuilder: (context) => [
                            _themeMenuItem(
                              context,
                              mode: ThemeMode.light,
                              selected: themeMode == ThemeMode.light,
                              icon: Icons.light_mode_outlined,
                              label: 'Light',
                            ),
                            _themeMenuItem(
                              context,
                              mode: ThemeMode.dark,
                              selected: themeMode == ThemeMode.dark,
                              icon: Icons.dark_mode_outlined,
                              label: 'Dark',
                            ),
                            _themeMenuItem(
                              context,
                              mode: ThemeMode.system,
                              selected: themeMode == ThemeMode.system,
                              icon: Icons.brightness_auto_outlined,
                              label: 'System',
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        PopupMenuButton<String>(
                          tooltip: me.userId,
                          onSelected: (value) {
                            if (value == 'logout') onLogout();
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              enabled: false,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    me.userId,
                                    style: theme.textTheme.labelLarge,
                                  ),
                                  Text(
                                    serverUrl,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'logout',
                              child: Row(
                                children: [
                                  Icon(Icons.logout_rounded),
                                  SizedBox(width: 10),
                                  Text('Sign out'),
                                ],
                              ),
                            ),
                          ],
                          child: CircleAvatar(
                            radius: 19,
                            backgroundColor: AppTheme.primary.withValues(
                              alpha: 0.14,
                            ),
                            child: Text(
                              _initials(me.userId),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        if (useRail)
                          Container(
                            width: useExtendedRail ? 252 : 92,
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                            child: SafeArea(
                              top: false,
                              child: _SectionNav(
                                section: section,
                                extended: useExtendedRail,
                                onSectionSelected: onSectionSelected,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: child,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.9),
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Text(
                      'AI can make mistakes. Verify important information.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.62,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _themeIcon(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.system => Icons.brightness_auto_outlined,
    };
  }

  PopupMenuItem<ThemeMode> _themeMenuItem(
    BuildContext context, {
    required ThemeMode mode,
    required bool selected,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          if (selected)
            Icon(
              Icons.check_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }

  String _initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }
}

class _SectionNav extends StatelessWidget {
  const _SectionNav({
    required this.section,
    required this.extended,
    required this.onSectionSelected,
  });

  final ConsoleSection section;
  final bool extended;
  final ValueChanged<ConsoleSection> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final destinations =
        <({ConsoleSection section, IconData icon, String label})>[
          (
            section: ConsoleSection.chat,
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Chat',
          ),
          (
            section: ConsoleSection.scheduler,
            icon: Icons.event_repeat_rounded,
            label: 'Scheduler',
          ),
          (
            section: ConsoleSection.tools,
            icon: Icons.build_circle_outlined,
            label: 'Tools',
          ),
        ];

    if (!extended) {
      return NavigationRail(
        selectedIndex: destinations.indexWhere(
          (item) => item.section == section,
        ),
        onDestinationSelected: (index) {
          onSectionSelected(destinations[index].section);
        },
        labelType: NavigationRailLabelType.all,
        destinations: [
          for (final item in destinations)
            NavigationRailDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.icon),
              label: Text(item.label),
            ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      children: [
        for (final item in destinations)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SectionButton(
              icon: item.icon,
              label: item.label,
              selected: item.section == section,
              onTap: () => onSectionSelected(item.section),
            ),
          ),
      ],
    );
  }
}

class _SectionButton extends StatelessWidget {
  const _SectionButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.8);

    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: foreground),
              const SizedBox(width: 12),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
