import 'package:flutter/material.dart';

import '../../models/promptd_models.dart';
import '../../state/promptd_app_state.dart';
import '../common/app_ui.dart';
import '../search_select_field.dart';

const _cronPresets = <({String label, String value})>[
  (label: 'Every min', value: '0 * * * * *'),
  (label: '5 min', value: '0 */5 * * * *'),
  (label: '15 min', value: '0 */15 * * * *'),
  (label: '30 min', value: '0 */30 * * * *'),
  (label: '1 hour', value: '0 0 * * * *'),
  (label: 'Daily 00:00', value: '0 0 0 * * *'),
  (label: 'Daily 08:00', value: '0 0 8 * * *'),
  (label: 'Weekly (Sun)', value: '0 0 0 * * 0'),
  (label: 'Monthly', value: '0 0 0 1 * *'),
];

const _retainPresets = <int>[0, 5, 10, 20, 50];

class ScheduleFormPanel extends StatefulWidget {
  const ScheduleFormPanel({
    super.key,
    required this.state,
    required this.initial,
    required this.onSaved,
    required this.onCancel,
    this.onBack,
  });

  final PromptdAppState state;
  final Schedule? initial;
  final ValueChanged<Schedule> onSaved;
  final VoidCallback onCancel;
  final VoidCallback? onBack;

  @override
  State<ScheduleFormPanel> createState() => _ScheduleFormPanelState();
}

