import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/message.dart';
import '../models/user.dart';
import '../transport/transport_type.dart';
import '../models/bluetooth_discovered_device.dart';
import '../security/e2e_encryption_service.dart';

class BluetoothMessagingService {
  static const MethodChannel _channel = MethodChannel('com.offlinemesh/bluetooth');
  static const EventChannel _eventChannel = EventChannel('com.offlinemesh/bluetooth/events');

  final UserProfile currentUser;
  E2eEncryptionService? encryptionService;
  
  // Mappings: Bluetooth MAC Address -> OfflineMesh ID
  final Map<String, String> _addressToOfflineMeshId = {};
  
  final _incomingMessagesController = StreamController<Message>.broadcast();
  Stream<Message> get incomingMessages => _incomingMessagesController.stream;

  StreamSubscription? _eventSubscription;

  BluetoothMessagingService({required this.currentUser, this.encryptionService});

  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('startServer');
      
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen((event) {
        if (event is Map) {
          _handleNativeEvent(Map<String, dynamic>.from(event));
        }
      });
      debugPrint('Bluetooth TCP-like Server started.');
    } catch (e) {
      debugPrint('Error initializing BluetoothMessagingService: $e');
    }
  }

  void shutdown() {
    _channel.invokeMethod('stopServer');
    _eventSubscription?.cancel();
  }

  void _handleNativeEvent(Map<String, dynamic> event) {
    final type = event['type'];
    final address = event['address'] as String;

    switch (type) {
      case 'connected':
        final isIncoming = event['isIncoming'] as bool? ?? false;
        debugPrint('Bluetooth connected to $address (incoming: $isIncoming)');
        // As soon as we connect (or someone connects to us), send our Identity Handshake
        _sendHandshake(address);
        break;
      case 'disconnected':
        debugPrint('Bluetooth disconnected from $address');
        _addressToOfflineMeshId.remove(address);
        break;
      case 'error':
        debugPrint('Bluetooth error on $address: ${event['error']}');
        break;
      case 'message':
        final rawMessage = event['message'] as String;
        _processRawMessage(address, rawMessage);
        break;
    }
  }

  void _sendHandshake(String address) {
    final payload = <String, dynamic>{
      'protocolVersion': 1,
      'type': 'IDENTITY_ANNOUNCEMENT',
      'offlineMeshId': currentUser.offlineMeshId,
    };

    if (encryptionService != null) {
      final pubKey = encryptionService!.identityPublicKeyBase64;
      if (pubKey != null) {
        payload['publicKey'] = pubKey;
        payload['keyId'] = encryptionService!.identityKeyId;
        payload['fingerprint'] = encryptionService!.fingerprint;
      }
    }

    final jsonStr = jsonEncode(payload);
    _channel.invokeMethod('sendMessage', {
      'address': address,
      'message': jsonStr,
    });
  }

  void _processRawMessage(String address, String rawMessage) {
    try {
      final payload = jsonDecode(rawMessage) as Map<String, dynamic>;
      
      if (payload['protocolVersion'] != 1) return;

      final type = payload['type'] as String?;
      
      if (type == 'IDENTITY_ANNOUNCEMENT') {
        final offlineMeshId = payload['offlineMeshId'] as String?;
        if (offlineMeshId != null) {
          _addressToOfflineMeshId[address] = offlineMeshId;
          debugPrint('Bluetooth handshake verified: $address is $offlineMeshId');

          final remotePubKey = payload['publicKey'] as String?;
          final remoteKeyId = payload['keyId'] as String?;
          final remoteFingerprint = payload['fingerprint'] as String?;

          if (remotePubKey != null && remoteKeyId != null && encryptionService != null) {
            encryptionService!.registerPeerKey(
              offlineMeshId: offlineMeshId,
              publicKeyBase64: remotePubKey,
              keyId: remoteKeyId,
              fingerprint: remoteFingerprint,
            );
          }
        }
      } else if (type == 'CHAT_MESSAGE') {
        // Validate recipient
        if (payload['recipientOfflineMeshId'] != currentUser.offlineMeshId) {
          debugPrint('Bluetooth message recipient mismatch.');
          return;
        }

        final senderOfflineMeshId = payload['senderOfflineMeshId'] as String?;
        // Ensure the sender matches the handshaked ID for this address
        if (senderOfflineMeshId == null || senderOfflineMeshId != _addressToOfflineMeshId[address]) {
          debugPrint('Bluetooth message spoofing detected or unverified peer.');
          return;
        }

        final messageData = payload['message'];
        if (messageData != null) {
          final message = Message.fromJson(messageData).copyWith(
            recipientOfflineMeshId: currentUser.offlineMeshId,
            transport: TransportType.BLUETOOTH,
          );
          _incomingMessagesController.add(message);
        }
      }
    } catch (e) {
      debugPrint('Failed to parse incoming Bluetooth message from $address: $e');
    }
  }

  /// Initiates a background connection to a discovered device for handshake.
  Future<void> connectAndHandshake(BluetoothDiscoveredDevice device) async {
    try {
      if (!_addressToOfflineMeshId.containsKey(device.address)) {
        await _channel.invokeMethod('connect', {'address': device.address});
      }
    } catch (e) {
      debugPrint('Bluetooth connect failed: $e');
    }
  }

  /// Sends a chat message to an OfflineMeshId over Bluetooth
  Future<void> sendMessage(String recipientOfflineMeshId, Message message) async {
    // Find the bluetooth address for this OfflineMesh ID
    String? targetAddress;
    _addressToOfflineMeshId.forEach((address, id) {
      if (id == recipientOfflineMeshId) {
        targetAddress = address;
      }
    });

    if (targetAddress == null) {
      throw Exception('Bluetooth peer $recipientOfflineMeshId not connected or handshaked.');
    }

    final payload = {
      'protocolVersion': 1,
      'type': 'CHAT_MESSAGE',
      'senderOfflineMeshId': currentUser.offlineMeshId,
      'recipientOfflineMeshId': recipientOfflineMeshId,
      'message': message.toJson(),
    };

    final jsonStr = jsonEncode(payload);
    
    await _channel.invokeMethod('sendMessage', {
      'address': targetAddress,
      'message': jsonStr,
    });
  }

  String? getOfflineMeshIdForAddress(String address) {
    return _addressToOfflineMeshId[address];
  }

  String? getAddressForOfflineMeshId(String offlineMeshId) {
    String? targetAddress;
    _addressToOfflineMeshId.forEach((address, id) {
      if (id == offlineMeshId) {
        targetAddress = address;
      }
    });
    return targetAddress;
  }
}
