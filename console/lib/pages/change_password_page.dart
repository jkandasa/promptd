import 'package:flutter/material.dart';

import '../state/promptd_app_state.dart';
import '../widgets/common/app_ui.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.state});

  final PromptdAppState state;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Change password', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('The initial admin password must be changed before continuing.'),
                  const SizedBox(height: 20),
                  TextField(controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
                  const SizedBox(height: 12),
                  TextField(controller: _next, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
                  const SizedBox(height: 12),
                  TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  AppButton(
                    label: 'Update password',
                    onPressed: _save,
                    loading: _saving,
                  ),
                  TextButton(onPressed: _saving ? null : widget.state.logout, child: const Text('Sign out')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_next.text != _confirm.text) {
      setState(() => _error = 'New passwords do not match');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.state.changePassword(currentPassword: _current.text, newPassword: _next.text);
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
