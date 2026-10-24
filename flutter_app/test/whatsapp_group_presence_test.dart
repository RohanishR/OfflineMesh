import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app/features/chat/models/group_chat_model.dart';
import 'package:flutter_app/features/chat/models/conversation_summary.dart';
import 'package:flutter_app/core/services/presence_service.dart';
import 'package:flutter_app/core/services/friend_service.dart';
import 'package:flutter_app/features/chat/services/group_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WhatsApp Phase 3: Group Chats, Presence & Blocking', () {
    test('GroupMemberModel correctly identifies roles and serializes JSON', () {
      final now = DateTime.now();
      final admin = GroupMemberModel(
        offlineMeshId: 'mesh-user-alice',
        username: 'Alice',
        role: 'ADMIN',
        joinedAt: now,
      );
      final member = GroupMemberModel(
        offlineMeshId: 'mesh-user-bob',
        username: 'Bob',
        role: 'MEMBER',
        joinedAt: now,
      );

      expect(admin.isAdmin, isTrue);
      expect(member.isAdmin, isFalse);

      final adminJson = admin.toJson();
      expect(adminJson['offlineMeshId'], 'mesh-user-alice');
      expect(adminJson['username'], 'Alice');
      expect(adminJson['role'], 'ADMIN');

      final deserializedAdmin = GroupMemberModel.fromJson(adminJson);
      expect(deserializedAdmin.offlineMeshId, 'mesh-user-alice');
      expect(deserializedAdmin.username, 'Alice');
      expect(deserializedAdmin.isAdmin, isTrue);
    });

    test('GroupChat model supports members, admin tracking, and JSON serialization', () {
      final now = DateTime.now();
      final group = GroupChat(
        id: 'group-uuid-1234',
        name: 'Mesh Core Team',
        description: 'Decentralized mesh protocol contributors',
        createdByOfflineMeshId: 'mesh-user-alice',
        createdAt: now,
        members: [
          GroupMemberModel(
            offlineMeshId: 'mesh-user-alice',
            username: 'Alice',
            role: 'ADMIN',
            joinedAt: now,
          ),
          GroupMemberModel(
            offlineMeshId: 'mesh-user-bob',
            username: 'Bob',
            role: 'MEMBER',
            joinedAt: now,
          ),
        ],
        lastMessage: 'Let us deploy the mesh relay',
        lastMessageTime: now,
      );

      expect(group.id, 'group-uuid-1234');
      expect(group.name, 'Mesh Core Team');
      expect(group.members.length, 2);
      expect(group.members.any((m) => m.isAdmin && m.offlineMeshId == 'mesh-user-alice'), isTrue);

      final json = group.toJson();
      expect(json['id'], 'group-uuid-1234');
      expect(json['name'], 'Mesh Core Team');
      expect(json['description'], 'Decentralized mesh protocol contributors');
      expect(json['members'], isA<List>());
      expect((json['members'] as List).length, 2);

      final restored = GroupChat.fromJson(json);
      expect(restored.id, group.id);
      expect(restored.name, group.name);
      expect(restored.description, group.description);
      expect(restored.members.length, 2);
      expect(restored.lastMessage, 'Let us deploy the mesh relay');

      // Test copyWith
      final updated = group.copyWith(
        name: 'Mesh Alpha Team',
        lastMessage: 'Meeting adjourned',
      );
      expect(updated.name, 'Mesh Alpha Team');
      expect(updated.lastMessage, 'Meeting adjourned');
      expect(updated.id, group.id);
    });

    test('UserPresence model correctly tracks online, typing, and recording states', () {
      final now = DateTime.now();
      final presence = UserPresence(
        offlineMeshId: 'mesh-user-charlie',
        status: 'ONLINE',
        isTyping: true,
        isRecording: false,
        lastSeen: now,
      );

      expect(presence.isOnline, isTrue);
      expect(presence.isTyping, isTrue);
      expect(presence.isRecording, isFalse);

      final json = presence.toJson();
      expect(json['offlineMeshId'], 'mesh-user-charlie');
      expect(json['status'], 'ONLINE');
      expect(json['isTyping'], true);
      expect(json['isRecording'], false);

      final fromJson = UserPresence.fromJson(json);
      expect(fromJson.offlineMeshId, 'mesh-user-charlie');
      expect(fromJson.isOnline, isTrue);
      expect(fromJson.isTyping, isTrue);
      expect(fromJson.isRecording, isFalse);

      final recordingPresence = UserPresence(
        offlineMeshId: 'mesh-user-charlie',
        status: 'ONLINE',
        isTyping: false,
        isRecording: true,
        lastSeen: now,
      );
      expect(recordingPresence.isRecording, isTrue);
      expect(recordingPresence.isTyping, isFalse);
    });

    test('FriendService contact blocking and unblocking persists locally', () async {
      SharedPreferences.setMockInitialValues({
        'local_blocked_users': <String>['mesh-user-spammer'],
      });

      final friendService = FriendService(
        baseUrl: 'http://localhost:8080',
        jwtToken: '', // Offline / local test
      );

      expect(await friendService.isUserBlocked('mesh-user-spammer'), isTrue);
      expect(await friendService.isUserBlocked('mesh-user-goodfriend'), isFalse);

      // Block another user
      await friendService.blockUser('mesh-user-annoying');
      expect(await friendService.isUserBlocked('mesh-user-annoying'), isTrue);
      final blockedList = await friendService.getBlockedUserIds();
      expect(blockedList.contains('mesh-user-annoying'), isTrue);
      expect(blockedList.contains('mesh-user-spammer'), isTrue);

      // Unblock user
      await friendService.unblockUser('mesh-user-spammer');
      expect(await friendService.isUserBlocked('mesh-user-spammer'), isFalse);
      expect(await friendService.isUserBlocked('mesh-user-annoying'), isTrue);
    });

    test('GroupService local cache persists group list offline', () async {
      SharedPreferences.setMockInitialValues({});

      final groupService = GroupService(
        baseUrl: 'http://localhost:8080',
        jwtToken: '',
      );

      final now = DateTime.now();
      final initialGroups = [
        GroupChat(
          id: 'grp-001',
          name: 'Emergency Response Mesh',
          description: 'Local disaster coordination network',
          createdByOfflineMeshId: 'mesh-user-rescue1',
          createdAt: now,
          members: [
            GroupMemberModel(
              offlineMeshId: 'mesh-user-rescue1',
              username: 'Rescue 1',
              role: 'ADMIN',
              joinedAt: now,
            ),
          ],
        ),
      ];

      // Save to local cache
      await groupService.saveGroupsLocally(initialGroups);

      // Retrieve locally
      final cachedGroups = await groupService.getUserGroups();
      expect(cachedGroups.length, 1);
      expect(cachedGroups.first.id, 'grp-001');
      expect(cachedGroups.first.name, 'Emergency Response Mesh');
      expect(cachedGroups.first.description, 'Local disaster coordination network');
      expect(cachedGroups.first.members.first.isAdmin, isTrue);
    });

    test('ConversationSummary supports group conversation tagging and groupId', () {
      final now = DateTime.now();
      final groupSummary = ConversationSummary(
        peerOfflineMeshId: 'group:grp-001',
        peerUsername: 'Emergency Response Mesh',
        lastMessage: 'Local disaster coordination network',
        lastMessageSenderId: '',
        lastMessageStatus: 'sent',
        lastMessageTime: now,
        isGroup: true,
        groupId: 'grp-001',
      );

      expect(groupSummary.isGroup, isTrue);
      expect(groupSummary.groupId, 'grp-001');

      final json = groupSummary.toJson();
      expect(json['isGroup'], isTrue);
      expect(json['groupId'], 'grp-001');

      final restored = ConversationSummary.fromJson(json);
      expect(restored.isGroup, isTrue);
      expect(restored.groupId, 'grp-001');
      expect(restored.peerUsername, 'Emergency Response Mesh');
    });
  });
}
