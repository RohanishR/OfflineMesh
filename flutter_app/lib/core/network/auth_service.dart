import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

/// Handles authentication against the OfflineMesh backend.
/// Stores the JWT token in SharedPreferences for session persistence.
class AuthService {
  static final _rejectedSessions = StreamController<String>.broadcast();
  static Stream<String> get rejectedSessions => _rejectedSessions.stream;

  static void checkResponse(int statusCode, String token) {
    if (statusCode == 401) {
      _rejectedSessions.add(token);
      throw const SessionExpiredException();
    }
  }

  // This only schedules reauthentication; signature verification stays on the server.
  static bool tokenExpired(String token, {DateTime? now}) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = claims['exp'];
      return exp is! num ||
          exp * 1000 <= (now ?? DateTime.now()).millisecondsSinceEpoch;
    } catch (_) {
      return true;
    }
  }

  String baseUrl;

  static String errorMessage(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return 'Cannot reach the server. Open Server settings and test the PC address for your current Wi-Fi or hotspot. Check that Docker is running on port 8081.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  String? _jwtToken;

  AuthService({String? baseUrl})
      : baseUrl = baseUrl ?? AppConfig.backendBaseUrl;

  void updateBaseUrl(String newUrl) {
    baseUrl = newUrl;
  }

  /// The current JWT token, or null if not authenticated.
  String? get jwtToken => _jwtToken;

  bool get isAuthenticated => _jwtToken != null;

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_jwtToken != null) 'Authorization': 'Bearer $_jwtToken',
      };

  /// Initialize the service by attempting to load an existing token.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _jwtToken = prefs.getString('jwt_token');
    if (_jwtToken != null && tokenExpired(_jwtToken!)) await logout();
  }

  /// Save token to secure storage/preferences
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
    _jwtToken = token;
  }

  /// POST /api/auth/register
  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    String? email,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'password': password,
            if (email != null) 'email': email,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_username', username);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Registration failed (${response.statusCode}): ${response.body}');
    }
  }

  /// POST /api/auth/login — stores the returned JWT automatically.
  Future<String> login({
    required String username,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      // Accept both common JWT response field names.
      final token = body['token'] as String? ?? body['accessToken'] as String?;
      if (token == null) {
        throw Exception(
            'Login succeeded but no token found in response: $body');
      }
      await _saveToken(token);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_username', username);

      final meshId = body['offlineMeshId'] as String?;
      if (meshId != null) {
        final profile = {
          'id': body['id']?.toString() ?? '',
          'username': username,
          'email': body['email']?.toString() ?? '',
          'offlineMeshId': meshId,
        };
        await prefs.setString('cached_user_profile', jsonEncode(profile));
      }

      return token;
    } else {
      throw Exception(
          'Login failed (${response.statusCode}): ${response.body}');
    }
  }

  /// Retrieve the last logged-in username persisted on device
  static Future<String?> getLastUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_username');
  }

  /// Check whether an offline user profile is cached on this device
  static Future<bool> hasCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('cached_user_profile') != null;
  }

  /// GET /api/auth/me — returns the current user profile.
  Future<Map<String, dynamic>> me() async {
    if (_jwtToken == null) throw Exception('Not authenticated');

    final response = await http
        .get(
          Uri.parse('$baseUrl/api/auth/me'),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      checkResponse(response.statusCode, _jwtToken!);
      throw Exception(
          'GET /api/auth/me failed (${response.statusCode}): ${response.body}');
    }
  }

  /// Clear the stored token (logout).
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    _jwtToken = null;
  }
}

class SessionExpiredException implements Exception {
  const SessionExpiredException();
  @override
  String toString() =>
      'Your session has expired or was rejected. Please sign in again.';
}
