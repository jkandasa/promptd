import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/chat_console_page.dart';
import 'pages/admin_console_page.dart';
import 'pages/change_password_page.dart';
import 'pages/login_page.dart';
import 'pages/scheduler_console_page.dart';
import 'pages/tools_console_page.dart';
import 'services/promptd_api_client.dart';
import 'services/session_store.dart';
import 'state/promptd_app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';

class PromptdConsoleApp extends StatefulWidget {
  const PromptdConsoleApp({super.key});

  @override
  State<PromptdConsoleApp> createState() => _PromptdConsoleAppState();
}

class _PromptdConsoleAppState extends State<PromptdConsoleApp> {
  static const _themeModeKey = 'promptd.console.themeMode';

  ThemeMode _themeMode = ThemeMode.light;
  late final PromptdAppState _state;

  @override
  void initState() {
    super.initState();
    _state = PromptdAppState(
      api: PromptdApiClient(),
      sessionStore: SessionStore(),
    )..initialize();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeModeKey);
    final mode = switch (value) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
    });
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Promptd Console',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          if (_state.initializing) {
            return const _WebSelectable(child: _LoadingScreen());
          }
          if (!_state.isAuthenticated) {
            return _WebSelectable(child: LoginPage(state: _state));
          }
          if (_state.me!.mustChangePassword) {
            return _WebSelectable(child: ChangePasswordPage(state: _state));
          }
          return _WebSelectable(
            child: AppShell(
              section: _state.section,
              themeMode: _themeMode,
              me: _state.me!,
              serverUrl: _state.serverUrl,
              loading: _state.loadingData,
              onSectionSelected: _state.selectSection,
              onRefresh: _state.refreshAppData,
              onLogout: _state.logout,
              onThemeModeChanged: _setThemeMode,
              child: switch (_state.section) {
                ConsoleSection.chat => ChatConsolePage(state: _state),
                ConsoleSection.scheduler => SchedulerConsolePage(state: _state),
                ConsoleSection.tools => ToolsConsolePage(state: _state),
                ConsoleSection.admin => AdminConsolePage(state: _state),
              },
            ),
          );
        },
      ),
    );
  }
}

class _WebSelectable extends StatelessWidget {
  const _WebSelectable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return kIsWeb ? SelectionArea(child: child) : child;
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
