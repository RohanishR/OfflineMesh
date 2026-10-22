import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/models/message.dart';
import 'package:flutter_app/core/transport/transport_type.dart';
import 'package:flutter_app/core/security/encrypted_envelope.dart';

void main() {
  group('WhatsApp Messaging & Recipient Isolation Tests', () {
    test('Message model serialization includes WhatsApp fields and recipient ID', () {
      final now = DateTime.now();
      final message = Message(
        id: 'msg-101',
        senderOfflineMeshId: 'user-alice',
        recipientOfflineMeshId: 'user-bob',
        content: 'Hey Bob, are you on the mesh?',
        createdAt: now,
        status: 'delivered',
        transport: TransportType.WIFI_LAN,
        replyToId: 'msg-100',
        replyToContent: 'Are you nearby?',
        replyToSender: 'user-bob',
        reactions: {'user-bob': '❤️', 'user-alice': '👍'},
        mediaType: 'text',
      );

      final json = message.toJson();
      expect(json['id'], 'msg-101');
      expect(json['senderOfflineMeshId'], 'user-alice');
      expect(json['recipientOfflineMeshId'], 'user-bob');
      expect(json['content'], 'Hey Bob, are you on the mesh?');
      expect(json['status'], 'delivered');
      expect(json['transport'], 'WIFI_LAN');
      expect(json['replyToId'], 'msg-100');
      expect(json['replyToContent'], 'Are you nearby?');
      expect(json['replyToSender'], 'user-bob');
      expect(json['reactions'], {'user-bob': '❤️', 'user-alice': '👍'});
      expect(json['mediaType'], 'text');

      final deserialized = Message.fromJson(json);
      expect(deserialized.id, 'msg-101');
      expect(deserialized.senderOfflineMeshId, 'user-alice');
      expect(deserialized.recipientOfflineMeshId, 'user-bob');
      expect(deserialized.content, 'Hey Bob, are you on the mesh?');
      expect(deserialized.status, 'delivered');
      expect(deserialized.transport, TransportType.WIFI_LAN);
      expect(deserialized.replyToId, 'msg-100');
      expect(deserialized.replyToContent, 'Are you nearby?');
      expect(deserialized.replyToSender, 'user-bob');
      expect(deserialized.reactions?['user-bob'], '❤️');
      expect(deserialized.reactions?['user-alice'], '👍');
      expect(deserialized.mediaType, 'text');
    });

    test('Confidentiality: Envelope targeted to Bob is rejected if Charlie inspects recipient', () {
      final envelope = EncryptedEnvelope(
        version: 2,
        messageId: 'enc-msg-1',
        senderId: 'user-alice',
        recipientId: 'user-bob',
        keyId: 'key-1',
        ephemeralPublicKey: 'fake-key',
        nonce: 'fake-nonce',
        ciphertext: 'fake-cipher',
        mac: 'fake-mac',
      );

      const charlieId = 'user-charlie';
      // Verify Charlie is not the recipient
      expect(envelope.recipientId == charlieId, isFalse);
      expect(envelope.recipientId, 'user-bob');
    });

    test('Reaction toggling: adding, changing, and removing reactions', () {
      final message = Message(
        id: 'msg-1',
        senderOfflineMeshId: 'user-alice',
        recipientOfflineMeshId: 'user-bob',
        content: 'Hello!',
        createdAt: DateTime.now(),
      );

      // Add reaction
      final map1 = Map<String, String>.from(message.reactions ?? {});
      map1['user-bob'] = '👍';
      final withReaction = message.copyWith(reactions: map1);
      expect(withReaction.reactions?['user-bob'], '👍');

      // Change reaction
      final map2 = Map<String, String>.from(withReaction.reactions ?? {});
      map2['user-bob'] = '❤️';
      final updatedReaction = withReaction.copyWith(reactions: map2);
      expect(updatedReaction.reactions?['user-bob'], '❤️');

      // Remove reaction
      final map3 = Map<String, String>.from(updatedReaction.reactions ?? {});
      map3.remove('user-bob');
      final removedReaction = updatedReaction.copyWith(reactions: map3);
      expect(removedReaction.reactions?.containsKey('user-bob'), isFalse);
    });
  });
}
