import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

/// Handles authentication against the OfflineMesh backend.
/// Stores the JWT token in SharedPreferences for session persistence.
class AuthService {
  final String baseUrl;

  String? _jwtToken;

  AuthService({String? baseUrl}) : baseUrl = baseUrl ?? AppConfig.backendBaseUrl;

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
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        if (email != null) 'email': email,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Registration failed (${response.statusCode}): ${response.body}');
    }
  }

  /// POST /api/auth/login — stores the returned JWT automatically.
  Future<String> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      // Accept both common JWT response field names.
      final token = body['token'] as String? ?? body['accessToken'] as String?;
      if (token == null) {
        throw Exception('Login succeeded but no token found in response: $body');
      }
      await _saveToken(token);
      return token;
    } else {
      throw Exception('Login failed (${response.statusCode}): ${response.body}');
    }
  }

  /// GET /api/auth/me — returns the current user profile.
  Future<Map<String, dynamic>> me() async {
    if (_jwtToken == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: _authHeaders,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('GET /api/auth/me failed (${response.statusCode}): ${response.body}');
    }
  }

  /// Clear the stored token (logout).
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    _jwtToken = null;
  }
}
