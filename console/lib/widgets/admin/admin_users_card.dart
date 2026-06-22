import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/promptd_models.dart';
import '../../state/promptd_app_state.dart';
import '../common/app_ui.dart';
import 'admin_card.dart';

class AdminUsersCard extends StatefulWidget {
  const AdminUsersCard({super.key, required this.state});

  final PromptdAppState state;

  @override
  State<AdminUsersCard> createState() => _AdminUsersCardState();
}

class _AdminUsersCardState extends State<AdminUsersCard> {
  final _filterCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.state.adminAuthConfig.users;
    final users = _filter.isEmpty
        ? all
        : all.where((u) => u.id.toLowerCase().contains(_filter)).toList();

    return AdminCard(
      title: 'Users',
      icon: Icons.people_alt_outlined,
      action: AppButton(
        label: 'User',
        icon: Icons.add_rounded,
        onPressed: () => _showUserDialog(context),
      ),
      filter: AdminFilterField(
        controller: _filterCtrl,
        hint: 'Filter users…',
        active: _filter.isNotEmpty,
        onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
        onClear: () {
          _filterCtrl.clear();
          setState(() => _filter = '');
        },
      ),
      emptyMessage: all.isEmpty ? 'No users' : 'No matches for "$_filter"',
      children: [
        for (final user in users)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(user.id),
            subtitle: Text(_userSubtitle(user)),
            trailing: Wrap(
              spacing: 4,
              children: [
                if (user.disabled) const AppPill(label: 'Disabled', tone: AppTone.neutral),
                if (user.mustChangePassword)
                  const AppPill(label: 'Change password', tone: AppTone.warning),
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
                  onPressed: user.id == widget.state.me?.userId
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
      builder: (ctx) => _ApiKeysDialog(state: widget.state, user: user),
    );
  }

  Future<void> _deleteUser(BuildContext context, String id) async {
    final ok = await showConfirmDialog(context, title: 'Delete user?', message: 'Delete "$id"?');
    if (ok) await widget.state.deleteAdminUser(id);
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
                    const AdminFormSectionLabel('Roles'),
                    const SizedBox(height: 6),
                    if (widget.state.adminAuthConfig.roles.isEmpty)
                      const Text('No roles defined')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final role in widget.state.adminAuthConfig.roles)
                            AppFilterChip(
                              label: role.name,
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
              AppButton(
                label: 'Save',
                onPressed: canSave ? () => Navigator.pop(context, true) : null,
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      await widget.state.saveAdminUser(
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
              child: AppButton(
                label: 'Generate new API key',
                icon: Icons.add_rounded,
                onPressed: () => _generateKey(context),
                loading: _loading,
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

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final generated = await widget.state.generateApiKey(
        _user.id,
        description: result.description,
        expiresAt: result.expiresAt,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      if (!mounted) return;
      await showDialog<void>(
        context: context, // ignore: use_build_context_synchronously
        barrierDismissible: false,
        builder: (ctx) => _ApiKeyGeneratedDialog(token: generated.token),
      );
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _deleteKey(ApiKey key) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete API key?',
      message: 'Key "${key.description.isNotEmpty ? key.description : key.id}" will be permanently deleted.',
    );

    if (!confirmed || !mounted) return;

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

    final statusTone = isExpired
        ? AppTone.danger
        : apiKey.disabled
            ? AppTone.neutral
            : AppTone.success;
    final statusLabel = isExpired ? 'Expired' : apiKey.disabled ? 'Disabled' : 'Active';

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
          AppPill(label: statusLabel, tone: statusTone),
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
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
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
      _expiryTime = time;
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
        AppButton(
          label: 'Generate',
          onPressed: () => Navigator.of(context).pop((
            description: _descCtrl.text.trim(),
            expiresAt: _expiresAt,
          )),
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
        AppButton(
          label: "I've copied the key",
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
