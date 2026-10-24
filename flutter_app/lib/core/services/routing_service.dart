import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/message.dart';
import '../transport/transport_type.dart';
import '../security/e2e_encryption_service.dart';
import '../security/encrypted_envelope.dart';
import 'message_service.dart';
import 'wifi_messaging_service.dart';
import 'wifi_peer_discovery_service.dart';
import 'wifi_file_transfer_service.dart';
import 'local_storage_service.dart';
import '../models/discovered_peer.dart';
import '../../features/files/models/file_metadata.dart';
import '../../features/files/services/file_service.dart';

class RoutingService {
  final MessageService messageService;
  final FileService fileService;
  final WifiMessagingService wifiMessagingService;
  final WifiPeerDiscoveryService discoveryService;
  final WifiFileTransferService wifiFileTransferService;
  final E2eEncryptionService? encryptionService;
  final LocalStorageService localStorageService;

  final _incomingMessagesController = StreamController<Message>.broadcast();
  Stream<Message> get incomingMessages => _incomingMessagesController.stream;

  final _incomingFilesController = StreamController<FileMetadata>.broadcast();
  Stream<FileMetadata> get incomingFiles => _incomingFilesController.stream;

  List<DiscoveredPeer> _activePeers = [];
  
  StreamSubscription? _peersSubscription;
  StreamSubscription? _wifiMessagesSubscription;
  StreamSubscription? _internetMessagesSubscription;
  StreamSubscription? _statusUpdatesSubscription;
  StreamSubscription? _wifiFilesSubscription;
  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _relayedPacketsSubscription;
  Timer? _outboxRetryTimer;

  final List<FileMetadata> _localSentFiles = [];
  final List<FileMetadata> _localReceivedFiles = [];
  final Set<String> _recentlyDeliveredMessageIds = {};

  RoutingService({
    required this.messageService,
    required this.fileService,
    required this.wifiMessagingService,
    required this.discoveryService,
    required this.wifiFileTransferService,
    this.encryptionService,
    LocalStorageService? localStorageService,
  }) : localStorageService = localStorageService ?? LocalStorageService();

