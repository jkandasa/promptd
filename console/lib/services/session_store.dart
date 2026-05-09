import 'package:shared_preferences/shared_preferences.dart';

class StoredSession {
  const StoredSession({
    required this.serverUrl,
    required this.cookieHeader,
    required this.jwtToken,
    required this.allowInsecureTls,
  });

  final String serverUrl;
  final String cookieHeader;
  final String jwtToken;
  final bool allowInsecureTls;

  bool get isComplete => serverUrl.isNotEmpty && jwtToken.isNotEmpty;
}

class SessionStore {
  static const _serverUrlKey = 'promptd.console.serverUrl';
  static const _cookieHeaderKey = 'promptd.console.cookieHeader';
  static const _jwtTokenKey = 'promptd.console.jwtToken';
  static const _allowInsecureTlsKey = 'promptd.console.allowInsecureTls';

  Future<StoredSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey) ?? '';
    final cookieHeader = prefs.getString(_cookieHeaderKey) ?? '';
    final jwtToken = prefs.getString(_jwtTokenKey) ?? '';
    final allowInsecureTls = prefs.getBool(_allowInsecureTlsKey) ?? false;
    final session = StoredSession(
      serverUrl: serverUrl,
      cookieHeader: cookieHeader,
      jwtToken: jwtToken,
      allowInsecureTls: allowInsecureTls,
    );
    return session.isComplete ? session : null;
  }

  Future<String> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverUrlKey) ?? '';
  }

  Future<bool> loadAllowInsecureTls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_allowInsecureTlsKey) ?? false;
  }

  Future<void> save(StoredSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, session.serverUrl);
    await prefs.setString(_cookieHeaderKey, session.cookieHeader);
    await prefs.setString(_jwtTokenKey, session.jwtToken);
    await prefs.setBool(_allowInsecureTlsKey, session.allowInsecureTls);
  }

  Future<void> saveServerUrl(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, serverUrl);
  }

  Future<void> saveAllowInsecureTls(bool allowInsecureTls) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowInsecureTlsKey, allowInsecureTls);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cookieHeaderKey);
    await prefs.remove(_jwtTokenKey);
  }
}
