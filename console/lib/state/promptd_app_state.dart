import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/promptd_models.dart';
import '../services/promptd_api_client.dart';
import '../services/session_store.dart';
import '../widgets/app_shell.dart';

class PromptdAppState extends ChangeNotifier {
  PromptdAppState({
    required PromptdApiClient api,
    required SessionStore sessionStore,
  }) : _api = api,
       _sessionStore = sessionStore;

  final PromptdApiClient _api;
  final SessionStore _sessionStore;
  final Uuid _uuid = const Uuid();
  bool _stopRequested = false;

  bool initializing = true;
  bool signingIn = false;
  bool loadingData = false;
  bool sending = false;
  bool compacting = false;
  String? error;
  String serverUrl = '';
  bool allowInsecureTls = false;
  AuthMe? me;
  UIConfig uiConfig = const UIConfig();
  ModelData modelData = const ModelData();
  List<ConversationMeta> conversations = const [];
  List<ChatMessage> messages = const [];
  List<ToolInfo> tools = const [];
  List<Schedule> schedules = const [];
  ConsoleSection section = ConsoleSection.chat;
  String? selectedConversationId;
  String? selectedProvider;
  String? selectedModel;
  String? selectedSystemPrompt;
  String chatMode = 'chat';

  bool get isAuthenticated => me != null;
  PromptdApiClient get api => _api;

  List<ModelInfo> get availableModels {
    if (selectedProvider == null || selectedProvider!.isEmpty) {
      return modelData.models;
    }
    return modelData.models
        .where((model) => model.provider == selectedProvider)
        .toList();
  }

  Future<void> initialize() async {
    serverUrl = await _sessionStore.loadServerUrl();
    allowInsecureTls = await _sessionStore.loadAllowInsecureTls();
    _api.allowInsecureTls = allowInsecureTls;
    final session = await _sessionStore.load();
    if (session == null) {
      initializing = false;
      notifyListeners();
      return;
    }
    _api.session = session;
    serverUrl = session.serverUrl;
    try {
      me = await _api.me();
      if (me == null) {
        await _sessionStore.clearToken();
      } else {
        await refreshAppData();
      }
    } catch (err) {
      error = err.toString();
      await _sessionStore.clearToken();
      me = null;
    } finally {
      initializing = false;
      notifyListeners();
    }
  }