class _ScheduleFormPanelState extends State<ScheduleFormPanel> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _promptController;
  late final TextEditingController _cronController;
  late final TextEditingController _retainController;
  late final TextEditingController _temperatureController;
  late final TextEditingController _maxTokensController;
  late final TextEditingController _topPController;
  late final TextEditingController _topKController;
  late bool _enabled;
  late String _type;
  late String? _provider;
  late String? _modelId;
  late String? _systemPrompt;
  late String _traceMode;
  late DateTime? _runAt;
  late Set<String> _allowedTools;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _promptController = TextEditingController(text: initial?.prompt ?? '');
    _cronController = TextEditingController(
      text: initial?.cronExpr ?? '0 0 * * * *',
    );
    _retainController = TextEditingController(
      text: '${initial?.retainHistory ?? 10}',
    );
    _temperatureController = TextEditingController(
      text: initial?.params?.temperature?.toString() ?? '',
    );
    _maxTokensController = TextEditingController(
      text: initial?.params?.maxTokens?.toString() ?? '',
    );
    _topPController = TextEditingController(
      text: initial?.params?.topP?.toString() ?? '',
    );
    _topKController = TextEditingController(
      text: initial?.params?.topK?.toString() ?? '',
    );
    _enabled = initial?.enabled ?? true;
    _type = initial?.type == 'once' ? 'once' : 'cron';
    _provider = initial?.provider;
    _modelId = initial?.modelId;
    _systemPrompt =
        initial?.systemPrompt ??
        widget.state.uiConfig.systemPrompts.firstOrNull?.name;
    _traceMode = initial?.traceEnabled == null
        ? 'default'
        : initial!.traceEnabled!
        ? 'on'
        : 'off';
    _runAt = initial?.runAt;
    _allowedTools = {...?initial?.allowedTools};
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    _cronController.dispose();
    _retainController.dispose();
    _temperatureController.dispose();
    _maxTokensController.dispose();
    _topPController.dispose();
    _topKController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final models = _provider == null || _provider!.isEmpty
        ? widget.state.modelData.models
        : widget.state.modelData.models
              .where((model) => model.provider == _provider)
              .toList();
    final providerNames = widget.state.modelData.providers
        .map((provider) => provider.name)
        .toList();

    return Card(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
              child: Row(
                children: [
                  if (widget.onBack != null) ...[
                    IconButton(
                      tooltip: 'Back to schedules',
                      onPressed: widget.onBack,
                      mouseCursor: SystemMouseCursors.click,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      widget.initial == null
                          ? 'Create Schedule'
                          : 'Edit Schedule',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Switch(
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Enabled', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionTitle('Schedule'),
                  TextFormField(
                    controller: _nameController,
                    style: theme.textTheme.bodyLarge,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'Daily summary',
                    ),
                    validator: _required('Name is required'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _promptController,
                    style: theme.textTheme.bodyLarge,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Prompt',
                      hintText:
                          'Write a concise summary of today\'s key events...',
                      helperText:
                          'Sent to the model as the user message on every execution.',
                      alignLabelWithHint: true,
                    ),
                    validator: _required('Prompt is required'),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'cron', label: Text('Recurring')),
                      ButtonSegment(value: 'once', label: Text('One-time')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (value) {
                      setState(() => _type = value.first);
                    },
                    style: const ButtonStyle(
                      mouseCursor: WidgetStatePropertyAll(
                        SystemMouseCursors.click,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_type == 'cron')
                    _cronField(theme)
                  else
                    _runAtField(theme),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoCol = constraints.maxWidth >= 620;
                      final children = [
                        _retainHistory(theme),
                        _traceModeSelector(theme),
                      ];
                      if (!twoCol) {
                        return Column(
                          children: [
                            children[0],
                            const SizedBox(height: 12),
                            children[1],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: children[0]),
                          const SizedBox(width: 12),
                          Expanded(child: children[1]),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _SectionTitle('Model'),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoCol = constraints.maxWidth >= 620;
                      final providerField = SearchSelectField<String>(
                        label: 'Provider',
                        width: double.infinity,
                        value: _provider ?? '',
                        enabled: true,
                        options: [
                          const SearchSelectOption(
                            value: '',
                            label: 'Auto',
                            subtitle: 'Server selects provider',
                          ),
                          for (final name in providerNames)
                            SearchSelectOption(value: name, label: name),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _provider = value?.isEmpty == true ? null : value;
                            _modelId = null;
                          });
                        },
                      );
                      final modelField = SearchSelectField<String>(
                        label: 'Model',
                        width: double.infinity,
                        value: _modelId ?? '',
                        enabled: models.isNotEmpty,
                        emptyText: 'No models',
                        options: [
                          const SearchSelectOption(
                            value: '',
                            label: 'Auto',
                            subtitle: 'Use server/model default',
                          ),
                          for (final model in models)
                            SearchSelectOption(
                              value: model.id,
                              label: model.label,
                              subtitle: [
                                if (model.provider?.isNotEmpty == true)
                                  model.provider!,
                                model.id,
                                if (model.source?.isNotEmpty == true)
                                  model.source!,
                              ].join(' · '),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _modelId = value?.isEmpty == true ? null : value;
                          });
                        },
                      );
                      if (!twoCol) {
                        return Column(
                          children: [
                            providerField,
                            const SizedBox(height: 12),
                            modelField,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: providerField),
                          const SizedBox(width: 12),
                          Expanded(child: modelField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SearchSelectField<String>(
                    label: 'System prompt',
                    width: double.infinity,
                    value: _systemPrompt,
                    enabled: widget.state.uiConfig.systemPrompts.isNotEmpty,
                    emptyText: 'No prompts',
                    options: [
                      for (final prompt in widget.state.uiConfig.systemPrompts)
                        SearchSelectOption(
                          value: prompt.name,
                          label: prompt.name,
                        ),
                    ],
                    onChanged: (value) => setState(() => _systemPrompt = value),
                  ),
                  const SizedBox(height: 16),
                  _allowedToolsField(theme),
                  const SizedBox(height: 20),
                  _SectionTitle('LLM Parameters'),
                  Text(
                    'Leave blank to use model or global defaults.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  _paramsGrid(theme),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: widget.initial == null
                        ? 'Create schedule'
                        : 'Save changes',
                    icon: Icons.save_rounded,
                    onPressed: _save,
                    loading: _saving,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cronField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _cronController,
          style: theme.textTheme.bodyLarge,
          decoration: const InputDecoration(
            labelText: 'Cron expression',
            helperText: '6-field: seconds minutes hours day month weekday',
          ),
          validator: _required('Cron expression is required'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in _cronPresets)
              AppChoiceChip(
                label: preset.label,
                selected: _cronController.text == preset.value,
                onSelected: () {
                  setState(() => _cronController.text = preset.value);
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _runAtField(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Run at', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  _runAt == null
                      ? 'No date selected'
                      : _runAt!.toLocal().toString(),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _pickRunAt,
            icon: const Icon(Icons.calendar_month_rounded),
            label: const Text('Select'),
          ),
        ],
      ),
    );
  }

  Widget _retainHistory(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _retainController,
          style: theme.textTheme.bodyLarge,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Keep last N executions',
            helperText: '0 = keep all',
          ),
          validator: (value) {
            final parsed = int.tryParse(value?.trim() ?? '');
            if (parsed == null || parsed < 0 || parsed > 1000) {
              return 'Use 0-1000';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final preset in _retainPresets)
              AppChoiceChip(
                label: preset == 0 ? 'All' : '$preset',
                selected: _retainController.text == '$preset',
                onSelected: () {
                  setState(() => _retainController.text = '$preset');
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _traceModeSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LLM trace', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'default', label: Text('Default')),
            ButtonSegment(value: 'on', label: Text('On')),
            ButtonSegment(value: 'off', label: Text('Off')),
          ],
          selected: {_traceMode},
          onSelectionChanged: (value) {
            setState(() => _traceMode = value.first);
          },
          style: const ButtonStyle(
            mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Default follows global config.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _allowedToolsField(ThemeData theme) {
    if (widget.state.tools.isEmpty) return const SizedBox.shrink();
    final selected = _allowedTools.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _showAllowedToolsDialog,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Allowed tools',
              helperText: 'Leave as all tools unless this schedule needs limits.',
              suffixIcon: Icon(Icons.arrow_drop_down_rounded),
            ),
            child: Text(
              _allowedTools.isEmpty
                  ? 'All tools'
                  : selected.take(4).join(', ') +
                        (selected.length > 4 ? ' +${selected.length - 4} more' : ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAllowedToolsDialog() async {
    final tools = [...widget.state.tools]..sort((a, b) => a.name.compareTo(b.name));
    final selected = {..._allowedTools};
    final searchController = TextEditingController();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = searchController.text.trim().toLowerCase();
          final visible = tools.where((tool) {
            return query.isEmpty ||
                tool.name.toLowerCase().contains(query) ||
                tool.description.toLowerCase().contains(query);
          }).toList();
          return AlertDialog(
            title: const Text('Allowed tools'),
            content: SizedBox(
              width: 520,
              height: 520,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search tools',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  CheckboxListTile(
                    value: selected.isEmpty,
                    title: const Text('All tools'),
                    subtitle: const Text('No explicit tool restriction'),
                    onChanged: (_) => setDialogState(selected.clear),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final tool = visible[index];
                        return CheckboxListTile(
                          value: selected.contains(tool.name),
                          title: Text(tool.name),
                          subtitle: tool.description.isEmpty
                              ? null
                              : Text(tool.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              selected.add(tool.name);
                            } else {
                              selected.remove(tool.name);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              AppButton(label: 'Apply', onPressed: () => Navigator.pop(context, selected)),
            ],
          );
        },
      ),
    );
    searchController.dispose();
    if (result != null) setState(() => _allowedTools = result);
  }

  Widget _paramsGrid(ThemeData theme) {
    final fields = [
      _numberField(
        controller: _temperatureController,
        label: 'Temperature',
        helper: '0 = deterministic · 2 = random',
      ),
      _numberField(
        controller: _maxTokensController,
        label: 'Max tokens',
        helper: 'Maximum output tokens',
      ),
      _numberField(
        controller: _topPController,
        label: 'Top P',
        helper: 'Nucleus sampling (0-1)',
      ),
      _numberField(
        controller: _topKController,
        label: 'Top K',
        helper: 'Provider-specific',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 4
            : width >= 520
            ? 2
            : 1;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final field in fields)
              SizedBox(
                width: (width - (columns - 1) * 12) / columns,
                child: field,
              ),
          ],
        );
      },
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String helper,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        hintText: 'default',
      ),
    );
  }

  Future<void> _pickRunAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _runAt ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_runAt ?? now),
    );
    if (time == null) return;
    setState(() {
      _runAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_type == 'once' && _runAt == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Run at is required')));
      return;
    }

    setState(() => _saving = true);
    try {
      final params = LlmParams(
        temperature: _doubleOrNull(_temperatureController.text),
        maxTokens: _intOrNull(_maxTokensController.text),
        topP: _doubleOrNull(_topPController.text),
        topK: _intOrNull(_topKController.text),
      );
      final payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'prompt': _promptController.text.trim(),
        'enabled': _enabled,
        'type': _type,
        'retainHistory': int.parse(_retainController.text.trim()),
        if (_type == 'cron') 'cronExpr': _cronController.text.trim(),
        if (_type == 'once') 'runAt': _runAt!.toUtc().toIso8601String(),
        if (_provider?.isNotEmpty == true) 'provider': _provider,
        if (_modelId?.isNotEmpty == true) 'modelId': _modelId,
        if (_systemPrompt?.isNotEmpty == true) 'systemPrompt': _systemPrompt,
        'allowedTools': _allowedTools.isEmpty ? null : _allowedTools.toList(),
        'params': params.isEmpty ? null : params.toJson(),
        'traceEnabled': switch (_traceMode) {
          'on' => true,
          'off' => false,
          _ => null,
        },
      };
      final saved = await widget.state.saveSchedule(
        id: widget.initial?.id,
        schedule: payload,
      );
      if (!mounted) return;
      widget.onSaved(saved);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $err')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  FormFieldValidator<String> _required(String message) {
    return (value) => value == null || value.trim().isEmpty ? message : null;
  }

  double? _doubleOrNull(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  int? _intOrNull(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
