import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/message.dart';
import '../models/user.dart';
import '../models/ble_discovered_device.dart';
import '../transport/transport_type.dart';

class BleMessagingService {
  static const MethodChannel _channel = MethodChannel('com.offlinemesh/ble_messaging');
  static const EventChannel _eventChannel = EventChannel('com.offlinemesh/ble_messaging/events');

  final UserProfile currentUser;
  
  // Mappings: BLE MAC Address -> OfflineMesh ID
  final Map<String, String> _addressToOfflineMeshId = {};
  
  final _incomingMessagesController = StreamController<Message>.broadcast();
  Stream<Message> get incomingMessages => _incomingMessagesController.stream;

  StreamSubscription? _eventSubscription;

  BleMessagingService({required this.currentUser});

  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('startServer', {
        'localId': currentUser.id
      });
      
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen((event) {
        if (event is Map) {
          _handleNativeEvent(Map<String, dynamic>.from(event));
        }
      });
      debugPrint('BLE Messaging GATT Server started.');
    } catch (e) {
      debugPrint('Error initializing BleMessagingService: $e');
    }
  }

  void shutdown() {
    _channel.invokeMethod('stopServer');
    _eventSubscription?.cancel();
  }

  void connect(String address) {
    _channel.invokeMethod('connect', {'address': address});
  }

  void disconnect(String address) {
    _channel.invokeMethod('disconnect', {'address': address});
  }

  void _handleNativeEvent(Map<String, dynamic> event) {
    final type = event['type'];
    final address = event['address'] as String;

    switch (type) {
      case 'connected':
        final isIncoming = event['isIncoming'] as bool? ?? false;
        debugPrint('BLE GATT connected to $address (incoming: $isIncoming)');
        // Once connected, we send our Identity Handshake
        _sendHandshake(address);
        break;
      case 'disconnected':
        debugPrint('BLE GATT disconnected from $address');
        _addressToOfflineMeshId.remove(address);
        break;
      case 'error':
        debugPrint('BLE error on $address: ${event['error']}');
        break;
      case 'message':
        final rawMessage = event['message'] as String;
        _processRawMessage(address, rawMessage);
        break;
    }
  }

  void _sendHandshake(String address) {
    final payload = {
      'protocolVersion': 1,
      'type': 'IDENTITY_ANNOUNCEMENT',
      'offlineMeshId': currentUser.offlineMeshId,
    };
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
          debugPrint('BLE handshake verified: $address is $offlineMeshId');
        }
      } else if (type == 'CHAT_MESSAGE') {
        // Validate recipient
        if (payload['recipientId'] != currentUser.offlineMeshId) return;

        // Construct existing Message object
        final message = Message(
          id: payload['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          senderOfflineMeshId: payload['senderId'] ?? 'unknown',
          content: payload['content'] ?? '',
          createdAt: payload['timestamp'] != null 
              ? DateTime.parse(payload['timestamp']) 
              : DateTime.now(),
          status: 'delivered',
          transport: TransportType.BLE,
        );

        _incomingMessagesController.add(message);
      }
    } catch (e) {
      debugPrint('Error parsing incoming BLE message: $e');
    }
  }

  Future<bool> hasMeshRoute(String offlineMeshId) async {
    try {
      final result = await _channel.invokeMethod('hasRoute', {'destId': offlineMeshId});
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking BLE mesh route: $e');
      return false;
    }
  }

  Future<void> sendMessage(String recipientOfflineMeshId, Message message) async {
    // Find the BLE address corresponding to the requested offlineMeshId
    String? targetAddress;
    _addressToOfflineMeshId.forEach((address, meshId) {
      if (meshId == recipientOfflineMeshId) {
        targetAddress = address;
      }
    });

    if (targetAddress == null) {
      targetAddress = 'mesh'; // Delegate mesh routing and queueing to Kotlin
    }

    final payload = {
      'protocolVersion': 1,
      'type': 'CHAT_MESSAGE',
      'id': message.id,
      'senderId': message.senderOfflineMeshId,
      'recipientId': recipientOfflineMeshId,
      'content': message.content,
      'timestamp': message.createdAt.toIso8601String(),
    };

    final jsonStr = jsonEncode(payload);
    await _channel.invokeMethod('sendMessage', {
      'address': targetAddress,
      'message': jsonStr,
    });
  }

  Future<void> connectAndHandshake(BleDiscoveredDevice device) async {
    try {
      if (!_addressToOfflineMeshId.containsKey(device.address)) {
        await _channel.invokeMethod('connect', {'address': device.address});
      }
    } catch (e) {
      debugPrint('BLE connect failed: $e');
    }
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
