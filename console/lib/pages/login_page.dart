import 'package:flutter/material.dart';

import '../state/promptd_app_state.dart';
import '../widgets/brand_mark.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.state});

  final PromptdAppState state;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _serverUrlController;
  final _userIdController = TextEditingController();
  final _passwordController = TextEditingController();
  late bool _allowInsecureTls;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController(
      text: widget.state.serverUrl.isNotEmpty
          ? widget.state.serverUrl
          : _defaultServerUrl(),
    );
    _allowInsecureTls = widget.state.allowInsecureTls;
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _userIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const BrandMark(size: 52),
                              const SizedBox(height: 20),
                              Text(
                                'Sign in',
                                style: theme.textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Connect to your Promptd server.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.68,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _serverUrlController,
                                keyboardType: TextInputType.url,
                                autofillHints: const [AutofillHints.url],
                                decoration: const InputDecoration(
                                  labelText: 'Server URL',
                                  hintText: 'http://localhost:8080',
                                  prefixIcon: Icon(Icons.dns_outlined),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Server URL is required';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _userIdController,
                                autofillHints: const [AutofillHints.username],
                                decoration: const InputDecoration(
                                  labelText: 'User ID',
                                  prefixIcon: Icon(
                                    Icons.person_outline_rounded,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'User ID is required';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: true,
                                autofillHints: const [AutofillHints.password],
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: Icon(Icons.lock_outline_rounded),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Password is required';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _allowInsecureTls,
                                title: const Text('Allow insecure TLS'),
                                subtitle: const Text(
                                  'For self-signed server certificates',
                                ),
                                onChanged: (value) {
                                  setState(() => _allowInsecureTls = value);
                                },
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 16),
                                _LoginError(message: _error!),
                              ],
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: widget.state.signingIn
                                      ? null
                                      : _submit,
                                  icon: widget.state.signingIn
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.login_rounded),
                                  label: const Text('Sign in'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Text(
                'AI can make mistakes. Verify important information.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await widget.state.login(
        serverUrl: _serverUrlController.text,
        userId: _userIdController.text.trim(),
        password: _passwordController.text,
        allowInsecureTls: _allowInsecureTls,
      );
    } catch (err) {
      setState(() => _error = err.toString());
    }
  }

  String _defaultServerUrl() {
    final base = Uri.base;
    if (base.hasScheme &&
        base.host.isNotEmpty &&
        base.scheme.startsWith('http')) {
      return '${base.scheme}://${base.authority}';
    }
    return 'http://localhost:8080';
  }
}

class _LoginError extends StatelessWidget {
  const _LoginError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
