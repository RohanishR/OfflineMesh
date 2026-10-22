import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/user.dart';

class FriendService {
  final String baseUrl;
  final String jwtToken;

  FriendService({String? baseUrl, required this.jwtToken}) 
      : baseUrl = baseUrl ?? AppConfig.backendBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      };

  Future<List<UserProfile>> getFriends() async {
    final prefs = await SharedPreferences.getInstance();

    if (jwtToken.isNotEmpty) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/api/friends'),
          headers: _headers,
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          await prefs.setString('cached_friends_list', response.body);
          Iterable l = jsonDecode(response.body);
          return List<UserProfile>.from(l.map((model) => UserProfile.fromJson(model)));
        }
      } catch (e) {
        debugPrint('Could not fetch remote friends ($e). Checking offline cache.');
      }
    }

    final cached = prefs.getString('cached_friends_list');
    if (cached != null) {
      try {
        Iterable l = jsonDecode(cached);
        return List<UserProfile>.from(l.map((model) => UserProfile.fromJson(model)));
      } catch (_) {}
    }

    return <UserProfile>[];
  }

  Future<UserProfile> connect(String offlineMeshId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/friends/connect'),
      headers: _headers,
      body: jsonEncode({'offlineMeshId': offlineMeshId}),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return UserProfile.fromJson(body['friend']);
    } else {
      throw Exception('Failed to connect: ${response.body}');
    }
  }

  Future<void> removeFriend(String offlineMeshId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/friends/$offlineMeshId'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to remove friend');
    }
  }
}
