import 'dart:convert';
import 'package:http/http.dart' as http;
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
    final response = await http.get(
      Uri.parse('$baseUrl/api/users/me/profile'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return UserProfile.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load my profile');
    }
  }
}
