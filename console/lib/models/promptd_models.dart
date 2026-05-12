import 'dart:math';

String _randomId() {
  const chars = 'abcdef0123456789';
  final rand = Random();
  final sb = StringBuffer();
  for (var i = 0; i < 32; i++) {
    sb.write(chars[rand.nextInt(chars.length)]);
  }
  return sb.toString();
}

class AuthMe {
  const AuthMe({
    required this.userId,
    required this.tenantId,
    required this.roles,
    required this.permissions,
    required this.superAdmin,
  });

  final String userId;
  final String tenantId;
  final List<String> roles;
  final Permissions permissions;
  final bool superAdmin;

  factory AuthMe.fromJson(Map<String, dynamic> json) {
    return AuthMe(
      userId: json['user_id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      roles: (json['roles'] as List<dynamic>? ?? []).cast<String>(),
      permissions: Permissions.fromJson(
        json['permissions'] as Map<String, dynamic>? ?? {},
      ),
      superAdmin: json['super_admin'] as bool? ?? false,
    );
  }
}

class Permissions {
  const Permissions({
    this.chat = false,
    this.upload = false,
    this.conversationsRead = false,
    this.conversationsWrite = false,
    this.compactConversationWrite = false,
    this.schedulesRead = false,
    this.schedulesWrite = false,
    this.tracesRead = false,
    this.admin = false,
  });

  final bool chat;
  final bool upload;
  final bool conversationsRead;
  final bool conversationsWrite;
  final bool compactConversationWrite;
  final bool schedulesRead;
  final bool schedulesWrite;
  final bool tracesRead;
  final bool admin;

  factory Permissions.fromJson(Map<String, dynamic> json) {
    return Permissions(
      chat: json['chat'] as bool? ?? false,
      upload: json['upload'] as bool? ?? false,
      conversationsRead: json['conversations_read'] as bool? ?? false,
      conversationsWrite: json['conversations_write'] as bool? ?? false,
      compactConversationWrite:
          json['compact_conversation_write'] as bool? ?? false,
      schedulesRead: json['schedules_read'] as bool? ?? false,
      schedulesWrite: json['schedules_write'] as bool? ?? false,
      tracesRead: json['traces_read'] as bool? ?? false,
      admin: json['admin'] as bool? ?? false,
    );
  }
}

class UIConfig {
  const UIConfig({
    this.welcomeTitle = 'How can I help?',
    this.aiDisclaimer = '',
    this.promptSuggestions = const [],
    this.systemPrompts = const [],
    this.compactConversation,
  });

  final String welcomeTitle;
  final String aiDisclaimer;
  final List<String> promptSuggestions;
  final List<SystemPrompt> systemPrompts;
  final CompactConversationConfig? compactConversation;

