import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Central application configuration.
/// Configured for Local Wi-Fi (No USB / no adb reverse required).
class AppConfig {
  AppConfig._();

  /// Default Host PC Wi-Fi IP address and backend port.
  static const String defaultHost = '172.20.193.151';
  static const int defaultPort = 8081;
  static const String defaultUrl = 'http://$defaultHost:$defaultPort';

  static String _backendBaseUrl = defaultUrl;
  static final changes = ValueNotifier<String>(defaultUrl);

  /// Current backend base URL.
  static String get backendBaseUrl => _backendBaseUrl;

  /// Loads custom backend URL if saved in SharedPreferences.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('custom_backend_base_url');
      if (saved != null && saved.trim().isNotEmpty) {
        _backendBaseUrl = normalizeUrl(saved);
      } else {
        _backendBaseUrl = defaultUrl;
      }
    } catch (_) {
      _backendBaseUrl = defaultUrl;
    }
    changes.value = _backendBaseUrl;
  }

  /// Accept a server origin only; never silently accept API paths or credentials.
  static String normalizeUrl(String input) {
    var value = input.trim();
    if (!value.contains('://')) value = 'http://$value';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.host.contains(RegExp(r'\s')) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException(
          'Enter a server address such as http://192.168.137.1:8081, without an API path.');
    }
    return uri.replace(path: '').toString();
  }

  static Future<void> setBackendBaseUrl(String url) async {
    final formatted = normalizeUrl(url);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('custom_backend_base_url', formatted)) {
      throw StateError('Could not save the server address. Try again.');
    }
    if (formatted != _backendBaseUrl) {
      // Credentials for one server must not be sent to a different endpoint.
      await prefs.remove('jwt_token');
    }
    _backendBaseUrl = formatted;
    changes.value = formatted;
  }

  /// Check the public health endpoint, without sending credentials.
  static Future<bool> testConnection(String url, {http.Client? client}) async {
    final target = normalizeUrl(url);
    final connection = client ?? http.Client();
    try {
      final response = await connection
          .get(Uri.parse('$target/api/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return false;
      final body = jsonDecode(response.body);
      return body is Map &&
          body['status'] == 'UP' &&
          body['service'] == 'OfflineMesh Backend';
    } catch (_) {
      return false;
    } finally {
      if (client == null) connection.close();
    }
  }

  /// Default WebRTC STUN/TURN ICE Servers configuration
  static const List<Map<String, dynamic>> defaultIceServers = [
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ]
    },
  ];

  static List<Map<String, dynamic>>? _cachedIceServers;

  /// Loads configured ICE servers (custom TURN/STUN or default Google STUN)
  static Future<List<Map<String, dynamic>>> getIceServers() async {
    if (_cachedIceServers != null) return _cachedIceServers!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('custom_ice_servers');
      if (saved != null && saved.trim().isNotEmpty) {
        final List<dynamic> list = jsonDecode(saved);
        _cachedIceServers = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        return _cachedIceServers!;
      }
    } catch (e) {
      debugPrint('Error loading custom ICE servers: $e');
    }
    return defaultIceServers;
  }

  /// Sets custom STUN/TURN ICE servers configuration
  static Future<void> setCustomIceServers(List<Map<String, dynamic>> servers) async {
    _cachedIceServers = servers;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_ice_servers', jsonEncode(servers));
  }
}
