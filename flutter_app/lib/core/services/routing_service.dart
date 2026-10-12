import 'dart:async';
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

  final _incomingMessagesController = StreamController<Message>.broadcast();
  Stream<Message> get incomingMessages => _incomingMessagesController.stream;

  final _incomingFilesController = StreamController<FileMetadata>.broadcast();
  Stream<FileMetadata> get incomingFiles => _incomingFilesController.stream;

  List<DiscoveredPeer> _activePeers = [];
  List<BleDiscoveredDevice> _activeBlePeers = [];
  
  StreamSubscription? _peersSubscription;
  StreamSubscription? _blePeersSubscription;
  StreamSubscription? _wifiMessagesSubscription;
  StreamSubscription? _bluetoothMessagesSubscription;
  StreamSubscription? _bleMessagesSubscription;
  StreamSubscription? _wifiFilesSubscription;

  StreamSubscription? _bluetoothFilesSubscription;

  final List<FileMetadata> _localSentFiles = [];
  final List<FileMetadata> _localReceivedFiles = [];

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
  });

  void initialize() {
    _peersSubscription = discoveryService.peersStream.listen((peers) {
      _activePeers = peers;
    });

    _blePeersSubscription = bleDiscoveryService?.devicesStream.listen((peers) {
      _activeBlePeers = peers;
      for (var peer in peers) {
        bleMessagingService?.connectAndHandshake(peer);
      }
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

    _wifiFilesSubscription = wifiFileTransferService.incomingFiles.listen((fileMeta) {
      _deliverIncomingFile(fileMeta, 'WIFI_LAN');
    });
    
    _bluetoothFilesSubscription = bluetoothFileTransferService.incomingFiles.listen((fileMeta) {
      _deliverIncomingFile(fileMeta, 'BLUETOOTH');
    });
  }

  Future<void> _deliverIncomingMessage(Message message, TransportType transport) async {
    message.transport = transport;

    if (EncryptedEnvelope.isEncryptedEnvelope(message.content)) {
      if (encryptionService != null) {
        try {
          final decryptedContent = await encryptionService!.decryptMessage(message.content);
          message = message.copyWith(content: decryptedContent);
        } catch (e) {
          debugPrint('Decryption failed for incoming message: $e');
          message = message.copyWith(content: 'Unable to decrypt message.');
        }
      } else {
        message = message.copyWith(content: 'Unable to decrypt message.');
      }
    }

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
          final keyEnvelope = EncryptedEnvelope.fromJsonString(fileMeta.encryptedKeyEnvelope!);

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

    _localReceivedFiles.add(fileMeta);
    _incomingFilesController.add(fileMeta);
  }

  void shutdown() {
    _peersSubscription?.cancel();
    _blePeersSubscription?.cancel();
    _wifiMessagesSubscription?.cancel();
    _bluetoothMessagesSubscription?.cancel();
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
      return false;
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

    // 4. INTERNET
    routes.add(TransportType.INTERNET);
    
    return routes;
  }

  Future<Message> sendMessage(String recipientOfflineMeshId, String content) async {
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();

    final localMessage = Message(
      id: messageId,
      senderOfflineMeshId: wifiMessagingService.currentUser.offlineMeshId,
      content: content,
      createdAt: DateTime.now(),
      status: 'sending',
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
      content: wireContent,
      createdAt: localMessage.createdAt,
      status: 'sending',
    );

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
            return localMessage.copyWith(
              id: backendMsg.id,
              createdAt: backendMsg.createdAt,
              status: 'sent',
              transport: TransportType.INTERNET,
            );
        }
        
        localMessage.status = 'sent';
        return localMessage;
      } catch (e) {
        debugPrint('$transport message send failed, trying next route: $e');
      }
    }

    // 5. BLE Store-And-Forward Queueing (Offline Fallback)
    if (bleMessagingService != null) {
      debugPrint('No active transports available. Queueing for offline store-and-forward.');
      wireMessage.transport = TransportType.BLE;
      localMessage.transport = TransportType.BLE;
      localMessage.status = 'queued'; // UI can optionally display this
      try {
        await bleMessagingService!.sendMessage(recipientOfflineMeshId, wireMessage);
        return localMessage;
      } catch (e) {
        debugPrint('Failed to queue offline message: $e');
      }
    }

    localMessage.status = 'failed';
    throw Exception('All transports and offline queueing failed to send message');
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
        debugPrint('E2EE file encryption failed: $e');
        rethrow;
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
          _localSentFiles.add(localMetadata);
          return localMetadata;
        } catch (e) {
          debugPrint('WIFI_LAN file send failed, trying next route: $e');
        }
      }

      // 2. BLUETOOTH transfer
      try {
        await bluetoothFileTransferService.sendFile(recipientOfflineMeshId, localMetadata, fileToSend, onProgress);
        localMetadata.transport = 'BLUETOOTH';
        _localSentFiles.add(localMetadata);
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
    
    final allFiles = [...apiFiles, ..._localSentFiles];
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
    
    final allFiles = [...apiFiles, ..._localReceivedFiles];
    allFiles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return allFiles;
  }
}
