import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/user.dart';
import '../../features/files/models/file_metadata.dart';
import 'bluetooth_messaging_service.dart';

class BluetoothFileTransferService {
  static const MethodChannel _channel = MethodChannel('com.offlinemesh/bluetooth_file');
  static const EventChannel _eventChannel = EventChannel('com.offlinemesh/bluetooth_file/events');

  final UserProfile currentUser;
  final BluetoothMessagingService bluetoothMessagingService;

  final _incomingFilesController = StreamController<FileMetadata>.broadcast();
  Stream<FileMetadata> get incomingFiles => _incomingFilesController.stream;

  StreamSubscription? _eventSubscription;

  // Track progress optionally if needed:
  // _progressController = StreamController<Map<String, dynamic>>.broadcast();

  BluetoothFileTransferService({
    required this.currentUser,
    required this.bluetoothMessagingService,
  });

  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('startServer');
      
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen((event) {
        if (event is Map) {
          _handleNativeEvent(Map<String, dynamic>.from(event));
        }
      });
      debugPrint('Bluetooth File Transfer Server started.');
    } catch (e) {
      debugPrint('Error initializing BluetoothFileTransferService: $e');
    }
  }

  void shutdown() {
    _channel.invokeMethod('stopServer');
    _eventSubscription?.cancel();
  }

  Future<void> _handleNativeEvent(Map<String, dynamic> event) async {
    final type = event['type'];
    final address = event['address'] as String;

    switch (type) {
      case 'incoming_file':
        await _processIncomingFile(
          address: address,
          metadataJson: event['metadata'] as String,
          tempFilePath: event['tempFilePath'] as String,
          calculatedHash: event['calculatedHash'] as String?,
        );
        break;
      case 'progress':
        // final progress = event['progress'] as double;
        // debugPrint('Bluetooth file transfer to/from $address is ${(progress * 100).toInt()}%');
        break;
      case 'sent':
        debugPrint('Bluetooth file successfully sent to $address');
        break;
      case 'error':
        debugPrint('Bluetooth file transfer error on $address: ${event['error']}');
        break;
    }
  }

  Future<void> _processIncomingFile({
    required String address,
    required String metadataJson,
    required String tempFilePath,
    required String? calculatedHash,
  }) async {
    final tempFile = File(tempFilePath);
    try {
      final payload = jsonDecode(metadataJson) as Map<String, dynamic>;
      
      if (payload['protocolVersion'] != 1 || payload['metadata'] == null) {
        debugPrint('Invalid protocol or missing metadata. Deleting temp file.');
        if (await tempFile.exists()) await tempFile.delete();
        return;
      }
      
      final parsedMetadata = FileMetadata.fromJson(payload['metadata']);
      
      if (parsedMetadata.recipientOfflineMeshId != currentUser.offlineMeshId) {
        debugPrint('File not intended for this user. Dropping.');
        if (await tempFile.exists()) await tempFile.delete();
        return;
      }

      // Verify the sender matches the Bluetooth handshaked address!
      final expectedSenderId = bluetoothMessagingService.getOfflineMeshIdForAddress(address);
      if (expectedSenderId == null || expectedSenderId != parsedMetadata.senderOfflineMeshId) {
        debugPrint('Sender identity mismatch or not handshaked! Dropping file.');
        if (await tempFile.exists()) await tempFile.delete();
        return;
      }

      if (parsedMetadata.checksum != null && parsedMetadata.checksum != calculatedHash) {
        debugPrint('Checksum mismatch! Deleting corrupted file.');
        if (await tempFile.exists()) await tempFile.delete();
        return;
      }

      // Rename temp file to actual file
      final directory = await getApplicationDocumentsDirectory();
      final safeName = parsedMetadata.originalFileName.replaceAll(RegExp(r'[^a-zA-Z0-9.\-_]'), '_');
      final finalPath = p.join(directory.path, safeName);
      
      await tempFile.rename(finalPath);
      parsedMetadata.localFilePath = finalPath;
      
      // Update status
      final completedMetadata = FileMetadata(
        id: parsedMetadata.id,
        senderOfflineMeshId: parsedMetadata.senderOfflineMeshId,
        recipientOfflineMeshId: parsedMetadata.recipientOfflineMeshId,
        originalFileName: parsedMetadata.originalFileName,
        contentType: parsedMetadata.contentType,
        fileSize: parsedMetadata.fileSize,
        checksum: parsedMetadata.checksum,
        status: 'COMPLETED',
        createdAt: parsedMetadata.createdAt,
        updatedAt: DateTime.now(),
        localFilePath: finalPath,
        isEncrypted: parsedMetadata.isEncrypted,
        encryptedKeyEnvelope: parsedMetadata.encryptedKeyEnvelope,
      );
      
      _incomingFilesController.add(completedMetadata);
    } catch (e) {
      debugPrint('Error processing incoming Bluetooth file: $e');
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  Future<void> sendFile(String recipientOfflineMeshId, FileMetadata metadata, File file, Function(double) onProgress) async {
    // We need the Bluetooth address for the recipient
    final targetAddress = bluetoothMessagingService.getAddressForOfflineMeshId(recipientOfflineMeshId);
    
    if (targetAddress == null) {
      throw Exception('Bluetooth peer $recipientOfflineMeshId not connected or handshaked.');
    }
    
    final payload = {
      'protocolVersion': 1,
      'metadata': metadata.toJson(),
    };
    final jsonStr = jsonEncode(payload);
    
    await _channel.invokeMethod('sendFile', {
      'address': targetAddress,
      'metadata': jsonStr,
      'filePath': file.absolute.path,
    });
  }
}
