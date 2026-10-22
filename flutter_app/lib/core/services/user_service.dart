import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/user.dart';

class UserService {
  final String baseUrl;
  final String jwtToken;

  UserService({String? baseUrl, required this.jwtToken}) 
      : baseUrl = baseUrl ?? AppConfig.backendBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      };

  Future<UserProfile> getPublicProfile(String offlineMeshId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/users/$offlineMeshId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return UserProfile.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load profile');
    }
  }

  Future<UserProfile> getMyProfile() async {
    final prefs = await SharedPreferences.getInstance();

    if (jwtToken.isNotEmpty) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/api/users/me/profile'),
          headers: _headers,
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          await prefs.setString('cached_user_profile', response.body);
          return UserProfile.fromJson(jsonDecode(response.body));
        }
      } catch (e) {
        debugPrint('Could not fetch remote profile ($e). Checking offline cache.');
      }
    }

    final cached = prefs.getString('cached_user_profile');
    if (cached != null) {
      return UserProfile.fromJson(jsonDecode(cached));
    }

    throw Exception('Failed to load profile and no offline cached profile found');
  }
}
