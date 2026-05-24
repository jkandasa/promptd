import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/promptd_models.dart';
import '../state/promptd_app_state.dart';
import '../widgets/common/app_ui.dart';

class AdminConsolePage extends StatefulWidget {
  const AdminConsolePage({super.key, required this.state});

  final PromptdAppState state;

  @override
  State<AdminConsolePage> createState() => _AdminConsolePageState();
}

class _AdminConsolePageState extends State<AdminConsolePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.state.refreshAdminData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              loading: widget.state.loadingData,
              onRefresh: widget.state.refreshAdminData,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: compact
                  ? ListView(children: _sections())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final section in _sections())
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: section,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _sections() => [
    _UsersCard(state: widget.state),
    _RolesCard(state: widget.state),
    _PromptsCard(state: widget.state),
  ];
}

class _Header extends StatelessWidget {
  const _Header({required this.loading, required this.onRefresh});

  final bool loading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Admin', style: theme.textTheme.headlineSmall),
              Text(
                'Manage users, roles, and system prompts.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Refresh',
          mouseCursor: SystemMouseCursors.click,
          onPressed: loading ? null : onRefresh,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

class _UsersCard extends StatelessWidget {
  const _UsersCard({required this.state});

  final PromptdAppState state;

  @override
  Widget build(BuildContext context) {
    return _AdminCard(
      title: 'Users',
      icon: Icons.people_alt_outlined,
      action: FilledButton.icon(
        onPressed: () => _showUserDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('User'),
      ),
      children: [
        for (final user in state.adminAuthConfig.users)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(user.id),
            subtitle: Text(_userSubtitle(user)),
            trailing: Wrap(
              spacing: 4,
              children: [
                if (user.disabled) const Chip(label: Text('Disabled')),
                if (user.mustChangePassword)
                  const Chip(label: Text('Change password')),
                IconButton(
                  tooltip: 'API Keys',
                  mouseCursor: SystemMouseCursors.click,
                  onPressed: () => _showApiKeysDialog(context, user),
                  icon: Badge(
                    isLabelVisible: user.apiKeys.isNotEmpty,
                    label: Text('${user.apiKeys.length}'),
                    child: const Icon(Icons.key_outlined),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  mouseCursor: SystemMouseCursors.click,
                  onPressed: () => _showUserDialog(context, user: user),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete',
                  mouseCursor: SystemMouseCursors.click,
                  onPressed: user.id == state.me?.userId
                      ? null
                      : () => _deleteUser(context, user.id),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _userSubtitle(AdminUser user) {
    final parts = [user.tenantId, if (user.roles.isNotEmpty) user.roles.join(', ')];
    return parts.join(' · ');
  }

  Future<void> _showApiKeysDialog(BuildContext context, AdminUser user) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ApiKeysDialog(state: state, user: user),
    );
  }

  Future<void> _deleteUser(BuildContext context, String id) async {
    final ok = await _confirm(context, 'Delete user?', 'Delete "$id"?');
    if (ok) await state.deleteAdminUser(id);
  }

  Future<void> _showUserDialog(BuildContext context, {AdminUser? user}) async {
    final isCreate = user == null;
    final idCtrl = TextEditingController(text: user?.id ?? '');
    final tenantCtrl = TextEditingController(text: user?.tenantId ?? 'default');
    final passwordCtrl = TextEditingController();
    final selected = {...?user?.roles};
    var disabled = user?.disabled ?? false;
    var mustChangePassword = user?.mustChangePassword ?? false;
    var passwordVisible = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final canSave = isCreate
              ? idCtrl.text.trim().isNotEmpty && passwordCtrl.text.isNotEmpty
              : true;
          return AlertDialog(
            title: Text(isCreate ? 'Create user' : 'Edit user'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: idCtrl,
                      enabled: isCreate,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'User ID',
                        hintText: 'e.g. alice',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tenantCtrl,
                      decoration: const InputDecoration(labelText: 'Tenant'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: !passwordVisible,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: isCreate ? 'Password' : 'New password (leave blank to keep)',
                        suffixIcon: IconButton(
                          mouseCursor: SystemMouseCursors.click,
                          icon: Icon(passwordVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(() => passwordVisible = !passwordVisible),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: disabled,
                      onChanged: (value) => setState(() => disabled = value),
                      title: const Text('Disabled'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: mustChangePassword,
                      onChanged: (value) => setState(() => mustChangePassword = value),
                      title: const Text('Require password change on next login'),
                    ),
                    const SizedBox(height: 8),
                    _FormSectionLabel('Roles'),
                    const SizedBox(height: 6),
                    if (state.adminAuthConfig.roles.isEmpty)
                      const Text('No roles defined')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final role in state.adminAuthConfig.roles)
                            FilterChip(
                              label: Text(role.name),
                              selected: selected.contains(role.name),
                              onSelected: (value) => setState(() =>
                                  value ? selected.add(role.name) : selected.remove(role.name)),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canSave ? () => Navigator.pop(context, true) : null,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      await state.saveAdminUser(
        id: idCtrl.text.trim(),
        tenantId: tenantCtrl.text.trim(),
        roles: selected.toList()..sort(),
        disabled: disabled,
        mustChangePassword: mustChangePassword,
        password: passwordCtrl.text,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// API Keys dialog
// ---------------------------------------------------------------------------

class _ApiKeysDialog extends StatefulWidget {
  const _ApiKeysDialog({required this.state, required this.user});

  final PromptdAppState state;
  final AdminUser user;

  @override
  State<_ApiKeysDialog> createState() => _ApiKeysDialogState();
}

class _ApiKeysDialogState extends State<_ApiKeysDialog> {
  bool _loading = false;
  String? _error;

  AdminUser get _user {
    // Pick the freshest copy from state so the list updates after operations.
    return widget.state.adminAuthConfig.users.firstWhere(
      (u) => u.id == widget.user.id,
      orElse: () => widget.user,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = _user.apiKeys;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.key_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('API Keys', style: theme.textTheme.titleLarge),
                        Text(
                          _user.id,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    mouseCursor: SystemMouseCursors.click,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            Expanded(
              child: keys.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.key_off_outlined,
                            size: 48,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No API keys yet',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: keys.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (_, i) => _ApiKeyTile(
                        key: ValueKey(keys[i].id),
                        apiKey: keys[i],
                        onDelete: () => _deleteKey(keys[i]),
                        onToggleDisabled: () => _toggleDisabled(keys[i]),
                      ),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _loading ? null : () => _generateKey(context),
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
                label: const Text('Generate new API key'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateKey(BuildContext context) async {
    final result = await showDialog<({String description, String expiresAt})>(
      context: context,
      builder: (ctx) => const _GenerateApiKeyDialog(),
    );

    if (result == null || !mounted) return;

    final description = result.description;
    final expiresAt = result.expiresAt;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final generated = await widget.state.generateApiKey(
        _user.id,
        description: description,
        expiresAt: expiresAt,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      final token = generated.token;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ApiKeyGeneratedDialog(token: token),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _deleteKey(ApiKey key) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete API key?'),
        content: Text(
          'Key "${key.description.isNotEmpty ? key.description : key.id}" will be permanently deleted and can no longer be used.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() { _loading = true; _error = null; });
    try {
      await widget.state.deleteApiKey(_user.id, key.id);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _toggleDisabled(ApiKey key) async {
    setState(() { _loading = true; _error = null; });
    try {
      await widget.state.updateApiKey(
        _user.id,
        key.id,
        description: key.description,
        disabled: !key.disabled,
        expiresAt: key.expiresAt ?? '',
      );
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }
}

class _ApiKeyTile extends StatelessWidget {
  const _ApiKeyTile({
    super.key,
    required this.apiKey,
    required this.onDelete,
    required this.onToggleDisabled,
  });

  final ApiKey apiKey;
  final VoidCallback onDelete;
  final VoidCallback onToggleDisabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = apiKey.isActive;
    final isExpired = apiKey.isExpired;

    Color statusColor;
    String statusLabel;
    if (isExpired) {
      statusColor = theme.colorScheme.error;
      statusLabel = 'Expired';
    } else if (apiKey.disabled) {
      statusColor = theme.colorScheme.secondary;
      statusLabel = 'Disabled';
    } else {
      statusColor = Colors.green;
      statusLabel = 'Active';
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(
        Icons.vpn_key_outlined,
        color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      title: Text(
        apiKey.description.isNotEmpty ? apiKey.description : apiKey.id,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ID: ${apiKey.id}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          Row(
            children: [
              if (apiKey.createdAt != null)
                Text(
                  'Created ${_shortDate(apiKey.createdAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              if (apiKey.expiresAt != null && apiKey.expiresAt!.isNotEmpty) ...[
                Text(
                  ' · Expires ${_shortDate(apiKey.expiresAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isExpired ? theme.colorScheme.error : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Chip(
            label: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11)),
            side: BorderSide(color: statusColor.withValues(alpha: 0.4)),
            backgroundColor: statusColor.withValues(alpha: 0.08),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'Key actions',
            style: const ButtonStyle(
              mouseCursor: WidgetStatePropertyAll(WidgetStateMouseCursor.clickable),
            ),
            onSelected: (v) {
              if (v == 'toggle') onToggleDisabled();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggle',
                mouseCursor: WidgetStateMouseCursor.clickable,
                child: Row(
                  children: [
                    Icon(apiKey.disabled ? Icons.check_circle_outline : Icons.block_outlined),
                    const SizedBox(width: 10),
                    Text(apiKey.disabled ? 'Enable' : 'Disable'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                mouseCursor: WidgetStateMouseCursor.clickable,
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                    const SizedBox(width: 10),
                    Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shortDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }
}

class _GenerateApiKeyDialog extends StatefulWidget {
  const _GenerateApiKeyDialog();

  @override
  State<_GenerateApiKeyDialog> createState() => _GenerateApiKeyDialogState();
}

class _GenerateApiKeyDialogState extends State<_GenerateApiKeyDialog> {
  final _descCtrl = TextEditingController();
  DateTime? _expiryDate;
  TimeOfDay? _expiryTime;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  String get _expiresAt {
    if (_expiryDate == null) return '';
    final t = _expiryTime ?? const TimeOfDay(hour: 23, minute: 59);
    final dt = DateTime.utc(
      _expiryDate!.year,
      _expiryDate!.month,
      _expiryDate!.day,
      t.hour,
      t.minute,
    );
    return dt.toIso8601String();
  }

  String get _expiryLabel {
    if (_expiryDate == null) return 'No expiry (never expires)';
    final t = _expiryTime ?? const TimeOfDay(hour: 23, minute: 59);
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${months[_expiryDate!.month - 1]} ${_expiryDate!.day}, ${_expiryDate!.year}  $h:$m UTC';
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: DateTime(now.year + 10),
      helpText: 'Select expiry date',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _expiryTime ?? const TimeOfDay(hour: 23, minute: 59),
      helpText: 'Select expiry time (UTC)',
    );
    if (!mounted) return;
    setState(() {
      _expiryDate = date;
      _expiryTime = time; // null means user dismissed — keep the date, default time
    });
  }

  void _clearExpiry() => setState(() {
    _expiryDate = null;
    _expiryTime = null;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasExpiry = _expiryDate != null;

    return AlertDialog(
      title: const Text('Generate API key'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _descCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'e.g. CI pipeline, production bot',
              ),
            ),
            const SizedBox(height: 16),
            Text('Expiry', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            InkWell(
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(10),
              onTap: _pickExpiry,
              child: InputDecorator(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.calendar_month_outlined),
                  suffixIcon: hasExpiry
                      ? IconButton(
                          mouseCursor: SystemMouseCursors.click,
                          tooltip: 'Clear expiry',
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: _clearExpiry,
                        )
                      : const Icon(Icons.arrow_drop_down_rounded),
                ),
                child: Text(
                  _expiryLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hasExpiry
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            description: _descCtrl.text.trim(),
            expiresAt: _expiresAt,
          )),
          child: const Text('Generate'),
        ),
      ],
    );
  }
}

class _ApiKeyGeneratedDialog extends StatefulWidget {
  const _ApiKeyGeneratedDialog({required this.token});

  final String token;

  @override
  State<_ApiKeyGeneratedDialog> createState() => _ApiKeyGeneratedDialogState();
}

class _ApiKeyGeneratedDialogState extends State<_ApiKeyGeneratedDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded),
          SizedBox(width: 10),
          Text('Copy your API key now'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
              ),
              child: Text(
                'This key is shown only once and cannot be retrieved again. '
                'Store it securely before closing this dialog.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
            const SizedBox(height: 16),
            Text('API Key', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      widget.token,
                      style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: _copied ? 'Copied!' : 'Copy',
                    mouseCursor: SystemMouseCursors.click,
                    icon: Icon(_copied ? Icons.check_circle_outline : Icons.copy_outlined),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.token));
                      setState(() => _copied = true);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Use this key as a Bearer token:\nAuthorization: Bearer ${widget.token}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("I've copied the key"),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Roles
// ---------------------------------------------------------------------------

class _RolesCard extends StatelessWidget {
  const _RolesCard({required this.state});

  final PromptdAppState state;

  @override
  Widget build(BuildContext context) {
    return _AdminCard(
      title: 'Roles',
      icon: Icons.badge_outlined,
      action: FilledButton.icon(
        onPressed: () => _showRoleDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Role'),
      ),
      children: [
        for (final role in state.adminAuthConfig.roles)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(role.name),
            subtitle: Text(role.superAdmin ? 'Super admin' : _permissionSummary(role.permissions)),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'Edit',
                  mouseCursor: SystemMouseCursors.click,
                  onPressed: () => _showRoleDialog(context, role: role),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete',
                  mouseCursor: SystemMouseCursors.click,
                  onPressed: () => _deleteRole(context, role.name),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _deleteRole(BuildContext context, String name) async {
    final ok = await _confirm(context, 'Delete role?', 'Delete "$name"?');
    if (ok) await state.deleteAdminRole(name);
  }

  Future<void> _showRoleDialog(BuildContext context, {AdminRole? role}) async {
    final isCreate = role == null;
    final nameCtrl = TextEditingController(text: role?.name ?? '');
    final modelsCtrl = TextEditingController(text: role?.models.allow.join('\n') ?? '*');
    final toolsCtrl = TextEditingController(text: role?.tools.allow.join('\n') ?? '*');
    final promptsCtrl = TextEditingController(text: role?.systemPrompts.allow.join('\n') ?? '*');
    var superAdmin = role?.superAdmin ?? false;
    var p = role?.permissions ?? const Permissions();

    const allowRulesHint = 'One entry per line. Use * to allow all.';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final canSave = nameCtrl.text.trim().isNotEmpty;
          return AlertDialog(
            title: Text(isCreate ? 'Create role' : 'Edit role'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      enabled: isCreate,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Role name',
                        hintText: 'e.g. editor',
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: superAdmin,
                      onChanged: (value) => setState(() => superAdmin = value),
                      title: const Text('Super admin'),
                      subtitle: const Text('Bypasses all permission and allow-rule checks'),
                    ),
                    if (!superAdmin) ...[
                      const SizedBox(height: 8),
                      _FormSectionLabel('Permissions'),
                      _permissionSwitches(p, (next) => setState(() => p = next)),
                      const SizedBox(height: 12),
                      _FormSectionLabel('Allow rules'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: modelsCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Models',
                          hintText: allowRulesHint,
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: toolsCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Tools',
                          hintText: allowRulesHint,
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: promptsCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'System prompts',
                          hintText: allowRulesHint,
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canSave ? () => Navigator.pop(context, true) : null,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      await state.saveAdminRole(AdminRole(
        name: nameCtrl.text.trim(),
        superAdmin: superAdmin,
        permissions: p,
        models: RolePolicy(allow: _lines(modelsCtrl.text)),
        tools: RolePolicy(allow: _lines(toolsCtrl.text)),
        systemPrompts: RolePolicy(allow: _lines(promptsCtrl.text)),
      ));
    }
  }
}

// ---------------------------------------------------------------------------
// System Prompts
// ---------------------------------------------------------------------------

class _PromptsCard extends StatelessWidget {
  const _PromptsCard({required this.state});

  final PromptdAppState state;

  @override
  Widget build(BuildContext context) {
    return _AdminCard(
      title: 'System Prompts',
      icon: Icons.article_outlined,
      action: FilledButton.icon(
        onPressed: () => _showPromptDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Prompt'),
      ),
      children: [
        for (final prompt in state.managedSystemPrompts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(prompt.name),
            subtitle: Text(prompt.content, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'Edit',
                  mouseCursor: SystemMouseCursors.click,
                  onPressed: () => _showPromptDialog(context, prompt: prompt),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete',
                  mouseCursor: SystemMouseCursors.click,
                  onPressed: () => _deletePrompt(context, prompt.name),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _deletePrompt(BuildContext context, String name) async {
    final ok = await _confirm(context, 'Delete prompt?', 'Delete "$name"?');
    if (ok) await state.deleteSystemPrompt(name);
  }

  Future<void> _showPromptDialog(BuildContext context, {ManagedSystemPrompt? prompt}) async {
    final isCreate = prompt == null;
    final nameCtrl = TextEditingController(text: prompt?.name ?? '');
    final contentCtrl = TextEditingController(text: prompt?.content ?? '');
    var previewMode = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final canSave = nameCtrl.text.trim().isNotEmpty && contentCtrl.text.trim().isNotEmpty;
          final theme = Theme.of(context);
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isCreate ? 'Create system prompt' : 'Edit system prompt',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          mouseCursor: SystemMouseCursors.click,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context, false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Name field
                    TextField(
                      controller: nameCtrl,
                      enabled: isCreate,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'e.g. assistant-v1',
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Content label + Edit/Preview toggle
                    Row(
                      children: [
                        _FormSectionLabel('Prompt content'),
                        const Spacer(),
                        SegmentedButton<bool>(
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Edit'),
                              icon: Icon(Icons.edit_outlined, size: 15),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('Preview'),
                              icon: Icon(Icons.visibility_outlined, size: 15),
                            ),
                          ],
                          selected: {previewMode},
                          onSelectionChanged: (s) => setState(() => previewMode = s.first),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Content area — fills remaining space
                    Expanded(
                      child: previewMode
                          ? _MarkdownPreview(text: contentCtrl.text)
                          : TextField(
                              controller: contentCtrl,
                              expands: true,
                              maxLines: null,
                              onChanged: (_) => setState(() {}),
                              textAlignVertical: TextAlignVertical.top,
                              decoration: const InputDecoration(
                                hintText: 'Enter system prompt text…',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.all(12),
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    // Action row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: canSave ? () => Navigator.pop(context, true) : null,
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (result == true) {
      await state.saveSystemPrompt(
        ManagedSystemPrompt(name: nameCtrl.text.trim(), content: contentCtrl.text),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Shared card shell
// ---------------------------------------------------------------------------

class _AdminCard extends StatelessWidget {
  const _AdminCard({
    required this.title,
    required this.icon,
    required this.action,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Widget action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppSurface(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
                action,
              ],
            ),
            const SizedBox(height: 12),
            if (children.isEmpty)
              const Padding(padding: EdgeInsets.all(12), child: Text('No records'))
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: text.trim().isEmpty
          ? Center(
              child: Text(
                'Nothing to preview',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: MarkdownBody(data: text),
            ),
    );
  }
}

class _FormSectionLabel extends StatelessWidget {
  const _FormSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }
}

Widget _permissionSwitches(Permissions p, ValueChanged<Permissions> onChanged) {
  SwitchListTile tile(String label, bool value, Permissions Function(bool) copy) =>
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: value,
        title: Text(label),
        onChanged: (v) => onChanged(copy(v)),
      );

  return Column(children: [
    tile('Chat', p.chat, (v) => p.copyWith(chat: v)),
    tile('Upload', p.upload, (v) => p.copyWith(upload: v)),
    tile('Conversations write', p.conversationsWrite, (v) => p.copyWith(conversationsWrite: v)),
    tile('Schedules write', p.schedulesWrite, (v) => p.copyWith(schedulesWrite: v)),
    tile('Traces read', p.tracesRead, (v) => p.copyWith(tracesRead: v)),
    tile('Admin', p.admin, (v) => p.copyWith(admin: v)),
  ]);
}

String _permissionSummary(Permissions p) {
  final values = [
    if (p.chat) 'chat',
    if (p.upload) 'upload',
    if (p.conversationsWrite) 'conversations',
    if (p.schedulesWrite) 'schedules',
    if (p.tracesRead) 'traces',
    if (p.admin) 'admin',
  ];
  return values.isEmpty ? 'No permissions' : values.join(', ');
}

List<String> _lines(String value) =>
    value.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

Future<bool> _confirm(BuildContext context, String title, String message) async {
  return await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  ) ?? false;
}