  Future<void> login({
    required String serverUrl,
    required String userId,
    required String password,
    required bool allowInsecureTls,
  }) async {
    signingIn = true;
    error = null;
    this.allowInsecureTls = allowInsecureTls;
    _api.allowInsecureTls = allowInsecureTls;
    notifyListeners();
    try {
      final result = await _api.login(
        serverUrl: serverUrl,
        userId: userId,
        password: password,
        allowInsecureTls: allowInsecureTls,
      );
      await _sessionStore.save(result.session);
      this.serverUrl = result.session.serverUrl;
      me = result.me;
      await refreshAppData();
    } catch (err) {
      error = err.toString();
      rethrow;
    } finally {
      signingIn = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _api.logout();
    await _sessionStore.clearToken();
    me = null;
    conversations = const [];
    messages = const [];
    tools = const [];
    schedules = const [];
    selectedConversationId = null;
    notifyListeners();
  }

  void selectSection(ConsoleSection next) {
    section = next;
    notifyListeners();
  }

  Future<void> refreshAppData() async {
    loadingData = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _api.uiConfig(),
        _api.models(),
        _api.conversations(),
        _api.tools(),
        _api.schedules(),
      ]);
      uiConfig = results[0] as UIConfig;
      modelData = results[1] as ModelData;
      conversations = results[2] as List<ConversationMeta>;
      tools = results[3] as List<ToolInfo>;
      schedules = results[4] as List<Schedule>;
      _selectDefaults();
    } catch (err) {
      error = err.toString();
    } finally {
      loadingData = false;
      notifyListeners();
    }
  }

  Future<void> refreshModels({bool discover = false}) async {
    modelData = await _api.models(
      provider: selectedProvider,
      discover: discover,
    );
    _selectDefaults();
    notifyListeners();
  }

  Future<void> loadConversation(String id) async {
    loadingData = true;
    error = null;
    selectedConversationId = id;
    messages = const [];
    notifyListeners();
    try {
      final detail = await _api.conversation(id);
      messages = detail.messages
          .where(
            (message) =>
                message.role == 'user' ||
                message.role == 'assistant' ||
                message.role == 'error',
          )
          .map(ChatMessage.fromStorage)
          .toList();
      chatMode = detail.mode == 'image_generation'
          ? 'image_generation'
          : 'chat';
      selectedProvider = detail.provider?.isNotEmpty == true
          ? detail.provider
          : selectedProvider;
      selectedModel = detail.model?.isNotEmpty == true
          ? detail.model
          : selectedModel;
      selectedSystemPrompt = detail.systemPrompt?.isNotEmpty == true
          ? detail.systemPrompt
          : selectedSystemPrompt;
    } catch (err) {
      error = err.toString();
    } finally {
      loadingData = false;
      notifyListeners();
    }
  }

  void startNewConversation() {
    selectedConversationId = null;
    messages = const [];
    notifyListeners();
  }

  void selectProvider(String? provider) {
    selectedProvider = provider?.isEmpty == true ? null : provider;
    selectedModel = null;
    _selectDefaults();
    notifyListeners();
  }

  void selectModel(String? model) {
    selectedModel = model?.isEmpty == true ? null : model;
    notifyListeners();
  }

  void selectSystemPrompt(String? prompt) {
    selectedSystemPrompt = prompt;
    notifyListeners();
  }

  void selectChatMode(String mode) {
    chatMode = mode;
    notifyListeners();
  }

  Future<void> sendMessage(
    String content, {
    List<UploadedFile> files = const [],
  }) async {
    final trimmed = content.trim();
    if ((trimmed.isEmpty && files.isEmpty) || sending) return;
    final conversationId = selectedConversationId ?? _uuid.v4();
    selectedConversationId = conversationId;
    final now = DateTime.now();
    messages = [
      ...messages,
      ChatMessage(
        id: _uuid.v4(),
        role: 'user',
        content: trimmed,
        sentAt: now,
        files: files,
      ),
      ChatMessage(
        id: 'pending-${now.microsecondsSinceEpoch}',
        role: 'assistant',
        content: '',
        sentAt: now,
        pending: true,
      ),
    ];
    sending = true;
    _stopRequested = false;
    error = null;
    notifyListeners();
    try {
      final response = await _api.chat(
        sessionId: conversationId,
        message: trimmed,
        mode: chatMode,
        files: files,
        provider: selectedProvider,
        model: selectedModel,
        systemPrompt: selectedSystemPrompt,
      );
      final userMessageId = response.userMessageId;
      final assistantMessageId = response.assistantMessageId;
      final sentMessages = messages
          .where((message) => !message.pending)
          .toList();
      if (userMessageId != null && sentMessages.isNotEmpty) {
        final lastIndex = sentMessages.lastIndexWhere(
          (message) => message.role == 'user' && message.content == trimmed,
        );
        if (lastIndex >= 0) {
          sentMessages[lastIndex] = sentMessages[lastIndex].copyWith(
            msgId: userMessageId,
          );
        }
      }
      messages = [
        ...sentMessages,
        ChatMessage(
          id: _uuid.v4(),
          msgId: assistantMessageId,
          role: 'assistant',
          content: response.reply,
          sentAt: DateTime.now(),
          model: response.model,
          provider: response.provider,
          timeTakenMs: response.timeTakenMs,
          llmCalls: response.llmCalls,
          toolCalls: response.toolCalls,
          files: response.files,
          trace: response.trace,
        ),
      ];
      if (response.compactSummary != null) {
        _upsertCompactSummary(
          ChatMessage.fromStorage(response.compactSummary!),
        );
      }
      await _refreshConversationsOnly();
    } catch (err) {
      if (_stopRequested) {
        messages = [
          for (final message in messages)
            if (!message.pending) message,
        ];
        error = null;
        return;
      }
      messages = [
        for (final message in messages)
          if (!message.pending) message,
        ChatMessage(
          id: _uuid.v4(),
          role: 'error',
          content: err.toString(),
          sentAt: DateTime.now(),
        ),
      ];
      error = err.toString();
    } finally {
      sending = false;
      _stopRequested = false;
      notifyListeners();
    }
  }

  void stopProcessing() {
    if (!sending) return;
    _stopRequested = true;
    _api.cancelActiveRequests();
    messages = [
      for (final message in messages)
        if (!message.pending) message,
    ];
    sending = false;
    error = null;
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    await _api.deleteConversation(id);
    if (selectedConversationId == id) startNewConversation();
    await _refreshConversationsOnly();
  }

  Future<void> deleteMessage(ChatMessage message) async {
    final conversationId = selectedConversationId;
    messages = messages.where((item) => item.id != message.id).toList();
    notifyListeners();
    if (conversationId == null || message.pending) return;
    final backendMsgId = message.msgId ?? message.id;
    await _api.deleteMessage(
      conversationId: conversationId,
      messageId: backendMsgId,
    );
    await _refreshConversationsOnly();
  }

  Future<void> editMessage(ChatMessage message, String newContent) async {
    final conversationId = selectedConversationId;
    final trimmed = newContent.trim();
    if (conversationId == null || message.role != 'user' || trimmed.isEmpty) {
      return;
    }
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index < 0) return;
    final backendMsgId = message.msgId ?? message.id;
    unawaited(
      _api
          .deleteMessagesFrom(
            conversationId: conversationId,
            messageId: backendMsgId,
          )
          .catchError((Object _) {}),
    );
    messages = messages.take(index).toList();
    notifyListeners();
    // Do not await; match web behavior where send runs independently.
    unawaited(sendMessage(trimmed));
  }

  Future<void> compactConversation({String? prompt, String? model}) async {
    final conversationId = selectedConversationId;
    if (conversationId == null || compacting) return;
    compacting = true;
    error = null;
    notifyListeners();
    try {
      final summary = await _api.compactConversation(
        conversationId: conversationId,
        prompt: prompt,
        model: model,
      );
      _upsertCompactSummary(ChatMessage.fromStorage(summary));
      await _refreshConversationsOnly();
    } catch (err) {
      error = err.toString();
    } finally {
      compacting = false;
      notifyListeners();
    }
  }

  Future<void> togglePinConversation(String id) async {
    await _api.togglePinConversation(id);
    await _refreshConversationsOnly();
  }

  Future<void> triggerSchedule(String id) async {
    await _api.triggerSchedule(id);
    schedules = await _api.schedules();
    notifyListeners();
  }

  Future<void> refreshSchedules() async {
    schedules = await _api.schedules();
    notifyListeners();
  }

  Future<Schedule> saveSchedule({
    String? id,
    required Map<String, dynamic> schedule,
  }) async {
    final saved = id == null || id.isEmpty
        ? await _api.createSchedule(schedule)
        : await _api.updateSchedule(id: id, schedule: schedule);
    schedules = await _api.schedules();
    notifyListeners();
    return saved;
  }

  Future<void> deleteSchedule(String id) async {
    await _api.deleteSchedule(id);
    schedules = await _api.schedules();
    notifyListeners();
  }

  Future<List<ScheduleExecution>> scheduleExecutions(String id) {
    return _api.scheduleExecutions(id);
  }

  Future<void> deleteScheduleExecution({
    required String scheduleId,
    required String executionId,
  }) {
    return _api.deleteScheduleExecution(
      scheduleId: scheduleId,
      executionId: executionId,
    );
  }

  Future<void> _refreshConversationsOnly() async {
    conversations = await _api.conversations();
    notifyListeners();
  }

  void _upsertCompactSummary(ChatMessage summary) {
    messages = [
      ...messages.where((message) => !message.compactSummary),
      summary.copyWith(compactSummary: true),
    ];
  }

  void _selectDefaults() {
    if ((selectedSystemPrompt == null || selectedSystemPrompt!.isEmpty) &&
        uiConfig.systemPrompts.isNotEmpty) {
      selectedSystemPrompt = uiConfig.systemPrompts.first.name;
    }
  }
}