  void initialize() {
    _loadPersistedFiles();

    _peersSubscription = discoveryService.peersStream.listen((peers) {
      _activePeers = peers;
      flushOutbox();
    });

    _wifiMessagesSubscription = wifiMessagingService.incomingMessages.listen((message) {
      _deliverIncomingMessage(message, TransportType.WIFI_LAN);
    });

    _internetMessagesSubscription = messageService.incomingMessages.listen((message) {
      _deliverIncomingMessage(message, TransportType.INTERNET);
    });

    _statusUpdatesSubscription = messageService.statusUpdates.listen((statusMap) async {
      final status = statusMap['status']?.toString();
      final senderId = statusMap['senderOfflineMeshId']?.toString();
      final recipientId = statusMap['recipientOfflineMeshId']?.toString();
      final messageId = statusMap['messageId']?.toString();
      final newContent = statusMap['newContent']?.toString();

      if (status == 'READ' && recipientId != null) {
        final conversationPeer = recipientId;
        final msgs = await localStorageService.loadConversation(conversationPeer);
        bool changed = false;
        for (int i = 0; i < msgs.length; i++) {
          if (msgs[i].senderOfflineMeshId == wifiMessagingService.currentUser.offlineMeshId &&
              msgs[i].status.toLowerCase() != 'read') {
            msgs[i] = msgs[i].copyWith(status: 'read');
            changed = true;
            _incomingMessagesController.add(msgs[i]);
          }
        }
        if (changed) {
          await localStorageService.saveMessages(conversationPeer, msgs);
        }
      } else if (status == 'EDITED' && messageId != null && senderId != null && newContent != null) {
        final conversationPeer = senderId;
        final msgs = await localStorageService.loadConversation(conversationPeer);
        final idx = msgs.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          final updated = msgs[idx].copyWith(content: newContent, isEdited: true, editedAt: DateTime.now());
          await localStorageService.updateMessage(conversationPeer, updated);
          _incomingMessagesController.add(updated);
        }
      } else if (status == 'DELETED' && messageId != null && senderId != null) {
        final conversationPeer = senderId;
        final msgs = await localStorageService.loadConversation(conversationPeer);
        final idx = msgs.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          final updated = msgs[idx].copyWith(content: '🚫 This message was deleted', isDeleted: true);
          await localStorageService.updateMessage(conversationPeer, updated);
          _incomingMessagesController.add(updated);
        }
      }
    });

    _wifiFilesSubscription = wifiFileTransferService.incomingFiles.listen((fileMeta) {
      _deliverIncomingFile(fileMeta, 'WIFI_LAN');
    });

    _relayedPacketsSubscription = wifiMessagingService.relayedPackets.listen((packet) {
      handleRelayedPacket(packet);
    });

    _connectionStateSubscription = messageService.connectionStateStream.listen((connected) {
      if (connected) {
        debugPrint('Internet connection restored: triggering instant outbox flush.');
        flushOutbox();
      }
    });

    // Periodic outbox flush & relay buffer retry timer (every 20s)
    _outboxRetryTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      flushOutbox();
    });

    flushOutbox();
  }

  Future<void> _loadPersistedFiles() async {
    try {
      final sent = await localStorageService.loadSentFiles();
      final received = await localStorageService.loadReceivedFiles();
      _localSentFiles.clear();
      _localSentFiles.addAll(sent);
      _localReceivedFiles.clear();
      _localReceivedFiles.addAll(received);
    } catch (e) {
      debugPrint('Error loading persisted files: $e');
    }
  }

  Future<void> _deliverIncomingMessage(Message message, TransportType transport) async {
    message.transport = transport;

    final myOfflineMeshId = wifiMessagingService.currentUser.offlineMeshId;

    // 1. Loopback prevention: Ignore messages sent by ourselves
    if (message.senderOfflineMeshId == myOfflineMeshId) {
      debugPrint('Dropping loopback message from myself: ${message.id}');
      return;
    }

    // 2. Persistent deduplication across transports and app restarts
    if (_recentlyDeliveredMessageIds.contains(message.id) ||
        await localStorageService.hasMessageBeenProcessed(message.id)) {
      debugPrint('Dropping already delivered duplicate message: ${message.id}');
      return;
    }
    _recentlyDeliveredMessageIds.add(message.id);
    if (_recentlyDeliveredMessageIds.length > 500) {
      _recentlyDeliveredMessageIds.remove(_recentlyDeliveredMessageIds.first);
    }
    await localStorageService.markMessageProcessed(message.id);

    // 3. Encrypted envelope handling
    if (EncryptedEnvelope.isEncryptedEnvelope(message.content)) {
      try {
        final envelope = EncryptedEnvelope.fromJson(jsonDecode(message.content));

        // Strict confidentiality: If envelope has a recipient specified and it is NOT me, DROP!
        if (envelope.recipientId.isNotEmpty && envelope.recipientId != myOfflineMeshId) {
          debugPrint('Confidentiality drop: Encrypted envelope recipient ${envelope.recipientId} != my ID ($myOfflineMeshId)');
          return;
        }

        if (encryptionService != null) {
          final decryptedContent = await encryptionService!.decryptMessage(envelope);
          message = message.copyWith(
            content: decryptedContent,
            recipientOfflineMeshId: myOfflineMeshId,
          );
        } else {
          debugPrint('Cannot decrypt E2EE message without encryptionService; dropping message');
          return;
        }
      } catch (e) {
        debugPrint('Decryption or recipient mismatch error, dropping message: $e');
        return; // NEVER persist 'Unable to decrypt message' or leaked packets!
      }
    } else {
      // 4. Plaintext message recipient validation
      if (message.recipientOfflineMeshId != null &&
          message.recipientOfflineMeshId!.isNotEmpty &&
          message.recipientOfflineMeshId != myOfflineMeshId) {
        debugPrint('Confidentiality drop: Plaintext message recipient ${message.recipientOfflineMeshId} != my ID ($myOfflineMeshId)');
        return;
      }
      message = message.copyWith(
        recipientOfflineMeshId: message.recipientOfflineMeshId ?? myOfflineMeshId,
      );
    }

    // 5. Intercept WhatsApp emoji reactions & control messages
    try {
      final trimmed = message.content.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        final data = jsonDecode(trimmed);
        if (data is Map<String, dynamic> && data.containsKey('type')) {
          final type = data['type']?.toString();
          if (type == 'REACTION') {
            final targetId = data['targetMessageId']?.toString();
            final emoji = data['emoji']?.toString();
            final senderId = data['senderId']?.toString() ?? message.senderOfflineMeshId;
            if (targetId != null && emoji != null) {
              final conversationPeer = message.senderOfflineMeshId;
              final msgs = await localStorageService.loadConversation(conversationPeer);
              final idx = msgs.indexWhere((m) => m.id == targetId);
              if (idx != -1) {
                final targetMsg = msgs[idx];
                final currentReactions = Map<String, String>.from(targetMsg.reactions ?? {});
                if (currentReactions[senderId] == emoji) {
                  currentReactions.remove(senderId);
                } else {
                  currentReactions[senderId] = emoji;
                }
                final updated = targetMsg.copyWith(reactions: currentReactions);
                await localStorageService.saveMessage(conversationPeer, updated);
                _incomingMessagesController.add(updated);
                return;
              }
            }
          } else if (type == 'READ_RECEIPT') {
            final conversationPeer = message.senderOfflineMeshId;
            final msgs = await localStorageService.loadConversation(conversationPeer);
            bool changed = false;
            for (int i = 0; i < msgs.length; i++) {
              if (msgs[i].senderOfflineMeshId == myOfflineMeshId && msgs[i].status.toLowerCase() != 'read') {
                msgs[i] = msgs[i].copyWith(status: 'read');
                changed = true;
                _incomingMessagesController.add(msgs[i]);
              }
            }
            if (changed) {
              await localStorageService.saveMessages(conversationPeer, msgs);
            }
            return;
          } else if (type == 'EDIT_MESSAGE') {
            final targetId = data['messageId']?.toString();
            final newContent = data['newContent']?.toString();
            if (targetId != null && newContent != null) {
              final conversationPeer = message.senderOfflineMeshId;
              final msgs = await localStorageService.loadConversation(conversationPeer);
              final idx = msgs.indexWhere((m) => m.id == targetId);
              if (idx != -1) {
                final updated = msgs[idx].copyWith(content: newContent, isEdited: true, editedAt: DateTime.now());
                await localStorageService.updateMessage(conversationPeer, updated);
                _incomingMessagesController.add(updated);
                return;
              }
            }
          } else if (type == 'DELETE_MESSAGE') {
            final targetId = data['messageId']?.toString();
            if (targetId != null) {
              final conversationPeer = message.senderOfflineMeshId;
              final msgs = await localStorageService.loadConversation(conversationPeer);
              final idx = msgs.indexWhere((m) => m.id == targetId);
              if (idx != -1) {
                final updated = msgs[idx].copyWith(content: '🚫 This message was deleted', isDeleted: true);
                await localStorageService.updateMessage(conversationPeer, updated);
                _incomingMessagesController.add(updated);
                return;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Reaction/control message parsing note: $e');
    }

    // 6. Persist incoming message locally for offline access
    await localStorageService.saveMessage(message.senderOfflineMeshId, message);
    _incomingMessagesController.add(message);
  }

  Future<void> _deliverIncomingFile(FileMetadata fileMeta, String transport) async {
    fileMeta.transport = transport;

    if (fileMeta.isEncrypted && fileMeta.encryptedKeyEnvelope != null && encryptionService != null && fileMeta.localFilePath != null) {
      try {
        final encFile = File(fileMeta.localFilePath!);
        if (await encFile.exists()) {
          final docDir = await getApplicationDocumentsDirectory();
          final safeName = fileMeta.originalFileName.replaceAll(RegExp(r'[^a-zA-Z0-9.\-_]'), '_');
          final decryptedPath = p.join(docDir.path, safeName);
          final decFile = File(decryptedPath);

          await encryptionService!.decryptFile(
            encryptedFile: encFile,
            encryptedKeyEnvelopeJson: fileMeta.encryptedKeyEnvelope!,
            senderOfflineMeshId: fileMeta.senderOfflineMeshId,
            targetFile: decFile,
          );

          if (await encFile.exists() && encFile.path != decFile.path) {
            await encFile.delete();
          }

          fileMeta.localFilePath = decryptedPath;
        }
      } catch (e) {
        debugPrint('Failed to decrypt incoming $transport file: $e');
      }
    }

    _localReceivedFiles.removeWhere((f) => f.id == fileMeta.id);
    _localReceivedFiles.add(fileMeta);
    await localStorageService.saveReceivedFile(fileMeta);
    _incomingFilesController.add(fileMeta);

    // Also persist as an inline rich media message in the sender conversation
    try {
      final ext = fileMeta.originalFileName.split('.').last.toLowerCase();
      String mediaType = 'file';
      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext) || fileMeta.contentType.startsWith('image/')) {
        mediaType = 'image';
      } else if (['mp4', 'mov', 'avi', 'mkv'].contains(ext) || fileMeta.contentType.startsWith('video/')) {
        mediaType = 'video';
      } else if (['m4a', 'mp3', 'wav', 'aac', 'ogg'].contains(ext) || fileMeta.contentType.startsWith('audio/')) {
        mediaType = 'audio';
      }

      final mediaMessage = Message(
        id: fileMeta.id,
        senderOfflineMeshId: fileMeta.senderOfflineMeshId,
        recipientOfflineMeshId: fileMeta.recipientOfflineMeshId,
        content: fileMeta.originalFileName,
        createdAt: fileMeta.createdAt,
        status: 'delivered',
        transport: transport == 'WIFI_LAN' ? TransportType.WIFI_LAN : TransportType.INTERNET,
        mediaType: mediaType,
        mediaPath: fileMeta.localFilePath,
        fileName: fileMeta.originalFileName,
        fileSize: fileMeta.fileSize,
        fileHash: fileMeta.checksum,
      );

      await localStorageService.saveMessage(fileMeta.senderOfflineMeshId, mediaMessage);
      _incomingMessagesController.add(mediaMessage);
    } catch (e) {
      debugPrint('Failed to convert incoming file to media message: $e');
    }
  }

  void shutdown() {
    _peersSubscription?.cancel();
    _wifiMessagesSubscription?.cancel();
    _internetMessagesSubscription?.cancel();
    _wifiFilesSubscription?.cancel();
    _incomingMessagesController.close();
    _incomingFilesController.close();
  }

  bool isPeerNearby(String offlineMeshId) {
    try {
      final peer = _activePeers.firstWhere((p) => p.offlineMeshId == offlineMeshId);
      return peer.isReachable;
    } catch (e) {
      return false;
    }
  }

  DiscoveredPeer? getPeerByOfflineMeshId(String offlineMeshId) {
    try {
      return _activePeers.firstWhere((p) => p.offlineMeshId == offlineMeshId && p.isReachable);
    } catch (e) {
      return null;
    }
  }

  DiscoveredPeer? getNearbyPeer(String offlineMeshId) {
    return getPeerByOfflineMeshId(offlineMeshId);
  }

  void addManualPeer({
    required String offlineMeshId,
    required String displayName,
    required String ipAddress,
    required int port,
  }) {
    _activePeers.removeWhere((p) => p.offlineMeshId == offlineMeshId);
    _activePeers.add(
      DiscoveredPeer(
        offlineMeshId: offlineMeshId,
        displayName: displayName,
        deviceId: 'manual_${offlineMeshId.hashCode}',
        ipAddress: ipAddress,
        port: port,
        discoveryTimestamp: DateTime.now(),
        lastSeenTimestamp: DateTime.now(),
        isReachable: true,
      ),
    );
  }

  Future<List<TransportType>> getAvailableRoutes(String destId) async {
    final routes = <TransportType>[];

    // 1. WIFI_LAN
    if (isPeerNearby(destId)) {
      routes.add(TransportType.WIFI_LAN);
    }

    // 2. INTERNET (Only route if authenticated with valid token)
    if (messageService.jwtToken.isNotEmpty) {
      routes.add(TransportType.INTERNET);
    }
    
    return routes;
  }

  Future<Message> sendMessage(
    String recipientOfflineMeshId,
    String content, {
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
    String mediaType = 'text',
  }) async {
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();

    final localMessage = Message(
      id: messageId,
      senderOfflineMeshId: wifiMessagingService.currentUser.offlineMeshId,
      recipientOfflineMeshId: recipientOfflineMeshId,
      content: content,
      createdAt: DateTime.now(),
      status: 'sending',
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSender: replyToSender,
      mediaType: mediaType,
    );

    String wireContent = content;
    if (encryptionService != null) {
      try {
        final envelope = await encryptionService!.encryptMessage(
          recipientOfflineMeshId: recipientOfflineMeshId,
          messageId: messageId,
          plaintext: content,
        );
        wireContent = envelope.toJsonString();
      } catch (e) {
        debugPrint('E2EE message encryption failed: $e');
        rethrow;
      }
    }

    final wireMessage = Message(
      id: messageId,
      senderOfflineMeshId: wifiMessagingService.currentUser.offlineMeshId,
      recipientOfflineMeshId: recipientOfflineMeshId,
      content: wireContent,
      createdAt: localMessage.createdAt,
      status: 'sending',
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSender: replyToSender,
      mediaType: mediaType,
    );

    // Save initial sending state locally
    await localStorageService.saveMessage(recipientOfflineMeshId, localMessage);

    final routes = await getAvailableRoutes(recipientOfflineMeshId);

    for (final transport in routes) {
      try {
        wireMessage.transport = transport;
        localMessage.transport = transport;
        
        switch (transport) {
          case TransportType.WIFI_LAN:
            final peer = _activePeers.firstWhere((p) => p.offlineMeshId == recipientOfflineMeshId && p.isReachable);
            await wifiMessagingService.sendMessage(peer, wireMessage);
            break;
          case TransportType.INTERNET:
            final backendMsg = await messageService.sendMessage(recipientOfflineMeshId, wireContent);
            if (encryptionService != null) {
              await encryptionService!.cacheSentMessage(backendMsg.id, content);
            }
            final deliveredMsg = localMessage.copyWith(
              id: backendMsg.id,
              createdAt: backendMsg.createdAt,
              status: 'sent',
              transport: TransportType.INTERNET,
            );
            await localStorageService.removeMessage(recipientOfflineMeshId, localMessage.id);
            await localStorageService.saveMessage(recipientOfflineMeshId, deliveredMsg);
            return deliveredMsg;
        }
        
        localMessage.status = 'sent';
        await localStorageService.saveMessage(recipientOfflineMeshId, localMessage);
        return localMessage;
      } catch (e) {
        debugPrint('$transport message send failed, trying next route: $e');
      }
    }

    // Local Persistent Outbox Queue (Offline Fallback for auto-flush on reconnect)
    debugPrint('Queuing message $messageId in persistent offline outbox.');
    localMessage.status = 'queued';
    await localStorageService.addToOutbox(
      recipientOfflineMeshId: recipientOfflineMeshId,
      message: localMessage,
      wireContent: wireContent,
    );
    await localStorageService.saveMessage(recipientOfflineMeshId, localMessage);
    return localMessage;
  }

  /// Sends a WhatsApp-style emoji reaction to a target message
  Future<void> sendReaction({
    required String peerOfflineMeshId,
    required String messageId,
    required String emoji,
  }) async {
    final payload = jsonEncode({
      'type': 'REACTION',
      'targetMessageId': messageId,
      'emoji': emoji,
      'senderId': wifiMessagingService.currentUser.offlineMeshId,
    });

    final conversationPeer = peerOfflineMeshId;
    final msgs = await localStorageService.loadConversation(conversationPeer);
    final idx = msgs.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final myId = wifiMessagingService.currentUser.offlineMeshId;
      final currentReactions = Map<String, String>.from(msgs[idx].reactions ?? {});
      if (currentReactions[myId] == emoji) {
        currentReactions.remove(myId);
      } else {
        currentReactions[myId] = emoji;
      }
      final updated = msgs[idx].copyWith(reactions: currentReactions);
      await localStorageService.saveMessage(conversationPeer, updated);
      _incomingMessagesController.add(updated);
    }

    final routes = await getAvailableRoutes(peerOfflineMeshId);
    final reactionMsg = Message(
      id: 'reaction_${DateTime.now().millisecondsSinceEpoch}',
      senderOfflineMeshId: wifiMessagingService.currentUser.offlineMeshId,
      recipientOfflineMeshId: peerOfflineMeshId,
      content: payload,
      createdAt: DateTime.now(),
      status: 'sent',
    );

    for (final transport in routes) {
      try {
        if (transport == TransportType.WIFI_LAN) {
          final peer = _activePeers.firstWhere((p) => p.offlineMeshId == peerOfflineMeshId && p.isReachable);
          await wifiMessagingService.sendMessage(peer, reactionMsg);
          return;
        } else if (transport == TransportType.INTERNET) {
          await messageService.sendMessage(peerOfflineMeshId, payload);
          return;
        }
      } catch (e) {
        debugPrint('Failed to send reaction via $transport: $e');
      }
    }
  }

  bool _isFlushingOutbox = false;
  Future<void> flushOutbox() async {
    if (_isFlushingOutbox) return;
    _isFlushingOutbox = true;

    try {
      final queued = await localStorageService.loadOutbox();
      if (queued.isNotEmpty) {
        for (final item in queued) {
          final messageId = item['messageId'] as String;
          final recipientId = item['recipientOfflineMeshId'] as String;
          final rawMsg = item['message'] as Map<String, dynamic>;

          final int retryCount = item['retryCount'] is int ? item['retryCount'] as int : 0;
          final DateTime queuedAt = DateTime.tryParse(item['queuedAt']?.toString() ?? '') ?? DateTime.now();

          // If reached max retries (10) or queued longer than 7 days, transition to failed
          if (retryCount >= 10 || DateTime.now().difference(queuedAt).inDays >= 7) {
            debugPrint('Outbox message $messageId reached max retries ($retryCount) or expired; marking failed.');
            await localStorageService.removeFromOutbox(messageId);
            final failedMsg = Message.fromJson(rawMsg).copyWith(status: 'failed');
            await localStorageService.saveMessage(recipientId, failedMsg);
            _incomingMessagesController.add(failedMsg);
            continue;
          }

          final routes = await getAvailableRoutes(recipientId);
          if (routes.isEmpty) {
            continue;
          }

          String wireContent = rawMsg['content'] ?? '';
          if (encryptionService != null && !EncryptedEnvelope.isEncryptedEnvelope(wireContent)) {
            try {
              final envelope = await encryptionService!.encryptMessage(
                recipientOfflineMeshId: recipientId,
                messageId: messageId,
                plaintext: wireContent,
              );
              wireContent = envelope.toJsonString();
            } catch (e) {
              debugPrint('Failed to encrypt queued message for $recipientId: $e');
              await localStorageService.updateOutboxItem(
                messageId,
                retryCount: retryCount + 1,
                lastError: 'Encryption failed: $e',
              );
              continue;
            }
          }

          final wireMessage = Message(
            id: messageId,
            senderOfflineMeshId: wifiMessagingService.currentUser.offlineMeshId,
            content: wireContent,
            createdAt: DateTime.tryParse(rawMsg['createdAt'] ?? '') ?? DateTime.now(),
            status: 'sending',
          );

          bool sent = false;
          Message? serverMessage;
          for (final transport in routes) {
            try {
              wireMessage.transport = transport;
              switch (transport) {
                case TransportType.WIFI_LAN:
                  final peer = _activePeers.firstWhere((p) => p.offlineMeshId == recipientId && p.isReachable);
                  await wifiMessagingService.sendMessage(peer, wireMessage);
                  sent = true;
                  break;
                case TransportType.INTERNET:
                  serverMessage = await messageService.sendMessage(recipientId, wireContent);
                  sent = true;
                  break;
              }
              if (sent) {
                await localStorageService.removeFromOutbox(messageId);
                final updated = Message.fromJson(rawMsg).copyWith(
                  id: serverMessage?.id,
                  createdAt: serverMessage?.createdAt,
                  status: 'sent',
                  transport: transport,
                );
                if (serverMessage != null) {
                  await encryptionService?.cacheSentMessage(serverMessage.id, updated.content);
                  await localStorageService.removeMessage(recipientId, messageId);
                }
                await localStorageService.saveMessage(recipientId, updated);
                _incomingMessagesController.add(updated);
                debugPrint('Successfully flushed queued message $messageId via $transport');
                break;
              }
            } catch (e) {
              debugPrint('Failed to flush message $messageId via $transport: $e');
            }
          }

          if (!sent) {
            await localStorageService.updateOutboxItem(
              messageId,
              retryCount: retryCount + 1,
              lastError: 'All available routes failed to send',
            );
          }
        }
      }

      // Flush store-and-forward relay buffer for reachable mesh peers
      await _flushRelayBuffer();
    } catch (e) {
      debugPrint('Error during outbox flush: $e');
    } finally {
      _isFlushingOutbox = false;
    }
  }

  /// Store-and-forward handler when a mesh packet arrives destined for another peer
  Future<void> handleRelayedPacket(Map<String, dynamic> payload) async {
    try {
      final packetId = payload['message']?['id']?.toString() ??
          payload['packetId']?.toString() ??
          payload['id']?.toString() ??
          '';

      if (packetId.isNotEmpty) {
        if (await localStorageService.hasMessageBeenProcessed(packetId)) {
          debugPrint('Dropping already processed/relayed mesh packet: $packetId');
          return;
        }
        await localStorageService.markMessageProcessed(packetId);
      }

      final recipientId = payload['recipientOfflineMeshId']?.toString() ?? '';
      if (recipientId.isEmpty) return;

      final hopCount = (payload['hopCount'] as int? ?? 1);
      final maxHops = (payload['maxHops'] as int? ?? 3);

      if (hopCount >= maxHops) {
        debugPrint('Dropping mesh packet $packetId: max hop count ($maxHops) reached.');
        return;
      }

      payload['hopCount'] = hopCount + 1;

      // Check if recipient is directly reachable on local Wi-Fi LAN
      final peer = _activePeers.where((p) => p.offlineMeshId == recipientId && p.isReachable).firstOrNull;
      if (peer != null) {
        debugPrint('Next-hop peer available for $recipientId; forwarding mesh packet $packetId over Wi-Fi.');
        await wifiMessagingService.sendRelayPacket(peer, payload);
      } else {
        debugPrint('Recipient $recipientId not yet reachable; storing mesh packet $packetId in relay buffer.');
        await localStorageService.addToRelayBuffer(payload);
      }
    } catch (e) {
      debugPrint('Error handling relayed mesh packet: $e');
    }
  }

  Future<void> _flushRelayBuffer() async {
    try {
      await localStorageService.pruneExpiredRelayPackets(maxAge: const Duration(hours: 24));
      final relayItems = await localStorageService.loadRelayBuffer();
      if (relayItems.isEmpty) return;

      for (final item in relayItems) {
        final recipientId = item['recipientOfflineMeshId']?.toString() ?? '';
        final packetId = item['packetId']?.toString() ?? '';
        final packet = Map<String, dynamic>.from(item['packet'] as Map? ?? {});

        if (recipientId.isNotEmpty) {
          final peer = _activePeers.where((p) => p.offlineMeshId == recipientId && p.isReachable).firstOrNull;
          if (peer != null) {
            try {
              debugPrint('Flushing buffered relay packet $packetId to $recipientId');
              await wifiMessagingService.sendRelayPacket(peer, packet);
              await localStorageService.removeFromRelayBuffer(packetId);
            } catch (e) {
              debugPrint('Failed to forward buffered relay packet to $recipientId: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error flushing relay buffer: $e');
    }
  }

  // File Transfer Routing
  
  Future<FileMetadata> sendFile(
      String recipientOfflineMeshId, 
      String fileName, 
      String contentType, 
      int fileSize, 
      File file, 
      Function(double) onProgress) async {
    
    File fileToSend = file;
    File? tempEncryptedFile;
    bool isEncrypted = false;
    String? encryptedKeyEnvelope;

    if (encryptionService != null) {
      try {
        final encResult = await encryptionService!.encryptFile(
          file,
          recipientOfflineMeshId,
        );
        tempEncryptedFile = encResult.encryptedFile;
        fileToSend = tempEncryptedFile;
        isEncrypted = true;
        encryptedKeyEnvelope = encResult.encryptedKeyEnvelope;
      } catch (e) {
        debugPrint('E2EE file encryption unavailable for $recipientOfflineMeshId ($e). Sending unencrypted.');
        isEncrypted = false;
        fileToSend = file;
      }
    }

    try {
      final encFileSize = await fileToSend.length();
      final fileBytes = await fileToSend.readAsBytes();
      final checksum = sha256.convert(fileBytes).toString();
      
      final localMetadata = FileMetadata(
        id: const Uuid().v4(), // generate local unique ID
        senderOfflineMeshId: wifiMessagingService.currentUser.offlineMeshId,
        recipientOfflineMeshId: recipientOfflineMeshId,
        originalFileName: fileName,
        contentType: contentType,
        fileSize: encFileSize,
        checksum: checksum,
        status: 'COMPLETED',
        createdAt: DateTime.now(),
        localFilePath: file.path,
        isEncrypted: isEncrypted,
        encryptedKeyEnvelope: encryptedKeyEnvelope,
      );

      // 1. WIFI_LAN local direct transfer
      DiscoveredPeer? targetPeer;
      try {
        targetPeer = _activePeers.firstWhere(
          (p) => p.offlineMeshId == recipientOfflineMeshId && p.isReachable,
        );
      } catch (e) {
        targetPeer = null;
      }

      if (targetPeer != null) {
        try {
          await wifiFileTransferService.sendFile(targetPeer, localMetadata, fileToSend, onProgress);
          localMetadata.transport = 'WIFI_LAN';
          _localSentFiles.removeWhere((f) => f.id == localMetadata.id);
          _localSentFiles.add(localMetadata);
          await localStorageService.saveSentFile(localMetadata);
          return localMetadata;
        } catch (e) {
          debugPrint('WIFI_LAN file send failed, trying next route: $e');
        }
      }

      // 2. Fallback INTERNET transfer
      final backendMetadata = await fileService.createMetadata(
        recipientOfflineMeshId: recipientOfflineMeshId,
        originalFileName: fileName,
        contentType: contentType,
        fileSize: encFileSize,
        checksum: checksum,
        isEncrypted: isEncrypted,
        encryptedKeyEnvelope: encryptedKeyEnvelope,
      );
      
      await fileService.uploadFile(backendMetadata, fileToSend, onProgress);
      backendMetadata.transport = 'INTERNET';
      backendMetadata.localFilePath = file.path;
      _localSentFiles.removeWhere((f) => f.id == backendMetadata.id);
      _localSentFiles.add(backendMetadata);
      await localStorageService.saveSentFile(backendMetadata);
      return backendMetadata;
    } finally {
      if (tempEncryptedFile != null && await tempEncryptedFile.exists()) {
        try {
          await tempEncryptedFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Sends a rich media message (image, video, voice note, or document)
  /// using end-to-end encryption, LAN direct peer transfer, or Internet fallback.
  Future<Message> sendMediaMessage({
    required String recipientOfflineMeshId,
    required File file,
    required String mediaType, // 'image', 'video', 'audio', 'file'
    String? customFileName,
    int? durationMs,
    Function(double)? onProgress,
  }) async {
    final fileName = customFileName ?? p.basename(file.path);
    final ext = fileName.split('.').last.toLowerCase();
    String contentType = '*/*';
    if (mediaType == 'image') {
      contentType = 'image/$ext';
    } else if (mediaType == 'video') {
      contentType = 'video/$ext';
    } else if (mediaType == 'audio') {
      contentType = 'audio/$ext';
    }

    final fileSize = await file.length();
    final fileBytes = await file.readAsBytes();
    final fileHash = sha256.convert(fileBytes).toString();

    // 1. Send file via existing multi-transport router (LAN direct -> Internet fallback)
    final fileMeta = await sendFile(
      recipientOfflineMeshId,
      fileName,
      contentType,
      fileSize,
      file,
      onProgress ?? (_) {},
    );

    // 2. Create local Message representation
    final myId = wifiMessagingService.currentUser.offlineMeshId;
    final message = Message(
      id: fileMeta.id,
      senderOfflineMeshId: myId,
      recipientOfflineMeshId: recipientOfflineMeshId,
      content: fileName,
      createdAt: DateTime.now(),
      status: 'sent',
      transport: fileMeta.transport == 'WIFI_LAN' ? TransportType.WIFI_LAN : TransportType.INTERNET,
      mediaType: mediaType,
      mediaPath: file.path,
      fileName: fileName,
      fileSize: fileSize,
      durationMs: durationMs,
      fileHash: fileHash,
    );

    // 3. Save to local storage for this conversation
    await localStorageService.saveMessage(recipientOfflineMeshId, message);

    return message;
  }
  
  Future<List<FileMetadata>> getCombinedSentFiles() async {
    List<FileMetadata> apiFiles = [];
    try {
      apiFiles = await fileService.getSentFiles();
    } catch (e) {
      debugPrint('Failed to get backend sent files: $e');
    }
    
    final Map<String, FileMetadata> fileMap = {};
    for (final f in _localSentFiles) {
      fileMap[f.id] = f;
    }
    for (final f in apiFiles) {
      if (fileMap.containsKey(f.id) && fileMap[f.id]?.localFilePath != null) {
        f.localFilePath = fileMap[f.id]!.localFilePath;
      }
      fileMap[f.id] = f;
    }
    
    final allFiles = fileMap.values.toList();
    allFiles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return allFiles;
  }
  
  Future<List<FileMetadata>> getCombinedReceivedFiles() async {
    List<FileMetadata> apiFiles = [];
    try {
      apiFiles = await fileService.getReceivedFiles();
    } catch (e) {
      debugPrint('Failed to get backend received files: $e');
    }
    
    final Map<String, FileMetadata> fileMap = {};
    for (final f in _localReceivedFiles) {
      fileMap[f.id] = f;
    }
    for (final f in apiFiles) {
      if (fileMap.containsKey(f.id) && fileMap[f.id]?.localFilePath != null) {
        f.localFilePath = fileMap[f.id]!.localFilePath;
      }
      fileMap[f.id] = f;
    }
    
    final allFiles = fileMap.values.toList();
    allFiles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return allFiles;
  }

  /// Sends a read receipt for all unread messages received from this peer
  Future<void> sendReadReceipt(String peerOfflineMeshId) async {
    final myId = wifiMessagingService.currentUser.offlineMeshId;
    await localStorageService.markConversationAsRead(peerOfflineMeshId, myId);

    final routes = await getAvailableRoutes(peerOfflineMeshId);
    final payload = jsonEncode({
      'type': 'READ_RECEIPT',
      'readerId': myId,
    });
    final receiptMsg = Message(
      id: 'receipt_${DateTime.now().millisecondsSinceEpoch}',
      senderOfflineMeshId: myId,
      recipientOfflineMeshId: peerOfflineMeshId,
      content: payload,
      createdAt: DateTime.now(),
      status: 'sent',
    );

    for (final transport in routes) {
      try {
        if (transport == TransportType.WIFI_LAN) {
          final peer = _activePeers.firstWhere((p) => p.offlineMeshId == peerOfflineMeshId && p.isReachable);
          await wifiMessagingService.sendMessage(peer, receiptMsg);
          return;
        } else if (transport == TransportType.INTERNET) {
          await messageService.markMessagesAsRead(peerOfflineMeshId);
          return;
        }
      } catch (e) {
        debugPrint('Failed to send read receipt via $transport: $e');
      }
    }
  }

  /// Edits an existing sent message and propagates the change to recipient
  Future<void> editMessage({
    required String peerOfflineMeshId,
    required String messageId,
    required String newContent,
  }) async {
    await localStorageService.updateMessageContent(
      peerOfflineMeshId,
      messageId,
      newContent,
      isEdited: true,
    );

    final msgs = await localStorageService.loadConversation(peerOfflineMeshId);
    final idx = msgs.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      _incomingMessagesController.add(msgs[idx]);
    }

    final routes = await getAvailableRoutes(peerOfflineMeshId);
    for (final transport in routes) {
      try {
        if (transport == TransportType.WIFI_LAN) {
          final peer = _activePeers.firstWhere((p) => p.offlineMeshId == peerOfflineMeshId && p.isReachable);
          final payload = jsonEncode({
            'type': 'EDIT_MESSAGE',
            'messageId': messageId,
            'newContent': newContent,
          });
          final editMsg = Message(
            id: 'edit_${DateTime.now().millisecondsSinceEpoch}',
            senderOfflineMeshId: wifiMessagingService.currentUser.offlineMeshId,
            recipientOfflineMeshId: peerOfflineMeshId,
            content: payload,
            createdAt: DateTime.now(),
            status: 'sent',
          );
          await wifiMessagingService.sendMessage(peer, editMsg);
          return;
        } else if (transport == TransportType.INTERNET) {
          await messageService.editMessage(messageId, newContent);
          return;
        }
      } catch (e) {
        debugPrint('Failed to send edit via $transport: $e');
      }
    }
  }

  /// Deletes a message for everyone (replaces content with deletion marker)
  Future<void> deleteMessageForEveryone({
    required String peerOfflineMeshId,
    required String messageId,
  }) async {
    const deletedText = '🚫 This message was deleted';
    await localStorageService.updateMessageContent(
      peerOfflineMeshId,
      messageId,
      deletedText,
      isDeleted: true,
    );

    final msgs = await localStorageService.loadConversation(peerOfflineMeshId);
    final idx = msgs.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      _incomingMessagesController.add(msgs[idx]);
    }

    final routes = await getAvailableRoutes(peerOfflineMeshId);
    for (final transport in routes) {
      try {
        if (transport == TransportType.WIFI_LAN) {
          final peer = _activePeers.firstWhere((p) => p.offlineMeshId == peerOfflineMeshId && p.isReachable);
          final payload = jsonEncode({
            'type': 'DELETE_MESSAGE',
            'messageId': messageId,
          });
          final delMsg = Message(
            id: 'delete_${DateTime.now().millisecondsSinceEpoch}',
            senderOfflineMeshId: wifiMessagingService.currentUser.offlineMeshId,
            recipientOfflineMeshId: peerOfflineMeshId,
            content: payload,
            createdAt: DateTime.now(),
            status: 'sent',
          );
          await wifiMessagingService.sendMessage(peer, delMsg);
          return;
        } else if (transport == TransportType.INTERNET) {
          await messageService.deleteMessageForEveryone(messageId);
          return;
        }
      } catch (e) {
        debugPrint('Failed to send delete-for-everyone via $transport: $e');
      }
    }
  }

  void dispose() {
    _outboxRetryTimer?.cancel();
    _peersSubscription?.cancel();
    _wifiMessagesSubscription?.cancel();
    _relayedPacketsSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _internetMessagesSubscription?.cancel();
    _statusUpdatesSubscription?.cancel();
    _wifiFilesSubscription?.cancel();
    _incomingMessagesController.close();
    _incomingFilesController.close();
  }
}
