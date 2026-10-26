import '../../../core/network/auth_service.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/message.dart';
import 'package:uuid/uuid.dart';
import '../models/group_chat_model.dart';

class GroupService {
  final String baseUrl;
  final String jwtToken;

  GroupService({String? baseUrl, required this.jwtToken})
      : baseUrl = baseUrl ?? AppConfig.backendBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      };

  Future<GroupChat> createGroup({
    required String name,
    String? description,
    required List<String> memberOfflineMeshIds,
  }) async {
    if (jwtToken.isNotEmpty) {
      try {
        final response = await http
            .post(
              Uri.parse('$baseUrl/api/groups'),
              headers: _headers,
              body: jsonEncode({
                'name': name,
                'description': description,
                'memberOfflineMeshIds': memberOfflineMeshIds,
              }),
            )
            .timeout(const Duration(seconds: 5));

        AuthService.checkResponse(response.statusCode, jwtToken);

        if (response.statusCode == 201 || response.statusCode == 200) {
          final json = jsonDecode(response.body);
          final group = GroupChat.fromJson(json);
          await _cacheGroup(group);
          return group;
        }
      } catch (e) {
        debugPrint(
            'Remote group creation failed ($e). Creating offline local group.');
      }
    }

    // Fallback: Create offline mesh group locally
    final prefs = await SharedPreferences.getInstance();
    final cachedRaw = prefs.getString('cached_user_profile');
    String myMeshId = 'ME';
    String myUsername = 'Me';
    if (cachedRaw != null) {
      try {
        final data = jsonDecode(cachedRaw);
        myMeshId = data['offlineMeshId']?.toString() ?? 'ME';
        myUsername = data['username']?.toString() ?? 'Me';
      } catch (_) {}
    }

    final localMembers = [
      GroupMemberModel(
        offlineMeshId: myMeshId,
        username: myUsername,
        role: 'ADMIN',
        joinedAt: DateTime.now(),
      ),
      ...memberOfflineMeshIds.map(
        (id) => GroupMemberModel(
          offlineMeshId: id,
          username: id,
          role: 'MEMBER',
          joinedAt: DateTime.now(),
        ),
      ),
    ];

    final localGroup = GroupChat(
      id: const Uuid().v4(),
      name: name,
      description: description,
      createdByOfflineMeshId: myMeshId,
      createdAt: DateTime.now(),
      members: localMembers,
    );

    await _cacheGroup(localGroup);
    return localGroup;
  }

  Future<List<GroupChat>> getUserGroups() async {
    final prefs = await SharedPreferences.getInstance();

    if (jwtToken.isNotEmpty) {
      try {
        final response = await http
            .get(
              Uri.parse('$baseUrl/api/groups'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 4));

        AuthService.checkResponse(response.statusCode, jwtToken);

        if (response.statusCode == 200) {
          await prefs.setString('cached_user_groups', response.body);
          final List list = jsonDecode(response.body);
          return list.map((g) => GroupChat.fromJson(g)).toList();
        }
      } catch (e) {
        debugPrint(
            'Could not fetch remote groups ($e). Checking offline cache.');
      }
    }

    final cached = prefs.getString('cached_user_groups');
    if (cached != null) {
      try {
        final List list = jsonDecode(cached);
        return list.map((g) => GroupChat.fromJson(g)).toList();
      } catch (_) {}
    }

    return <GroupChat>[];
  }

  Future<void> saveGroupsLocally(List<GroupChat> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'cached_user_groups',
      jsonEncode(groups.map((g) => g.toJson()).toList()),
    );
  }

  Future<GroupChat> getGroupDetails(String groupId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/groups/$groupId'),
      headers: _headers,
    );

    AuthService.checkResponse(response.statusCode, jwtToken);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final group = GroupChat.fromJson(json);
      await _cacheGroup(group);
      return group;
    } else {
      throw Exception('Failed to get group details');
    }
  }

  Future<GroupChat> addMember(
      String groupId, String memberOfflineMeshId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/groups/$groupId/members/$memberOfflineMeshId'),
      headers: _headers,
    );

    AuthService.checkResponse(response.statusCode, jwtToken);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final group = GroupChat.fromJson(json);
      await _cacheGroup(group);
      return group;
    } else {
      throw Exception('Failed to add member to group');
    }
  }

  Future<GroupChat> removeMember(
      String groupId, String memberOfflineMeshId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/groups/$groupId/members/$memberOfflineMeshId'),
      headers: _headers,
    );

    AuthService.checkResponse(response.statusCode, jwtToken);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final group = GroupChat.fromJson(json);
      await _cacheGroup(group);
      return group;
    } else {
      throw Exception('Failed to remove member from group');
    }
  }

  Future<List<Message>> getGroupMessages(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'cached_group_msgs_$groupId';

    if (jwtToken.isNotEmpty) {
      try {
        final response = await http
            .get(
              Uri.parse('$baseUrl/api/groups/$groupId/messages'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 4));

        AuthService.checkResponse(response.statusCode, jwtToken);

        if (response.statusCode == 200) {
          await prefs.setString(cacheKey, response.body);
          final List list = jsonDecode(response.body);
          return list.map((m) => Message.fromJson(m)).toList();
        }
      } catch (e) {
        debugPrint(
            'Could not fetch remote group messages ($e). Checking offline cache.');
      }
    }

    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        final List list = jsonDecode(cached);
        return list.map((m) => Message.fromJson(m)).toList();
      } catch (_) {}
    }

    return <Message>[];
  }

  Future<Message> sendGroupMessage(String groupId, String content) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/groups/$groupId/messages'),
      headers: _headers,
      body: jsonEncode({'content': content}),
    );

    AuthService.checkResponse(response.statusCode, jwtToken);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return Message.fromJson(json);
    } else {
      throw Exception('Failed to send group message');
    }
  }

  Future<void> _cacheGroup(GroupChat group) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cached_user_groups');
    List<GroupChat> list = [];
    if (cached != null) {
      try {
        final List raw = jsonDecode(cached);
        list = raw.map((g) => GroupChat.fromJson(g)).toList();
      } catch (_) {}
    }
    list.removeWhere((g) => g.id == group.id);
    list.insert(0, group);
    await prefs.setString(
        'cached_user_groups', jsonEncode(list.map((g) => g.toJson()).toList()));
  }
}
