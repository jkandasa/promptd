import 'package:flutter/material.dart';
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
            subtitle: Text('${user.tenantId} · ${user.roles.join(', ')}'),
            trailing: Wrap(
              spacing: 4,
              children: [
                if (user.disabled) const Chip(label: Text('Disabled')),
                if (user.mustChangePassword)
                  const Chip(label: Text('Change password')),
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
