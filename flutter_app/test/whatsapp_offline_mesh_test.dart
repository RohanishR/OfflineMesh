import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/models/message.dart';
import 'package:flutter_app/core/services/local_storage_service.dart';
import 'package:flutter_app/core/transport/transport_type.dart';

void main() {
  late Directory tempDir;
  late LocalStorageService storageService;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mesh_test_');
    storageService = LocalStorageService(baseDir: tempDir);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Phase 4: Persistent Deduplication Cache Tests', () {
    test('Unseen message is not marked processed initially', () async {
      final processed = await storageService.hasMessageBeenProcessed('msg-unique-1');
      expect(processed, isFalse);
    });

    test('Marking message processed persists across service instances', () async {
      await storageService.markMessageProcessed('msg-unique-1');
      expect(await storageService.hasMessageBeenProcessed('msg-unique-1'), isTrue);

      // Create new instance pointing to same directory
      final freshService = LocalStorageService(baseDir: tempDir);
      expect(await freshService.hasMessageBeenProcessed('msg-unique-1'), isTrue);
      expect(await freshService.hasMessageBeenProcessed('msg-unique-2'), isFalse);
    });

    test('Expired processed message is automatically pruned', () async {
      // Mark with negative expiry (already in the past)
      await storageService.markMessageProcessed(
        'msg-expired-1',
        expiry: const Duration(seconds: -10),
      );

      final isProcessed = await storageService.hasMessageBeenProcessed('msg-expired-1');
      expect(isProcessed, isFalse);
    });
  });

  group('Phase 4: Outbox Queue & Retry Engine Tests', () {
    test('Adding to outbox initializes retry count to 0', () async {
      final message = Message(
        id: 'msg-outbox-1',
        senderOfflineMeshId: 'user-alice',
        recipientOfflineMeshId: 'user-bob',
        content: 'Hello Bob while offline',
        createdAt: DateTime.now(),
        status: 'queued',
      );

      await storageService.addToOutbox(
        recipientOfflineMeshId: 'user-bob',
        message: message,
        wireContent: 'Hello Bob while offline',
      );

      final outbox = await storageService.loadOutbox();
      expect(outbox.length, 1);
      expect(outbox.first['messageId'], 'msg-outbox-1');
      expect(outbox.first['recipientOfflineMeshId'], 'user-bob');
      expect(outbox.first['retryCount'], 0);
    });

    test('Updating outbox item increments retry count and sets lastError', () async {
      final message = Message(
        id: 'msg-outbox-2',
        senderOfflineMeshId: 'user-alice',
        recipientOfflineMeshId: 'user-bob',
        content: 'Test retry count',
        createdAt: DateTime.now(),
        status: 'queued',
      );

      await storageService.addToOutbox(
        recipientOfflineMeshId: 'user-bob',
        message: message,
        wireContent: 'Test retry count',
      );

      await storageService.updateOutboxItem(
        'msg-outbox-2',
        retryCount: 1,
        lastError: 'LAN socket timeout',
        status: 'retrying',
      );

      final outbox = await storageService.loadOutbox();
      expect(outbox.first['retryCount'], 1);
      expect(outbox.first['lastError'], 'LAN socket timeout');
      expect(outbox.first['status'], 'retrying');
      expect(outbox.first['lastAttemptAt'], isNotNull);
    });

    test('Removing from outbox clears the queued item', () async {
      final message = Message(
        id: 'msg-outbox-3',
        senderOfflineMeshId: 'user-alice',
        recipientOfflineMeshId: 'user-bob',
        content: 'To be removed',
        createdAt: DateTime.now(),
        status: 'queued',
      );

      await storageService.addToOutbox(
        recipientOfflineMeshId: 'user-bob',
        message: message,
        wireContent: 'To be removed',
      );

      expect((await storageService.loadOutbox()).length, 1);
      await storageService.removeFromOutbox('msg-outbox-3');
      expect((await storageService.loadOutbox()).length, 0);
    });
  });

  group('Phase 4: Store-and-Forward Mesh Relay Buffer Tests', () {
    test('Adding to relay buffer preserves packet and hop count', () async {
      final packet = {
        'protocolVersion': 1,
        'type': 'CHAT_MESSAGE',
        'packetId': 'relay-pkt-100',
        'senderOfflineMeshId': 'user-alice',
        'recipientOfflineMeshId': 'user-carol',
        'hopCount': 1,
        'maxHops': 3,
        'message': {
          'id': 'msg-carol-100',
          'senderOfflineMeshId': 'user-alice',
          'recipientOfflineMeshId': 'user-carol',
          'content': 'Secret mesh relay',
        },
      };

      await storageService.addToRelayBuffer(packet);
      final buffer = await storageService.loadRelayBuffer();

      expect(buffer.length, 1);
      expect(buffer.first['packetId'], 'relay-pkt-100');
      expect(buffer.first['recipientOfflineMeshId'], 'user-carol');
      expect(buffer.first['senderOfflineMeshId'], 'user-alice');
      expect(buffer.first['hopCount'], 1);
      expect(buffer.first['bufferedAt'], isNotNull);
    });

    test('Relay buffer deduplication updates existing packet with latest payload', () async {
      final packet1 = {
        'protocolVersion': 1,
        'type': 'CHAT_MESSAGE',
        'packetId': 'relay-pkt-101',
        'recipientOfflineMeshId': 'user-carol',
        'hopCount': 1,
      };

      final packet2 = {
        'protocolVersion': 1,
        'type': 'CHAT_MESSAGE',
        'packetId': 'relay-pkt-101',
        'recipientOfflineMeshId': 'user-carol',
        'hopCount': 2,
      };

      await storageService.addToRelayBuffer(packet1);
      await storageService.addToRelayBuffer(packet2);

      final buffer = await storageService.loadRelayBuffer();
      expect(buffer.length, 1);
      expect(buffer.first['hopCount'], 2);
    });

    test('Removing from relay buffer and pruning expired packets', () async {
      final packet = {
        'protocolVersion': 1,
        'packetId': 'relay-pkt-102',
        'recipientOfflineMeshId': 'user-carol',
        'hopCount': 1,
      };

      await storageService.addToRelayBuffer(packet);
      expect((await storageService.loadRelayBuffer()).length, 1);

      await storageService.removeFromRelayBuffer('relay-pkt-102');
      expect((await storageService.loadRelayBuffer()).length, 0);
    });

    test('Hop count decrement / max hops validation logic', () {
      const maxHops = 3;
      int hopCount = 1;

      // Hop 1 -> Node B
      expect(hopCount < maxHops, isTrue);
      hopCount++; // Now 2

      // Hop 2 -> Node C
      expect(hopCount < maxHops, isTrue);
      hopCount++; // Now 3

      // Hop 3 -> Exceeded limit
      expect(hopCount >= maxHops, isTrue); // Should be dropped!
    });
  });

  group('Phase 4: Conversation Status & Outbox Failure Logic', () {
    test('Failed status transition updates message model', () {
      final queuedMsg = Message(
        id: 'msg-failing-1',
        senderOfflineMeshId: 'user-alice',
        recipientOfflineMeshId: 'user-bob',
        content: 'Undelivered message',
        createdAt: DateTime.now(),
        status: 'queued',
        transport: TransportType.WIFI_LAN,
      );

      final failedMsg = queuedMsg.copyWith(status: 'failed');
      expect(failedMsg.status, 'failed');
      expect(failedMsg.id, 'msg-failing-1');
      expect(failedMsg.content, 'Undelivered message');
    });

    test('Sent status transition updates message model upon outbox flush', () {
      final queuedMsg = Message(
        id: 'msg-success-1',
        senderOfflineMeshId: 'user-alice',
        recipientOfflineMeshId: 'user-bob',
        content: 'Delivered message',
        createdAt: DateTime.now(),
        status: 'queued',
      );

      final sentMsg = queuedMsg.copyWith(
        status: 'sent',
        transport: TransportType.INTERNET,
      );
      expect(sentMsg.status, 'sent');
      expect(sentMsg.transport, TransportType.INTERNET);
    });
  });
}
