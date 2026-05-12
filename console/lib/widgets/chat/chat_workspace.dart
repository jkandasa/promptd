import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/promptd_models.dart';
import '../../state/promptd_app_state.dart';
import '../brand_mark.dart';
import '../search_select_field.dart';
import 'message_bubble.dart';

const _maxUploadBytes = 10 * 1024 * 1024;
const _maxUploadFiles = 10;

class ChatWorkspace extends StatefulWidget {
  const ChatWorkspace({super.key, required this.state, this.leading});

  final PromptdAppState state;
  final Widget? leading;

  @override
  State<ChatWorkspace> createState() => _ChatWorkspaceState();
}

class _ChatWorkspaceState extends State<ChatWorkspace> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  List<UploadedFile> _uploadedFiles = const [];
  bool _uploading = false;
  int _lastMessageCount = 0;
  bool _lastSending = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final inputLines = _inputLines(MediaQuery.sizeOf(context));
    final lineHeight = (theme.textTheme.bodyLarge?.fontSize ?? 16) * 1.45;
    final inputMinHeight = (lineHeight * inputLines) + 58;
    final canUpload = state.me?.permissions.upload ?? false;
    final canCompact =
        state.chatMode == 'chat' &&
        (state.uiConfig.compactConversation?.enabled ?? false) &&
        (state.me?.permissions.compactConversationWrite ?? false) &&
        (state.selectedConversationId != null || state.messages.isNotEmpty);
    _scheduleScrollIfNeeded(state);

    if (!state.me!.permissions.chat) {
      return const Card(
        child: Center(child: Text('Chat access is not enabled for this user.')),
      );
    }

    return Card(
      child: Column(
        children: [
          _ChatToolbar(state: state, leading: widget.leading),
          const Divider(height: 1),
          Expanded(
            child:
                state.loadingData &&
                    state.selectedConversationId != null &&
                    state.messages.isEmpty
                ? const _ConversationLoadingState()
                : state.messages.isEmpty
                ? _EmptyChat(state: state, onPrompt: _send)
                : ListView.separated(
                    controller: _scrollController,
                    cacheExtent: 1200,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                    itemCount: state.messages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return RepaintBoundary(
                        child: MessageBubble(
                          key: ValueKey(state.messages[index].id),
                          message: state.messages[index],
                          onDelete: state.deleteMessage,
                          onEdit: state.editMessage,
                          loadFileBytes: state.api.downloadFile,
                        ),
                      );
                    },
                  ),
          ),
          if (state.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              decoration: BoxDecoration(
                color: _softErrorColor(theme),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _softErrorBorderColor(theme)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: _softErrorAccentColor(theme),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.enter):
                        _SendMessageIntent(),
                    SingleActivator(LogicalKeyboardKey.numpadEnter):
                        _SendMessageIntent(),
                    SingleActivator(LogicalKeyboardKey.enter, shift: true):
                        _InsertNewlineIntent(),
                    SingleActivator(
                      LogicalKeyboardKey.numpadEnter,
                      shift: true,
                    ): _InsertNewlineIntent(),
                  },
                  child: Actions(
                    actions: {
                      _SendMessageIntent: CallbackAction<_SendMessageIntent>(
                        onInvoke: (_) {
                          if (!state.sending && !_uploading) {
                            _send(_inputController.text);
                          }
                          return null;
                        },
                      ),
                      _InsertNewlineIntent:
                          CallbackAction<_InsertNewlineIntent>(
                            onInvoke: (_) {
                              _insertNewline();
                              return null;
                            },
                          ),
                    },
                    child: Stack(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: inputMinHeight,
                          ),
                          child: TextField(
                            controller: _inputController,
                            minLines: inputLines,
                            maxLines: inputLines,
                            enabled: !_uploading,
                            autocorrect: true,
                            enableSuggestions: true,
                            spellCheckConfiguration:
                                const SpellCheckConfiguration.disabled(),
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.send,
                            onSubmitted: state.sending || _uploading
                                ? null
                                : _send,
                            decoration: InputDecoration(
                              hintText: 'Message Promptd',
                              contentPadding: EdgeInsets.fromLTRB(
                                14,
                                12,
                                canCompact ? 94 : 52,
                                58,
                              ),
                            ),
                          ),
                        ),
                        if (canUpload)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: SizedBox.square(
                              dimension: 34,
                              child: IconButton(
                                tooltip: _uploading
                                    ? 'Uploading...'
                                    : 'Attach file',
                                onPressed: state.sending || _uploading
                                    ? null
                                    : _pickFiles,
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                icon: _uploading
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.attach_file_rounded),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canCompact) ...[
                                SizedBox.square(
                                  dimension: 34,
                                  child: IconButton.filledTonal(
                                    tooltip: 'Compact conversation',
                                    onPressed: state.compacting
                                        ? null
                                        : () => _openCompactDialog(context),
                                    iconSize: 18,
                                    padding: EdgeInsets.zero,
                                    icon: state.compacting
                                        ? const SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.compress_rounded),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              SizedBox.square(
                                dimension: 34,
                                child: Tooltip(
                                  message: state.sending
                                      ? 'Stop processing'
                                      : 'Send',
                                  child: FilledButton(
                                    onPressed: _uploading
                                        ? null
                                        : state.sending
                                        ? state.stopProcessing
                                        : () => _send(_inputController.text),
                                    style: FilledButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      backgroundColor: state.sending
                                          ? theme.colorScheme.error
                                          : null,
                                      foregroundColor: state.sending
                                          ? theme.colorScheme.onError
                                          : null,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: state.sending
                                        ? const Icon(
                                            Icons.stop_rounded,
                                            size: 18,
                                          )
                                        : const Icon(
                                            Icons.send_rounded,
                                            size: 18,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_uploadedFiles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final file in _uploadedFiles)
                        InputChip(
                          avatar: Icon(
                            file.isImage
                                ? Icons.image_outlined
                                : Icons.description_outlined,
                            size: 18,
                          ),
                          label: Text(
                            '${file.filename} (${_fmtFileSize(file.size)})',
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: state.sending || _uploading
                              ? null
                              : () => _removeUploadedFile(file),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    final remaining = _maxUploadFiles - _uploadedFiles.length;
    if (remaining <= 0) {
      _showMessage('You can attach at most $_maxUploadFiles files');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final incoming = result.files.take(remaining).toList();
    if (result.files.length > remaining) {
      _showMessage('You can attach at most $_maxUploadFiles files');
    }
    final oversized = incoming
        .where((file) => file.size > _maxUploadBytes)
        .map((file) => file.name)
        .toList();
    if (oversized.isNotEmpty) {
      _showMessage('${oversized.join(', ')} exceed the 10 MB limit');
      return;
    }

    setState(() => _uploading = true);
    final uploaded = <UploadedFile>[];
    final failed = <String>[];
    try {
      for (final file in incoming) {
        final bytes = file.bytes;
        if (bytes == null) {
          failed.add(file.name);
          continue;
        }
        try {
          uploaded.add(
            await widget.state.api.uploadFile(
              filename: file.name,
              bytes: bytes,
            ),
          );
        } catch (_) {
          failed.add(file.name);
        }
      }
      if (!mounted) return;
      setState(() => _uploadedFiles = [..._uploadedFiles, ...uploaded]);
      if (failed.isNotEmpty) {
        _showMessage('Failed to upload: ${failed.join(', ')}');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _scheduleScrollIfNeeded(PromptdAppState state) {
    final messageCount = state.messages.length;
    final changed =
        messageCount != _lastMessageCount || state.sending != _lastSending;
    _lastMessageCount = messageCount;
    _lastSending = state.sending;
    if (!changed || messageCount == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _removeUploadedFile(UploadedFile file) async {
    setState(() {
      _uploadedFiles = [
        for (final item in _uploadedFiles)
          if (item.id != file.id) item,
      ];
    });
    await widget.state.api.deleteFile(file.id).catchError((_) {});
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send(String text) async {
    final files = _uploadedFiles;
    if (text.trim().isEmpty && files.isEmpty) return;
    _inputController.clear();
    setState(() => _uploadedFiles = const []);
    await widget.state.sendMessage(text, files: files);
  }

  void _insertNewline() {
    final value = _inputController.value;
    final selection = value.selection;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;
    final text = value.text.replaceRange(start, end, '\n');
    _inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  int _inputLines(Size size) {
    if (size.shortestSide < 520) return 2;
    if (size.width < 900 || size.height < 720) return 2;
    return 4;
  }

  Future<void> _openCompactDialog(BuildContext context) async {
    final promptController = TextEditingController(
      text: widget.state.uiConfig.compactConversation?.defaultPrompt ?? '',
    );
    String? selectedModel = widget.state.selectedModel;
    final shouldCompact = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Compact conversation'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: promptController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'Prompt'),
                ),
                const SizedBox(height: 12),
                SearchSelectField<String>(
                  label: 'Model',
                  width: double.infinity,
                  value: selectedModel,
                  enabled: widget.state.modelData.models.isNotEmpty,
                  emptyText: 'No models',
                  options: [
                    for (final model in widget.state.modelData.models)
                      SearchSelectOption(
                        value: model.id,
                        label: model.label,
                        subtitle: [
                          if (model.provider?.isNotEmpty == true)
                            model.provider!,
                          model.id,
                        ].join(' · '),
                      ),
                  ],
                  onChanged: (value) => selectedModel = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.compress_rounded),
              label: const Text('Compact'),
            ),
          ],
        );
      },
    );
    if (shouldCompact == true) {
      await widget.state.compactConversation(
        prompt: promptController.text,
        model: selectedModel,
      );
    }
    promptController.dispose();
  }
}

Color _softErrorColor(ThemeData theme) {
  return Color.lerp(
    theme.colorScheme.surface,
    theme.colorScheme.error,
    theme.brightness == Brightness.dark ? 0.16 : 0.08,
  )!;
}

Color _softErrorBorderColor(ThemeData theme) {
  return theme.colorScheme.error.withValues(
    alpha: theme.brightness == Brightness.dark ? 0.34 : 0.22,
  );
}

Color _softErrorAccentColor(ThemeData theme) {
  return Color.lerp(
    theme.colorScheme.error,
    theme.colorScheme.onSurface,
    theme.brightness == Brightness.dark ? 0.18 : 0.08,
  )!;
}

class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}

class _InsertNewlineIntent extends Intent {
  const _InsertNewlineIntent();
}

class _ChatToolbar extends StatelessWidget {
  const _ChatToolbar({required this.state, this.leading});

  final PromptdAppState state;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final providers = state.modelData.providers;
    final models = state.availableModels;
    final prompts = state.uiConfig.systemPrompts;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return _CompactChatToolbar(
            state: state,
            leading: leading,
            providers: providers,
            models: models,
            prompts: prompts,
          );
        }
        return _ExpandedChatToolbar(
          state: state,
          leading: leading,
          providers: providers,
          models: models,
          prompts: prompts,
        );
      },
    );
  }
}

class _ExpandedChatToolbar extends StatelessWidget {
  const _ExpandedChatToolbar({
    required this.state,
    required this.providers,
    required this.models,
    required this.prompts,
    this.leading,
  });

  final PromptdAppState state;
  final List<dynamic> providers;
  final List<dynamic> models;
  final List<dynamic> prompts;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ?leading,
          IconButton.filledTonal(
            tooltip: 'New chat',
            onPressed: state.startNewConversation,
            icon: const Icon(Icons.add_rounded),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'chat',
                icon: Icon(Icons.chat_bubble_outline_rounded),
                label: Text('Chat'),
              ),
              ButtonSegment(
                value: 'image_generation',
                icon: Icon(Icons.image_outlined),
                label: Text('Image'),
              ),
            ],
            selected: {state.chatMode},
            onSelectionChanged: (value) => state.selectChatMode(value.first),
          ),
          SearchSelectField<String>(
            label: 'System prompt',
            width: 240,
            value:
                prompts.any(
                  (prompt) => prompt.name == state.selectedSystemPrompt,
                )
                ? state.selectedSystemPrompt
                : null,
            enabled: prompts.isNotEmpty,
            emptyText: 'No prompts',
            options: [
              for (final prompt in prompts)
                SearchSelectOption(value: prompt.name, label: prompt.name),
            ],
            onChanged: state.selectSystemPrompt,
          ),
          SearchSelectField<String>(
            label: 'Provider',
            width: 190,
            value: state.selectedProvider,
            enabled: providers.isNotEmpty,
            emptyText: 'No providers',
            options: [
              for (final provider in providers)
                SearchSelectOption(
                  value: provider.name,
                  label: provider.name,
                  subtitle:
                      '${provider.count} models'
                      '${provider.source == null ? '' : ' · ${provider.source}'}',
                ),
            ],
            onChanged: state.selectProvider,
          ),
          SearchSelectField<String>(
            label: 'Model',
            width: 300,
            value: models.any((model) => model.id == state.selectedModel)
                ? state.selectedModel
                : null,
            enabled: models.isNotEmpty,
            emptyText: 'No models',
            options: [
              for (final model in models)
                SearchSelectOption(
                  value: model.id,
                  label: model.label,
                  subtitle: [
                    if (model.provider?.isNotEmpty == true) model.provider!,
                    model.id,
                    if (model.source?.isNotEmpty == true) model.source!,
                  ].join(' · '),
                ),
            ],
            onChanged: state.selectModel,
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            tooltip: 'Discover models',
            onPressed: () => state.refreshModels(discover: true),
            icon: const Icon(Icons.manage_search_rounded),
          ),
        ],
      ),
    );
  }
}

