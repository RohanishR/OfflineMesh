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
  }

  void _handleIncomingConnection(Socket client) {
    final List<int> incomingBytes = [];

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

            // Validate protocol and recipient
            if (payload['protocolVersion'] == 1 &&
                payload['recipientOfflineMeshId'] == currentUser.offlineMeshId) {
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
                  final message = Message.fromJson(messageData);
                  _incomingMessagesController.add(message);
                }
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

  Future<void> sendMessage(DiscoveredPeer peer, Message message) async {
    Socket? socket;
    try {
      socket = await Socket.connect(peer.ipAddress, _messagingPort, timeout: const Duration(seconds: 3));

      final payload = {
        'protocolVersion': 1,
        'type': 'CHAT_MESSAGE',
        'senderOfflineMeshId': currentUser.offlineMeshId,
        'recipientOfflineMeshId': peer.offlineMeshId,
        'message': message.toJson(),
      };

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