  factory UIConfig.fromJson(Map<String, dynamic> json) {
    return UIConfig(
      welcomeTitle: json['welcomeTitle'] as String? ?? 'How can I help?',
      aiDisclaimer: json['aiDisclaimer'] as String? ?? '',
      promptSuggestions: (json['promptSuggestions'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      systemPrompts:
          (json['systemPrompts'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(SystemPrompt.fromJson)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name)),
      compactConversation: json['compactConversation'] is Map<String, dynamic>
          ? CompactConversationConfig.fromJson(
              json['compactConversation'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class CompactConversationConfig {
  const CompactConversationConfig({
    this.enabled = false,
    this.defaultPrompt = '',
    this.afterMessages = 0,
    this.afterTokens = 0,
  });

  final bool enabled;
  final String defaultPrompt;
  final int afterMessages;
  final int afterTokens;

  factory CompactConversationConfig.fromJson(Map<String, dynamic> json) {
    return CompactConversationConfig(
      enabled: json['enabled'] as bool? ?? false,
      defaultPrompt: json['defaultPrompt'] as String? ?? '',
      afterMessages: json['afterMessages'] as int? ?? 0,
      afterTokens: json['afterTokens'] as int? ?? 0,
    );
  }
}

class SystemPrompt {
  const SystemPrompt({required this.name});

  final String name;

  factory SystemPrompt.fromJson(Map<String, dynamic> json) {
    return SystemPrompt(name: json['name'] as String? ?? '');
  }
}

class ProviderInfo {
  const ProviderInfo({
    required this.name,
    required this.count,
    this.source,
    this.updatedAt,
    this.refreshInterval,
    this.imageGenerationEnabled = false,
  });

  final String name;
  final int count;
  final String? source;
  final String? updatedAt;
  final String? refreshInterval;
  final bool imageGenerationEnabled;

  factory ProviderInfo.fromJson(Map<String, dynamic> json) {
    return ProviderInfo(
      name: json['name'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      source: json['source'] as String?,
      updatedAt: json['updated_at'] as String?,
      refreshInterval: json['refresh_interval'] as String?,
      imageGenerationEnabled:
          json['image_generation_enabled'] as bool? ?? false,
    );
  }
}

class ModelInfo {
  const ModelInfo({
    required this.id,
    this.name,
    this.provider,
    this.source,
    this.isManual = false,
    this.params,
  });

  final String id;
  final String? name;
  final String? provider;
  final String? source;
  final bool isManual;
  final LlmParams? params;

  String get label => name?.isNotEmpty == true ? name! : id;

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String?,
      provider: json['provider'] as String?,
      source: json['source'] as String?,
      isManual: json['is_manual'] as bool? ?? false,
      params: json['params'] is Map<String, dynamic>
          ? LlmParams.fromJson(json['params'] as Map<String, dynamic>)
          : null,
    );
  }
}

class ModelData {
  const ModelData({
    this.models = const [],
    this.providers = const [],
    this.selectionMethod = 'round_robin',
    this.source,
    this.count = 0,
    this.updatedAt,
    this.refreshInterval,
    this.globalParams,
  });

  final List<ModelInfo> models;
  final List<ProviderInfo> providers;
  final String selectionMethod;
  final String? source;
  final int count;
  final String? updatedAt;
  final String? refreshInterval;
  final LlmParams? globalParams;

  factory ModelData.fromJson(Map<String, dynamic> json) {
    return ModelData(
      models: (json['models'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ModelInfo.fromJson)
          .toList(),
      providers: (json['providers'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ProviderInfo.fromJson)
          .toList(),
      selectionMethod: json['selection_method'] as String? ?? 'round_robin',
      source: json['source'] as String?,
      count: json['count'] as int? ?? 0,
      updatedAt: json['updated_at'] as String?,
      refreshInterval: json['refresh_interval'] as String?,
      globalParams: json['global_params'] is Map<String, dynamic>
          ? LlmParams.fromJson(json['global_params'] as Map<String, dynamic>)
          : null,
    );
  }
}

class LlmParams {
  const LlmParams({this.temperature, this.maxTokens, this.topP, this.topK});

  final double? temperature;
  final int? maxTokens;
  final double? topP;
  final int? topK;

  bool get isEmpty =>
      temperature == null && maxTokens == null && topP == null && topK == null;

  Map<String, dynamic> toJson() {
    return {
      if (temperature != null) 'temperature': temperature,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (topP != null) 'top_p': topP,
      if (topK != null) 'top_k': topK,
    };
  }

  factory LlmParams.fromJson(Map<String, dynamic> json) {
    return LlmParams(
      temperature: _asDouble(json['temperature']),
      maxTokens: json['max_tokens'] as int?,
      topP: _asDouble(json['top_p']),
      topK: json['top_k'] as int?,
    );
  }
}

class ConversationMeta {
  const ConversationMeta({
    required this.id,
    required this.title,
    this.mode,
    this.model,
    this.provider,
    this.systemPrompt,
    this.params,
    this.pinned = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String? mode;
  final String? model;
  final String? provider;
  final String? systemPrompt;
  final LlmParams? params;
  final bool pinned;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ConversationMeta.fromJson(Map<String, dynamic> json) {
    return ConversationMeta(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      mode: json['mode'] as String?,
      model: json['model'] as String?,
      provider: json['provider'] as String?,
      systemPrompt: json['system_prompt'] as String?,
      params: json['params'] is Map<String, dynamic>
          ? LlmParams.fromJson(json['params'] as Map<String, dynamic>)
          : null,
      pinned: json['pinned'] as bool? ?? false,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }
}

class ConversationDetail extends ConversationMeta {
  const ConversationDetail({
    required super.id,
    required super.title,
    super.mode,
    super.model,
    super.provider,
    super.systemPrompt,
    super.params,
    super.pinned,
    super.createdAt,
    super.updatedAt,
    this.messages = const [],
  });

  final List<StorageMessage> messages;

  factory ConversationDetail.fromJson(Map<String, dynamic> json) {
    final meta = ConversationMeta.fromJson(json);
    return ConversationDetail(
      id: meta.id,
      title: meta.title,
      mode: meta.mode,
      model: meta.model,
      provider: meta.provider,
      systemPrompt: meta.systemPrompt,
      params: meta.params,
      pinned: meta.pinned,
      createdAt: meta.createdAt,
      updatedAt: meta.updatedAt,
      messages: (json['messages'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(StorageMessage.fromJson)
          .toList(),
    );
  }
}

class StorageMessage {
  const StorageMessage({
    required this.id,
    required this.role,
    required this.content,
    this.mode,
    this.sentAt,
    this.compactSummary = false,
    this.model,
    this.provider,
    this.timeTakenMs,
    this.llmCalls,
    this.toolCalls,
    this.files = const [],
    this.trace = const [],
  });

  final String id;
  final String role;
  final String content;
  final String? mode;
  final DateTime? sentAt;
  final bool compactSummary;
  final String? model;
  final String? provider;
  final int? timeTakenMs;
  final int? llmCalls;
  final int? toolCalls;
  final List<UploadedFile> files;
  final List<Map<String, dynamic>> trace;

  factory StorageMessage.fromJson(Map<String, dynamic> json) {
    return StorageMessage(
      id: json['id'] as String? ?? '',
      role: json['role'] as String? ?? '',
      content: json['content'] as String? ?? '',
      mode: json['mode'] as String?,
      sentAt: _parseDate(json['sent_at']),
      compactSummary: json['compact_summary'] as bool? ?? false,
      model: json['model'] as String?,
      provider: json['provider'] as String?,
      timeTakenMs: json['time_taken_ms'] as int?,
      llmCalls: json['llm_calls'] as int?,
      toolCalls: json['tool_calls'] as int?,
      files: _uploadedFiles(json['files']),
      trace: _mapList(json['trace']),
    );
  }
}

class UploadedFile {
  const UploadedFile({
    required this.id,
    required this.filename,
    required this.size,
    required this.url,
    this.contentType,
  });

  final String id;
  final String filename;
  final int size;
  final String url;
  final String? contentType;

  bool get isImage {
    final type = contentType?.toLowerCase() ?? '';
    if (type.startsWith('image/')) return true;
    final lower = filename.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.svg');
  }

  bool get isSvg {
    final type = contentType?.toLowerCase() ?? '';
    return type == 'image/svg+xml' || filename.toLowerCase().endsWith('.svg');
  }

  factory UploadedFile.fromJson(Map<String, dynamic> json) {
    return UploadedFile(
      id: json['id'] as String? ?? '',
      filename: json['filename'] as String? ?? 'file',
      size: json['size'] as int? ?? 0,
      url: json['url'] as String? ?? '',
      contentType: json['content_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filename': filename,
      'size': size,
      'url': url,
      if (contentType != null) 'content_type': contentType,
    };
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    this.msgId,
    required this.role,
    required this.content,
    required this.sentAt,
    this.model,
    this.provider,
    this.timeTakenMs,
    this.llmCalls,
    this.toolCalls,
    this.files = const [],
    this.trace = const [],
    this.compactSummary = false,
    this.pending = false,
  });

  /// Stable local UI identifier (never changes after creation).
  final String id;

  /// Backend message identifier, set after the message is persisted.
  final String? msgId;

  final String role;
  final String content;
  final DateTime sentAt;
  final String? model;
  final String? provider;
  final int? timeTakenMs;
  final int? llmCalls;
  final int? toolCalls;
  final List<UploadedFile> files;
  final List<Map<String, dynamic>> trace;
  final bool compactSummary;
  final bool pending;

  factory ChatMessage.fromStorage(StorageMessage message) {
    return ChatMessage(
      id: _randomId(),
      msgId: message.id,
      role: message.role,
      content: message.content,
      sentAt: message.sentAt ?? DateTime.now(),
      model: message.model,
      provider: message.provider,
      timeTakenMs: message.timeTakenMs,
      llmCalls: message.llmCalls,
      toolCalls: message.toolCalls,
      files: message.files,
      trace: message.trace,
      compactSummary: message.compactSummary,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? msgId,
    String? role,
    String? content,
    DateTime? sentAt,
    String? model,
    String? provider,
    int? timeTakenMs,
    int? llmCalls,
    int? toolCalls,
    List<UploadedFile>? files,
    List<Map<String, dynamic>>? trace,
    bool? compactSummary,
    bool? pending,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      msgId: msgId ?? this.msgId,
      role: role ?? this.role,
      content: content ?? this.content,
      sentAt: sentAt ?? this.sentAt,
      model: model ?? this.model,
      provider: provider ?? this.provider,
      timeTakenMs: timeTakenMs ?? this.timeTakenMs,
      llmCalls: llmCalls ?? this.llmCalls,
      toolCalls: toolCalls ?? this.toolCalls,
      files: files ?? this.files,
      trace: trace ?? this.trace,
      compactSummary: compactSummary ?? this.compactSummary,
      pending: pending ?? this.pending,
    );
  }
}

class ChatResponse {
  const ChatResponse({
    required this.reply,
    required this.model,
    this.provider,
    this.timeTakenMs = 0,
    this.llmCalls = 0,
    this.toolCalls = 0,
    this.userMessageId,
    this.assistantMessageId,
    this.files = const [],
    this.trace = const [],
    this.compactSummary,
  });

  final String reply;
  final String model;
  final String? provider;
  final int timeTakenMs;
  final int llmCalls;
  final int toolCalls;
  final String? userMessageId;
  final String? assistantMessageId;
  final List<UploadedFile> files;
  final List<Map<String, dynamic>> trace;
  final StorageMessage? compactSummary;

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      reply: json['reply'] as String? ?? '',
      model: json['model'] as String? ?? '',
      provider: json['provider'] as String?,
      timeTakenMs: json['time_taken_ms'] as int? ?? 0,
      llmCalls: json['llm_calls'] as int? ?? 0,
      toolCalls: json['tool_calls'] as int? ?? 0,
      userMessageId: json['user_msg_id'] as String?,
      assistantMessageId: json['assistant_msg_id'] as String?,
      files: _uploadedFiles(json['files']),
      trace: _mapList(json['trace']),
      compactSummary: json['compact_summary'] is Map<String, dynamic>
          ? StorageMessage.fromJson(
              json['compact_summary'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class ToolInfo {
  const ToolInfo({
    required this.name,
    required this.description,
    this.parameters,
  });

  final String name;
  final String description;
  final Map<String, dynamic>? parameters;

  List<String> get parameterNames {
    final properties = parameters?['properties'];
    if (properties is Map<String, dynamic>) return properties.keys.toList();
    return const [];
  }

  List<String> get requiredNames {
    final required = parameters?['required'];
    if (required is List<dynamic>) return required.whereType<String>().toList();
    return const [];
  }

  factory ToolInfo.fromJson(Map<String, dynamic> json) {
    return ToolInfo(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      parameters: json['parameters'] as Map<String, dynamic>?,
    );
  }
}

class Schedule {
  const Schedule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.type,
    required this.prompt,
    required this.retainHistory,
    this.cronExpr,
    this.runAt,
    this.modelId,
    this.provider,
    this.systemPrompt,
    this.allowedTools,
    this.params,
    this.traceEnabled,
    this.createdAt,
    this.updatedAt,
    this.lastRunAt,
    this.nextRunAt,
  });

  final String id;
  final String name;
  final bool enabled;
  final String type;
  final String? cronExpr;
  final DateTime? runAt;
  final String prompt;
  final String? modelId;
  final String? provider;
  final String? systemPrompt;
  final List<String>? allowedTools;
  final LlmParams? params;
  final bool? traceEnabled;
  final int retainHistory;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      type: json['type'] as String? ?? 'cron',
      cronExpr: json['cronExpr'] as String?,
      runAt: _parseDate(json['runAt']),
      prompt: json['prompt'] as String? ?? '',
      modelId: json['modelId'] as String?,
      provider: json['provider'] as String?,
      systemPrompt: json['systemPrompt'] as String?,
      allowedTools: (json['allowedTools'] as List<dynamic>?)?.cast<String>(),
      params: json['params'] is Map<String, dynamic>
          ? LlmParams.fromJson(json['params'] as Map<String, dynamic>)
          : null,
      traceEnabled: json['traceEnabled'] as bool?,
      retainHistory: json['retainHistory'] as int? ?? 0,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      lastRunAt: _parseDate(json['lastRunAt']),
      nextRunAt: _parseDate(json['nextRunAt']),
    );
  }
}

class ScheduleExecution {
  const ScheduleExecution({
    required this.id,
    required this.scheduleId,
    required this.triggeredAt,
    required this.status,
    this.completedAt,
    this.error,
    this.response,
    this.trace = const [],
    this.modelUsed,
    this.providerUsed,
    this.llmCalls,
    this.toolCalls,
    this.durationMs,
  });

  final String id;
  final String scheduleId;
  final DateTime? triggeredAt;
  final DateTime? completedAt;
  final String status;
  final String? error;
  final String? response;
  final List<Map<String, dynamic>> trace;
  final String? modelUsed;
  final String? providerUsed;
  final int? llmCalls;
  final int? toolCalls;
  final int? durationMs;

  factory ScheduleExecution.fromJson(Map<String, dynamic> json) {
    return ScheduleExecution(
      id: json['id'] as String? ?? '',
      scheduleId: json['scheduleId'] as String? ?? '',
      triggeredAt: _parseDate(json['triggeredAt']),
      completedAt: _parseDate(json['completedAt']),
      status: json['status'] as String? ?? 'running',
      error: json['error'] as String?,
      response: json['response'] as String?,
      trace: _mapList(json['trace']),
      modelUsed: json['modelUsed'] as String?,
      providerUsed: json['providerUsed'] as String?,
      llmCalls: json['llmCalls'] as int?,
      toolCalls: json['toolCalls'] as int?,
      durationMs: json['durationMs'] as int?,
    );
  }
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return null;
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List<dynamic>) return const [];
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}

List<UploadedFile> _uploadedFiles(Object? value) {
  if (value is! List<dynamic>) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map(UploadedFile.fromJson)
      .toList(growable: false);
}
