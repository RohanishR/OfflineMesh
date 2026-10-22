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
import 'bluetooth_messaging_service.dart';
import 'bluetooth_file_transfer_service.dart';
import 'ble_discovery_service.dart';
import 'ble_messaging_service.dart';
import 'local_storage_service.dart';
import '../models/discovered_peer.dart';
import '../models/ble_discovered_device.dart';
import '../../features/files/models/file_metadata.dart';
import '../../features/files/services/file_service.dart';

class RoutingService {
  final MessageService messageService;
  final FileService fileService;
  final WifiMessagingService wifiMessagingService;
  final WifiPeerDiscoveryService discoveryService;
  final WifiFileTransferService wifiFileTransferService;
  final BluetoothMessagingService bluetoothMessagingService;
  final BluetoothFileTransferService bluetoothFileTransferService;
  final BleDiscoveryService? bleDiscoveryService;
  final BleMessagingService? bleMessagingService;
  final E2eEncryptionService? encryptionService;
  final LocalStorageService localStorageService;

  final _incomingMessagesController = StreamController<Message>.broadcast();
  Stream<Message> get incomingMessages => _incomingMessagesController.stream;

  final _incomingFilesController = StreamController<FileMetadata>.broadcast();
  Stream<FileMetadata> get incomingFiles => _incomingFilesController.stream;

  List<DiscoveredPeer> _activePeers = [];
  List<BleDiscoveredDevice> _activeBlePeers = [];
  List<BleDiscoveredDevice> get activeBlePeers => List.unmodifiable(_activeBlePeers);
  
  StreamSubscription? _peersSubscription;
  StreamSubscription? _blePeersSubscription;
  StreamSubscription? _wifiMessagesSubscription;
  StreamSubscription? _bluetoothMessagesSubscription;
  StreamSubscription? _bleMessagesSubscription;
  StreamSubscription? _internetMessagesSubscription;
  StreamSubscription? _wifiFilesSubscription;

  StreamSubscription? _bluetoothFilesSubscription;

  final List<FileMetadata> _localSentFiles = [];
  final List<FileMetadata> _localReceivedFiles = [];
  final Set<String> _recentlyDeliveredMessageIds = {};

  RoutingService({
    required this.messageService,
    required this.fileService,
    required this.wifiMessagingService,
    required this.discoveryService,
    required this.wifiFileTransferService,
    required this.bluetoothMessagingService,
    required this.bluetoothFileTransferService,
    this.bleDiscoveryService,
    this.bleMessagingService,
    this.encryptionService,
    LocalStorageService? localStorageService,
  }) : localStorageService = localStorageService ?? LocalStorageService();

