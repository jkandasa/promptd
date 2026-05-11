import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/promptd_models.dart';
import 'http_client_factory.dart';
import 'session_store.dart';

class PromptdApiException implements Exception {
  const PromptdApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class LoginResult {
  const LoginResult({required this.me, required this.session});

  final AuthMe me;
  final StoredSession session;
}

class PromptdApiClient {
  PromptdApiClient({http.Client? httpClient, bool allowInsecureTls = false})
    : _httpClient =
          httpClient ??
          createPromptdHttpClient(allowInsecureTls: allowInsecureTls),
      _ownsClient = httpClient == null,
      _allowInsecureTls = allowInsecureTls;

  http.Client _httpClient;
  final bool _ownsClient;
  bool _allowInsecureTls;
  String _serverUrl = '';
  String _cookieHeader = '';
  String _jwtToken = '';

  String get serverUrl => _serverUrl;
  Map<String, String> get authHeaders => {
    if (_jwtToken.isNotEmpty) 'Authorization': 'Bearer $_jwtToken',
    if (_cookieHeader.isNotEmpty) 'Cookie': _cookieHeader,
  };

  set session(StoredSession? session) {
    allowInsecureTls = session?.allowInsecureTls ?? false;
    _serverUrl = session?.serverUrl ?? '';
    _cookieHeader = session?.cookieHeader ?? '';
    _jwtToken = session?.jwtToken ?? '';
  }

  bool get allowInsecureTls => _allowInsecureTls;

  set allowInsecureTls(bool value) {
    if (_allowInsecureTls == value) return;
    _allowInsecureTls = value;
    if (_ownsClient) {
      _httpClient.close();
      _httpClient = createPromptdHttpClient(allowInsecureTls: value);
    }
  }

  void cancelActiveRequests() {
    if (!_ownsClient) return;
    _httpClient.close();
    _httpClient = createPromptdHttpClient(allowInsecureTls: _allowInsecureTls);
  }

  Future<LoginResult> login({
    required String serverUrl,
    required String userId,
    required String password,
    required bool allowInsecureTls,
  }) async {
    this.allowInsecureTls = allowInsecureTls;
    final normalizedUrl = _normalizeServerUrl(serverUrl);
    final response = await _httpClient.post(
      _uri(normalizedUrl, '/api/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'password': password}),
    );
    final body = _decodeBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PromptdApiException(
        _errorMessage(body, 'Login failed'),
        statusCode: response.statusCode,
      );
    }
    final jwtToken = body['token'] as String? ?? '';
    if (jwtToken.isEmpty) {
      throw const PromptdApiException(
        'Login response did not include a session token',
      );
    }
    final cookieHeader = _cookieFromSetCookie(response.headers['set-cookie']);
    final session = StoredSession(
      serverUrl: normalizedUrl,
      cookieHeader: cookieHeader,
      jwtToken: jwtToken,
      allowInsecureTls: allowInsecureTls,
    );
    this.session = session;
    return LoginResult(me: AuthMe.fromJson(body), session: session);
  }

  Future<void> logout() async {
    if (_serverUrl.isEmpty) return;
    await _request('POST', '/api/auth/logout', allowUnauthorized: true);
    session = null;
  }

  Future<AuthMe?> me() async {
    final response = await _requestRaw('GET', '/api/auth/me');
    if (response.statusCode == 401) return null;
    final body = _decodeBody(response);
    _throwIfFailed(response, body, 'Failed to load current user');
    return AuthMe.fromJson(body);
  }

  Future<UIConfig> uiConfig() async {
    final body = await _request('GET', '/api/ui-config');
    return UIConfig.fromJson(body);
  }

  Future<ModelData> models({String? provider, bool discover = false}) async {
    final query = <String, String>{
      if (provider != null && provider.isNotEmpty) 'provider': provider,
      if (discover) 'discover': 'true',
    };
    final body = await _request('GET', '/api/models', query: query);
    return ModelData.fromJson(body);
  }

  Future<List<ConversationMeta>> conversations() async {
    final body = await _requestList('GET', '/api/conversations');
    return body
        .whereType<Map<String, dynamic>>()
        .map(ConversationMeta.fromJson)
        .toList();
  }

  Future<ConversationDetail> conversation(String id) async {
    final body = await _request('GET', '/api/conversations/$id');
    return ConversationDetail.fromJson(body);
  }

  Future<void> deleteConversation(String id) async {
    await _request('DELETE', '/api/conversations/$id');
  }

  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    await _request(
      'DELETE',
      '/api/conversations/$conversationId/messages/$messageId',
    );
  }

  Future<void> deleteMessagesFrom({
    required String conversationId,
    required String messageId,
  }) async {
    await _request(
      'DELETE',
      '/api/conversations/$conversationId/messages/$messageId/after',
    );
  }

  Future<bool> togglePinConversation(String id) async {
    final body = await _request('PATCH', '/api/conversations/$id/pin');
    return body['pinned'] as bool? ?? false;
  }

