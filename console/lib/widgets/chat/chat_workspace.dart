import 'package:flutter/material.dart';

import '../../state/promptd_app_state.dart';
import '../brand_mark.dart';
import '../search_select_field.dart';
import 'message_bubble.dart';

class ChatWorkspace extends StatefulWidget {
  const ChatWorkspace({super.key, required this.state});

  final PromptdAppState state;

  @override
  State<ChatWorkspace> createState() => _ChatWorkspaceState();
}

class _ChatWorkspaceState extends State<ChatWorkspace> {
  final _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);

    if (!state.me!.permissions.chat) {
      return const Card(
        child: Center(child: Text('Chat access is not enabled for this user.')),
      );
    }

    return Card(
      child: Column(
        children: [
          _ChatToolbar(state: state),
          const Divider(height: 1),
          Expanded(
            child: state.messages.isEmpty
                ? _EmptyChat(state: state, onPrompt: _send)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                    itemCount: state.messages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return MessageBubble(
                        message: state.messages[index],
                        onDelete: state.deleteMessage,
                        onEdit: state.editMessage,
                      );
                    },
                  ),
          ),
          if (state.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.errorContainer,
              child: Text(
                state.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Message Promptd',
                      prefixIcon: Icon(Icons.auto_awesome_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: state.sending
                      ? null
                      : () => _send(_inputController.text),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(52, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: state.sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
                if (state.chatMode == 'chat' &&
                    (state.uiConfig.compactConversation?.enabled ?? false) &&
                    (state.me?.permissions.compactConversationWrite ?? false) &&
                    (state.selectedConversationId != null ||
                        state.messages.isNotEmpty)) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Compact conversation',
                    onPressed: state.compacting
                        ? null
                        : () => _openCompactDialog(context),
                    icon: state.compacting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.compress_rounded),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send(String text) async {
    _inputController.clear();
    await widget.state.sendMessage(text);
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

class _ChatToolbar extends StatelessWidget {
  const _ChatToolbar({required this.state});

  final PromptdAppState state;

  @override
  Widget build(BuildContext context) {
    final providers = state.modelData.providers;
    final models = state.availableModels;
    final prompts = state.uiConfig.systemPrompts;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
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
          IconButton.filledTonal(
            tooltip: 'New chat',
            onPressed: state.startNewConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
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

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.state, required this.onPrompt});

  final PromptdAppState state;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = state.uiConfig.promptSuggestions;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 76),
            const SizedBox(height: 18),
            Text(
              state.uiConfig.welcomeTitle,
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            if (state.uiConfig.aiDisclaimer.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Text(
                  state.uiConfig.aiDisclaimer,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                    height: 1.45,
                  ),
                ),
              ),
            ],
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
    );
  }
}