  void initialize() {
    _loadPersistedFiles();

    _peersSubscription = discoveryService.peersStream.listen((peers) {
      _activePeers = peers;
      flushOutbox();
    });

    _blePeersSubscription = bleDiscoveryService?.devicesStream.listen((peers) {
      _activeBlePeers = peers;
      for (var peer in peers) {
        bleMessagingService?.connectAndHandshake(peer);
      }
      flushOutbox();
    });

    _wifiMessagesSubscription = wifiMessagingService.incomingMessages.listen((message) {
      _deliverIncomingMessage(message, TransportType.WIFI_LAN);
    });
    
    _bluetoothMessagesSubscription = bluetoothMessagingService.incomingMessages.listen((message) {
      _deliverIncomingMessage(message, TransportType.BLUETOOTH);
    });

    _bleMessagesSubscription = bleMessagingService?.incomingMessages.listen((message) {
      _deliverIncomingMessage(message, TransportType.BLE);
    });

    _internetMessagesSubscription = messageService.incomingMessages.listen((message) {
      _deliverIncomingMessage(message, TransportType.INTERNET);
    });

    _wifiFilesSubscription = wifiFileTransferService.incomingFiles.listen((fileMeta) {
      _deliverIncomingFile(fileMeta, 'WIFI_LAN');
    });
    
    _bluetoothFilesSubscription = bluetoothFileTransferService.incomingFiles.listen((fileMeta) {
      _deliverIncomingFile(fileMeta, 'BLUETOOTH');
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

    // 2. Deduplicate incoming messages across transports
    if (_recentlyDeliveredMessageIds.contains(message.id)) {
      debugPrint('Dropping already delivered duplicate message: ${message.id}');
      return;
    }
    _recentlyDeliveredMessageIds.add(message.id);
    if (_recentlyDeliveredMessageIds.length > 500) {
      _recentlyDeliveredMessageIds.remove(_recentlyDeliveredMessageIds.first);
    }

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

    // 5. Intercept WhatsApp emoji reactions
    try {
      final trimmed = message.content.trim();
      if (trimmed.startsWith('{"type":"REACTION"') || trimmed.startsWith('{"type": "REACTION"')) {
        final data = jsonDecode(trimmed) as Map<String, dynamic>;
        if (data['type'] == 'REACTION') {
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
              return; // Handled as reaction update; do not create duplicate text bubble
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Reaction parsing note: $e');
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
  }

  void shutdown() {
    _peersSubscription?.cancel();
    _blePeersSubscription?.cancel();
    _wifiMessagesSubscription?.cancel();
    _bluetoothMessagesSubscription?.cancel();
    _bleMessagesSubscription?.cancel();
    _internetMessagesSubscription?.cancel();
    _wifiFilesSubscription?.cancel();
    _bluetoothFilesSubscription?.cancel();
    _incomingMessagesController.close();
    _incomingFilesController.close();
  }

  bool isPeerNearby(String offlineMeshId) {
    try {
      final peer = _activePeers.firstWhere((p) => p.offlineMeshId == offlineMeshId);
      return peer.isReachable;
    } catch (e) {
      return wifiMessagingService.getKnownIpForPeer(offlineMeshId) != null;
    }
  }

  DiscoveredPeer? getNearbyPeer(String offlineMeshId) {
    try {
      return _activePeers.firstWhere((p) => p.offlineMeshId == offlineMeshId && p.isReachable);
    } catch (e) {
      final cachedIp = wifiMessagingService.getKnownIpForPeer(offlineMeshId);
      if (cachedIp != null) {
        final now = DateTime.now();
        return DiscoveredPeer(
          offlineMeshId: offlineMeshId,
          displayName: offlineMeshId,
          deviceId: offlineMeshId,
          ipAddress: cachedIp,
          port: 45455,
          discoveryTimestamp: now,
          lastSeenTimestamp: now,
          isReachable: true,
        );
      }
      return null;
    }
  }

  Future<List<TransportType>> getAvailableRoutes(String destId) async {
    final routes = <TransportType>[];

    // 1. WIFI_LAN
    if (isPeerNearby(destId)) {
      routes.add(TransportType.WIFI_LAN);
    }

    // 2. BLUETOOTH
    final btAddress = bluetoothMessagingService.getAddressForOfflineMeshId(destId);
    if (btAddress != null) {
      routes.add(TransportType.BLUETOOTH);
    }

    // 3. BLE (Direct or Mesh)
    if (bleMessagingService != null) {
      final bleAddress = bleMessagingService!.getAddressForOfflineMeshId(destId);
      if (bleAddress != null) {
        routes.add(TransportType.BLE); // Direct
      } else {
        final hasMesh = await bleMessagingService!.hasMeshRoute(destId);
        if (hasMesh) {
          routes.add(TransportType.BLE); // Mesh
        }
      }
    }

    // 4. INTERNET (Only route if authenticated with valid token)
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
          case TransportType.BLUETOOTH:
            await bluetoothMessagingService.sendMessage(recipientOfflineMeshId, wireMessage);
            break;
          case TransportType.BLE:
            await bleMessagingService!.sendMessage(recipientOfflineMeshId, wireMessage);
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

    // 5. BLE Store-And-Forward Queueing (Offline Fallback)
    if (bleMessagingService != null) {
      debugPrint('No active transports available. Attempting BLE store-and-forward.');
      wireMessage.transport = TransportType.BLE;
      localMessage.transport = TransportType.BLE;
      localMessage.status = 'queued';
      try {
        await bleMessagingService!.sendMessage(recipientOfflineMeshId, wireMessage);
        await localStorageService.saveMessage(recipientOfflineMeshId, localMessage);
        return localMessage;
      } catch (e) {
        debugPrint('BLE store-and-forward queue failed: $e');
      }
    }

    // 6. Local Persistent Outbox Queue (Offline Fallback for auto-flush on reconnect)
    debugPrint('Queuing message $messageId in persistent offline outbox.');
    localMessage.status = 'queued';
    await localStorageService.saveMessage(recipientOfflineMeshId, localMessage);
    await localStorageService.addToOutbox(
      recipientOfflineMeshId: recipientOfflineMeshId,
      message: localMessage,
      wireContent: wireContent,
    );
    return localMessage;
  }

  Future<void> sendReaction({
    required String peerOfflineMeshId,
    required String messageId,
    required String emoji,
  }) async {
    final myId = wifiMessagingService.currentUser.offlineMeshId;
    final messages = await localStorageService.loadConversation(peerOfflineMeshId);
    final targetIndex = messages.indexWhere((m) => m.id == messageId);
    if (targetIndex != -1) {
      final msg = messages[targetIndex];
      final currentReactions = Map<String, String>.from(msg.reactions ?? {});
      if (currentReactions[myId] == emoji) {
        currentReactions.remove(myId);
      } else {
        currentReactions[myId] = emoji;
      }
      final updated = msg.copyWith(reactions: currentReactions);
      await localStorageService.saveMessage(peerOfflineMeshId, updated);
      _incomingMessagesController.add(updated);

      // Transmit reaction signal across mesh
      try {
        final reactionJson = jsonEncode({
          'type': 'REACTION',
          'targetMessageId': messageId,
          'emoji': emoji,
          'senderId': myId,
        });
        await sendMessage(peerOfflineMeshId, reactionJson);
      } catch (e) {
        debugPrint('Could not transmit reaction over wire: $e');
      }
    }
  }

  bool _isFlushingOutbox = false;
  Future<void> flushOutbox() async {
    if (_isFlushingOutbox) return;
    _isFlushingOutbox = true;
    try {
      final queuedItems = await localStorageService.loadOutbox();
      for (final item in queuedItems) {
        final recipientId = item['recipientOfflineMeshId'] as String?;
        final messageId = item['messageId'] as String?;
        final wireContent = item['wireContent'] as String?;
        final rawMsg = item['message'] as Map<String, dynamic>?;
        if (recipientId == null || messageId == null || wireContent == null || rawMsg == null) continue;

        final routes = await getAvailableRoutes(recipientId);
        if (routes.isEmpty) continue;

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
              case TransportType.BLUETOOTH:
                await bluetoothMessagingService.sendMessage(recipientId, wireMessage);
                sent = true;
                break;
              case TransportType.BLE:
                await bleMessagingService!.sendMessage(recipientId, wireMessage);
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
                id: serverMessage?.id, createdAt: serverMessage?.createdAt,
                status: 'sent', transport: transport);
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
      }
    } catch (e) {
      debugPrint('Error during outbox flush: $e');
    } finally {
      _isFlushingOutbox = false;
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

      // 2. BLUETOOTH transfer
      try {
        await bluetoothFileTransferService.sendFile(recipientOfflineMeshId, localMetadata, fileToSend, onProgress);
        localMetadata.transport = 'BLUETOOTH';
        _localSentFiles.removeWhere((f) => f.id == localMetadata.id);
        _localSentFiles.add(localMetadata);
        await localStorageService.saveSentFile(localMetadata);
        return localMetadata;
      } catch (e) {
        debugPrint('BLUETOOTH file send failed or unavailable: $e');
      }

      // 3. Fallback INTERNET transfer
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
}
