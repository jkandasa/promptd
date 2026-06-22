import 'package:flutter/material.dart';

import '../state/promptd_app_state.dart';
import '../widgets/common/app_ui.dart';
import '../widgets/admin/admin_prompts_card.dart';
import '../widgets/admin/admin_roles_card.dart';
import '../widgets/admin/admin_users_card.dart';

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
    AdminUsersCard(state: widget.state),
    AdminRolesCard(state: widget.state),
    AdminPromptsCard(state: widget.state),
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
        AppRefreshButton(loading: loading, onRefresh: onRefresh),
      ],
    );
  }
}