  Future<ChatResponse> chat({
    required String sessionId,
    required String message,
    required String mode,
    List<UploadedFile> files = const [],
    String? provider,
    String? model,
    String? systemPrompt,
    LlmParams? params,
  }) async {
    final body = await _request(
      'POST',
      '/api/chat',
      body: {
        'session_id': sessionId,
        'message': message,
        'mode': mode,
        if (files.isNotEmpty)
          'files': [for (final file in files) file.toJson()],
        if (provider != null && provider.isNotEmpty) 'provider': provider,
        if (model != null && model.isNotEmpty) 'model': model,
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          'system_prompt': systemPrompt,
        if (params != null && !params.isEmpty) 'params': params.toJson(),
      },
    );
    return ChatResponse.fromJson(body);
  }

  Future<UploadedFile> uploadFile({
    required String filename,
    required Uint8List bytes,
  }) async {
    if (_serverUrl.isEmpty) {
      throw const PromptdApiException('Server URL is not configured');
    }
    final request = http.MultipartRequest(
      'POST',
      _uri(_serverUrl, '/api/upload'),
    );
    request.headers.addAll(authHeaders);
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);
    final body = _decodeBody(response);
    _throwIfFailed(response, body, 'Upload failed');
    return UploadedFile.fromJson(body);
  }

  Future<void> deleteFile(String fileId) async {
    if (fileId.isEmpty) return;
    await _request('DELETE', '/api/files/$fileId');
  }

  Future<StorageMessage> compactConversation({
    required String conversationId,
    String? prompt,
    String? model,
  }) async {
    final body = await _request(
      'POST',
      '/api/conversations/$conversationId/compact',
      body: {
        if (prompt != null && prompt.trim().isNotEmpty) 'prompt': prompt,
        if (model != null && model.isNotEmpty) 'model': model,
      },
    );
    return StorageMessage.fromJson(body);
  }

  Future<List<ToolInfo>> tools() async {
    final body = await _request('GET', '/api/tools');
    final tools = body['tools'];
    if (tools is! List<dynamic>) return const [];
    return tools
        .whereType<Map<String, dynamic>>()
        .map(ToolInfo.fromJson)
        .toList();
  }

  Future<List<Schedule>> schedules() async {
    final body = await _request('GET', '/api/schedules');
    final schedules = body['schedules'];
    if (schedules is! List<dynamic>) return const [];
    return schedules
        .whereType<Map<String, dynamic>>()
        .map(Schedule.fromJson)
        .toList();
  }

  Future<void> triggerSchedule(String id) async {
    await _request('POST', '/api/schedules/$id/trigger');
  }

  Future<Uint8List> downloadFile(String url) async {
    final response = await _httpClient.get(
      Uri.parse(resolveUrl(url)),
      headers: authHeaders,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PromptdApiException(
        'Failed to load file',
        statusCode: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  String resolveUrl(String value) {
    if (value.isEmpty || _serverUrl.isEmpty) return value;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return value;
    final base = Uri.parse(_serverUrl);
    return base.replace(path: value).toString();
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool allowUnauthorized = false,
  }) async {
    final response = await _requestRaw(method, path, query: query, body: body);
    final decoded = _decodeBody(response);
    if (allowUnauthorized && response.statusCode == 401) return decoded;
    _throwIfFailed(response, decoded, 'Request failed');
    return decoded;
  }

  Future<List<dynamic>> _requestList(String method, String path) async {
    final response = await _requestRaw(method, path);
    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) {
      throw const PromptdApiException('Unexpected response format');
    }
    _throwIfFailed(response, const {}, 'Request failed');
    return decoded;
  }

  Future<http.Response> _requestRaw(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) {
    if (_serverUrl.isEmpty) {
      throw const PromptdApiException('Server URL is not configured');
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      ...authHeaders,
      if (body != null) 'Content-Type': 'application/json',
    };
    final uri = _uri(_serverUrl, path, query);
    final encodedBody = body == null ? null : jsonEncode(body);
    return switch (method) {
      'GET' => _httpClient.get(uri, headers: headers),
      'POST' => _httpClient.post(uri, headers: headers, body: encodedBody),
      'PATCH' => _httpClient.patch(uri, headers: headers, body: encodedBody),
      'DELETE' => _httpClient.delete(uri, headers: headers),
      _ => throw PromptdApiException('Unsupported method $method'),
    };
  }

  Uri _uri(String serverUrl, String path, [Map<String, String>? query]) {
    final base = Uri.parse(serverUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      path: '$basePath$path',
      queryParameters: query?.isEmpty == true ? null : query,
    );
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    if (response.body.isEmpty) return {};
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const PromptdApiException('Unexpected response format');
  }

  void _throwIfFailed(
    http.Response response,
    Map<String, dynamic> body,
    String fallback,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw PromptdApiException(
      _errorMessage(body, fallback),
      statusCode: response.statusCode,
    );
  }

  String _normalizeServerUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const PromptdApiException('Server URL is required');
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  String _cookieFromSetCookie(String? setCookie) {
    if (setCookie == null || setCookie.isEmpty) return '';
    return setCookie.split(';').first.trim();
  }

  String _errorMessage(Map<String, dynamic> body, String fallback) {
    return body['error'] as String? ?? fallback;
  }
}
