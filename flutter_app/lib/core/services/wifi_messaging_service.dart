import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/discovered_peer.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../../features/call/models/webrtc_signaling_message.dart';

class WifiMessagingService {
  static const int _messagingPort = 45455;
  ServerSocket? _serverSocket;
  final UserProfile currentUser;

  final _incomingMessagesController = StreamController<Message>.broadcast();
  Stream<Message> get incomingMessages => _incomingMessagesController.stream;

  final _incomingSignalingController = StreamController<WebRtcSignalingMessage>.broadcast();
  Stream<WebRtcSignalingMessage> get incomingSignalingMessages => _incomingSignalingController.stream;

  final _relayedPacketsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get relayedPackets => _relayedPacketsController.stream;

  final Map<String, String> _peerIpCache = {};
  String? getKnownIpForPeer(String offlineMeshId) => _peerIpCache[offlineMeshId];

  WifiMessagingService({required this.currentUser});

  Future<void> initialize() async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, _messagingPort);
      _serverSocket!.listen((Socket client) {
        _handleIncomingConnection(client);
      });
      debugPrint('WIFI_LAN TCP Server listening on $_messagingPort');
    } catch (e) {
      debugPrint('Error starting WIFI_LAN TCP Server: $e');
    }
  }

  void shutdown() {
    _serverSocket?.close();
    _serverSocket = null;
    _incomingMessagesController.close();
    _incomingSignalingController.close();
    _relayedPacketsController.close();
  }

  void _handleIncomingConnection(Socket client) {
    final List<int> incomingBytes = [];
    final clientIp = client.remoteAddress.address;

    client.listen(
      (List<int> chunk) {
        incomingBytes.addAll(chunk);
      },
      onError: (e) {
        debugPrint('TCP Client Error: $e');
        client.close();
      },
      onDone: () {
        try {
          if (incomingBytes.isNotEmpty) {
            final String payloadStr = utf8.decode(incomingBytes);
            final Map<String, dynamic> payload = jsonDecode(payloadStr);

            final senderOfflineMeshId = payload['senderOfflineMeshId'] as String?;
            if (senderOfflineMeshId != null && senderOfflineMeshId.isNotEmpty) {
              _peerIpCache[senderOfflineMeshId] = clientIp;
            }

            // Validate protocol and recipient
            if (payload['protocolVersion'] == 1) {
              final recipientOfflineMeshId = payload['recipientOfflineMeshId'] as String?;
              if (recipientOfflineMeshId == currentUser.offlineMeshId) {
                final type = payload['type'];

                if (type == 'WEBRTC_SIGNAL') {
                  final signalData = payload['signal'];
                  if (signalData != null) {
                    final signal = WebRtcSignalingMessage.fromJson(signalData);
                    _incomingSignalingController.add(signal);
                  }
                } else {
                  final messageData = payload['message'];
                  if (messageData != null) {
                    final message = Message.fromJson(messageData).copyWith(
                      recipientOfflineMeshId: currentUser.offlineMeshId,
                    );
                    _incomingMessagesController.add(message);
                  }
                }
              } else if (recipientOfflineMeshId != null && recipientOfflineMeshId.isNotEmpty) {
                // Multi-hop / Store-and-forward packet for another mesh peer
                debugPrint('Received multi-hop mesh packet for $recipientOfflineMeshId from $senderOfflineMeshId');
                _relayedPacketsController.add(payload);
              }
            }
          }
        } catch (e) {
          debugPrint('Error handling incoming TCP data: $e');
        } finally {
          client.close();
        }
      },
    );
  }

  Future<void> sendMessage(DiscoveredPeer peer, Message message, {int hopCount = 1}) async {
    Socket? socket;
    try {
      socket = await Socket.connect(peer.ipAddress, _messagingPort, timeout: const Duration(seconds: 3));

      final payload = {
        'protocolVersion': 1,
        'type': 'CHAT_MESSAGE',
        'senderOfflineMeshId': currentUser.offlineMeshId,
        'recipientOfflineMeshId': peer.offlineMeshId,
        'hopCount': hopCount,
        'maxHops': 3,
        'message': message.toJson(),
      };

      final data = utf8.encode(jsonEncode(payload));
      socket.add(data);
      await socket.flush();
    } finally {
      socket?.close();
    }
  }

  Future<void> sendRelayPacket(DiscoveredPeer peer, Map<String, dynamic> payload) async {
    Socket? socket;
    try {
      socket = await Socket.connect(peer.ipAddress, _messagingPort, timeout: const Duration(seconds: 3));
      final data = utf8.encode(jsonEncode(payload));
      socket.add(data);
      await socket.flush();
    } finally {
      socket?.close();
    }
  }

  Future<void> sendSignalingMessage(DiscoveredPeer peer, WebRtcSignalingMessage signal) async {
    Socket? socket;
    try {
      socket = await Socket.connect(peer.ipAddress, _messagingPort, timeout: const Duration(seconds: 3));

      final payload = {
        'protocolVersion': 1,
        'type': 'WEBRTC_SIGNAL',
        'senderOfflineMeshId': currentUser.offlineMeshId,
        'recipientOfflineMeshId': peer.offlineMeshId,
        'signal': signal.toJson(),
      };

      final data = utf8.encode(jsonEncode(payload));
      socket.add(data);
      await socket.flush();
    } catch (e) {
      debugPrint('Failed to send Wi-Fi WebRTC signal: $e');
      rethrow;
    } finally {
      socket?.close();
    }
  }
}
