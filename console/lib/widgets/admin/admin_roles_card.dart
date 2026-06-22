import 'package:flutter/material.dart';

import '../../models/promptd_models.dart';
import '../../state/promptd_app_state.dart';
import '../common/app_ui.dart';
import 'admin_card.dart';

class AdminRolesCard extends StatefulWidget {
  const AdminRolesCard({super.key, required this.state});

  final PromptdAppState state;

  @override
  State<AdminRolesCard> createState() => _AdminRolesCardState();
}

class _AdminRolesCardState extends State<AdminRolesCard> {
  final _filterCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.state.adminAuthConfig.roles;
    final roles = _filter.isEmpty
        ? all
        : all.where((r) => r.name.toLowerCase().contains(_filter)).toList();

    return AdminCard(
      title: 'Roles',
      icon: Icons.badge_outlined,
      action: AppButton(
        label: 'Role',
        icon: Icons.add_rounded,
        onPressed: () => _showRoleDialog(context),
      ),
      filter: AdminFilterField(
        controller: _filterCtrl,
        hint: 'Filter roles…',
        active: _filter.isNotEmpty,
        onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
        onClear: () {
          _filterCtrl.clear();
          setState(() => _filter = '');
        },
      ),
      emptyMessage: all.isEmpty ? 'No roles' : 'No matches for "$_filter"',
      children: [
        for (final role in roles)
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
    final ok = await showConfirmDialog(context, title: 'Delete role?', message: 'Delete "$name"?');
    if (ok) await widget.state.deleteAdminRole(name);
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
                      const AdminFormSectionLabel('Permissions'),
                      _permissionSwitches(p, (next) => setState(() => p = next)),
                      const SizedBox(height: 12),
                      const AdminFormSectionLabel('Allow rules'),
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
      await widget.state.saveAdminRole(AdminRole(
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