class _CompactChatToolbar extends StatelessWidget {
  const _CompactChatToolbar({
    required this.state,
    required this.providers,
    required this.models,
    required this.prompts,
    this.leading,
  });

  final PromptdAppState state;
  final List<dynamic> providers;
  final List<dynamic> models;
  final List<dynamic> prompts;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modeLabel = state.chatMode == 'image_generation' ? 'Image' : 'Chat';
    final provider = state.selectedProvider?.isNotEmpty == true
        ? state.selectedProvider!
        : 'Provider';
    final model =
        models
            .where((model) => model.id == state.selectedModel)
            .map((model) => model.label)
            .firstOrNull ??
        'Model';
    final prompt = state.selectedSystemPrompt?.isNotEmpty == true
        ? state.selectedSystemPrompt!
        : 'System prompt';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          IconButton.filledTonal(
            tooltip: 'New chat',
            visualDensity: VisualDensity.compact,
            onPressed: state.startNewConversation,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openSettingsSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.72,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      state.chatMode == 'image_generation'
                          ? Icons.image_outlined
                          : Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            modeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge,
                          ),
                          Text(
                            '$prompt · $provider · $model',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.62,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.62,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Discover models',
            visualDensity: VisualDensity.compact,
            onPressed: () => state.refreshModels(discover: true),
            icon: const Icon(Icons.manage_search_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettingsSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Chat settings',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'chat',
                          icon: Icon(Icons.chat_bubble_outline_rounded),
                          label: Text('Chat'),
                        ),
                        ButtonSegment(
                          value: 'image_generation',
                          icon: Icon(Icons.image_outlined),
                          label: Text('Image'),
                        ),
                      ],
                      selected: {state.chatMode},
                      onSelectionChanged: (value) {
                        state.selectChatMode(value.first);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    SearchSelectField<String>(
                      label: 'System prompt',
                      width: double.infinity,
                      value:
                          prompts.any(
                            (prompt) =>
                                prompt.name == state.selectedSystemPrompt,
                          )
                          ? state.selectedSystemPrompt
                          : null,
                      enabled: prompts.isNotEmpty,
                      emptyText: 'No prompts',
                      options: [
                        for (final prompt in prompts)
                          SearchSelectOption(
                            value: prompt.name,
                            label: prompt.name,
                          ),
                      ],
                      onChanged: (value) {
                        state.selectSystemPrompt(value);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    SearchSelectField<String>(
                      label: 'Provider',
                      width: double.infinity,
                      value: state.selectedProvider,
                      enabled: providers.isNotEmpty,
                      emptyText: 'No providers',
                      options: [
                        for (final provider in providers)
                          SearchSelectOption(
                            value: provider.name,
                            label: provider.name,
                            subtitle:
                                '${provider.count} models'
                                '${provider.source == null ? '' : ' · ${provider.source}'}',
                          ),
                      ],
                      onChanged: (value) {
                        state.selectProvider(value);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    SearchSelectField<String>(
                      label: 'Model',
                      width: double.infinity,
                      value:
                          models.any((model) => model.id == state.selectedModel)
                          ? state.selectedModel
                          : null,
                      enabled: models.isNotEmpty,
                      emptyText: 'No models',
                      options: [
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
                        state.selectModel(value);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

String _fmtFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _ConversationLoadingState extends StatelessWidget {
  const _ConversationLoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            'Loading conversation...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.state, required this.onPrompt});

  final PromptdAppState state;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = state.uiConfig.promptSuggestions;
    final isImageMode = state.chatMode == 'image_generation';

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.9),
          radius: 0.9,
          colors: [
            theme.colorScheme.primary.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.12 : 0.07,
            ),
            Colors.transparent,
          ],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 72),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 80, glow: true),
              const SizedBox(height: 18),
              Text(
                state.uiConfig.welcomeTitle,
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Promptd · AI Assistant',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Text(
                  isImageMode
                      ? 'Describe the image you want to create, or attach an image and describe how it should be transformed.'
                      : 'Start with a prompt below or type your own request. Ask for debugging, code changes, summaries, or planning help.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                    height: 1.45,
                  ),
                ),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 22),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final suggestion in suggestions)
                      ActionChip(
                        onPressed: () => onPrompt(suggestion),
                        label: Text(suggestion),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
