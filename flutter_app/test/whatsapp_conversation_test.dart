import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/models/message.dart';
import 'package:flutter_app/core/transport/transport_type.dart';
import 'package:flutter_app/features/chat/models/conversation_summary.dart';

void main() {
  group('WhatsApp Phase 1: Conversation & Message Features', () {
    test('ConversationSummary serialization and flag toggling', () {
      final now = DateTime.now();
      final summary = ConversationSummary(
        peerOfflineMeshId: 'mesh-user-bob',
        peerUsername: 'Bob Ross',
        lastMessage: 'Paint happy little trees',
        lastMessageSenderId: 'mesh-user-bob',
        lastMessageStatus: 'delivered',
        lastMessageTime: now,
        unreadCount: 3,
        isPinned: true,
        isMuted: false,
        isArchived: false,
      );

      final json = summary.toJson();
      expect(json['peerOfflineMeshId'], 'mesh-user-bob');
      expect(json['peerUsername'], 'Bob Ross');
      expect(json['lastMessage'], 'Paint happy little trees');
      expect(json['lastMessageSenderId'], 'mesh-user-bob');
      expect(json['unreadCount'], 3);
      expect(json['lastMessageStatus'], 'delivered');
      expect(json['isPinned'], true);
      expect(json['isMuted'], false);
      expect(json['isArchived'], false);

      final deserialized = ConversationSummary.fromJson(json);
      expect(deserialized.peerOfflineMeshId, 'mesh-user-bob');
      expect(deserialized.peerUsername, 'Bob Ross');
      expect(deserialized.lastMessage, 'Paint happy little trees');
      expect(deserialized.lastMessageSenderId, 'mesh-user-bob');
      expect(deserialized.unreadCount, 3);
      expect(deserialized.lastMessageStatus, 'delivered');
      expect(deserialized.isPinned, true);
      expect(deserialized.isMuted, false);
      expect(deserialized.isArchived, false);

      // Verify copyWith mutability for pinning, muting, archiving
      final updated = summary.copyWith(
        isPinned: false,
        isMuted: true,
        isArchived: true,
        unreadCount: 0,
      );
      expect(updated.isPinned, false);
      expect(updated.isMuted, true);
      expect(updated.isArchived, true);
      expect(updated.unreadCount, 0);
    });

    test('Message model serialization supports edit and delete metadata', () {
      final now = DateTime.now();
      final editedTime = now.add(const Duration(minutes: 5));

      final originalMsg = Message(
        id: 'msg-999',
        senderOfflineMeshId: 'mesh-user-alice',
        recipientOfflineMeshId: 'mesh-user-bob',
        content: 'Original message text',
        createdAt: now,
        status: 'sent',
        transport: TransportType.WIFI_LAN,
      );

      expect(originalMsg.isEdited, false);
      expect(originalMsg.isDeleted, false);
      expect(originalMsg.editedAt, isNull);

      // Edit message
      final editedMsg = originalMsg.copyWith(
        content: 'Updated corrected text',
        isEdited: true,
        editedAt: editedTime,
      );
      expect(editedMsg.content, 'Updated corrected text');
      expect(editedMsg.isEdited, true);
      expect(editedMsg.editedAt, editedTime);

      final editedJson = editedMsg.toJson();
      expect(editedJson['isEdited'], true);
      expect(editedJson['editedAt'], editedTime.toIso8601String());

      final deserializedEdited = Message.fromJson(editedJson);
      expect(deserializedEdited.isEdited, true);
      expect(deserializedEdited.content, 'Updated corrected text');
      expect(deserializedEdited.editedAt, isNotNull);

      // Delete message for everyone
      final deletedMsg = originalMsg.copyWith(
        content: '🚫 This message was deleted',
        isDeleted: true,
      );
      expect(deletedMsg.isDeleted, true);
      expect(deletedMsg.content, '🚫 This message was deleted');

      final deletedJson = deletedMsg.toJson();
      expect(deletedJson['isDeleted'], true);

      final deserializedDeleted = Message.fromJson(deletedJson);
      expect(deserializedDeleted.isDeleted, true);
      expect(deserializedDeleted.content, '🚫 This message was deleted');
    });

    test('Message status progression: pending -> sent -> delivered -> read', () {
      final baseMsg = Message(
        id: 'msg-status-1',
        senderOfflineMeshId: 'alice',
        recipientOfflineMeshId: 'bob',
        content: 'Check receipt states',
        createdAt: DateTime.now(),
        status: 'pending',
      );

      final sentMsg = baseMsg.copyWith(status: 'sent');
      expect(sentMsg.status, 'sent');

      final deliveredMsg = sentMsg.copyWith(status: 'delivered');
      expect(deliveredMsg.status, 'delivered');

      final readMsg = deliveredMsg.copyWith(status: 'read');
      expect(readMsg.status, 'read');
    });

    test('Conversation list filter predicates', () {
      final convs = [
        ConversationSummary(
          peerOfflineMeshId: 'u1',
          peerUsername: 'Alice',
          lastMessage: 'Hi',
          lastMessageSenderId: 'u1',
          lastMessageStatus: 'delivered',
          lastMessageTime: DateTime.now().subtract(const Duration(minutes: 10)),
          unreadCount: 0,
          isPinned: true,
          isArchived: false,
        ),
        ConversationSummary(
          peerOfflineMeshId: 'u2',
          peerUsername: 'Bob',
          lastMessage: 'New note',
          lastMessageSenderId: 'u2',
          lastMessageStatus: 'read',
          lastMessageTime: DateTime.now().subtract(const Duration(minutes: 5)),
          unreadCount: 2,
          isPinned: false,
          isArchived: false,
        ),
        ConversationSummary(
          peerOfflineMeshId: 'u3',
          peerUsername: 'Charlie',
          lastMessage: 'Archived chat',
          lastMessageSenderId: 'u3',
          lastMessageStatus: 'sent',
          lastMessageTime: DateTime.now().subtract(const Duration(days: 1)),
          unreadCount: 0,
          isPinned: false,
          isArchived: true,
        ),
      ];

      // Unread filter
      final unread = convs.where((c) => c.unreadCount > 0).toList();
      expect(unread.length, 1);
      expect(unread.first.peerOfflineMeshId, 'u2');

      // Pinned filter
      final pinned = convs.where((c) => c.isPinned).toList();
      expect(pinned.length, 1);
      expect(pinned.first.peerOfflineMeshId, 'u1');

      // Archived filter
      final archived = convs.where((c) => c.isArchived).toList();
      expect(archived.length, 1);
      expect(archived.first.peerOfflineMeshId, 'u3');

      // Active non-archived
      final active = convs.where((c) => !c.isArchived).toList();
      expect(active.length, 2);
    });
  });
}
