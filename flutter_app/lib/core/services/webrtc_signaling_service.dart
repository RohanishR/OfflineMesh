import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';

import '../config/app_config.dart';
import '../../features/call/models/webrtc_signaling_message.dart';

class WebRtcSignalingService {
  final String jwtToken;
  final String localOfflineMeshId;
  StompClient? _stompClient;

  final _incomingSignalingController = StreamController<WebRtcSignalingMessage>.broadcast();
  Stream<WebRtcSignalingMessage> get incomingSignalingMessages => _incomingSignalingController.stream;

  bool get isConnected => _stompClient?.isActive ?? false;

  WebRtcSignalingService({
    required this.jwtToken,
    required this.localOfflineMeshId,
  });

  Future<void> connect() async {
    final wsUrl = AppConfig.backendBaseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://') + '/ws';

    _stompClient = StompClient(
      config: StompConfig(
        url: wsUrl,
        onConnect: _onConnect,
        onWebSocketError: (dynamic error) => debugPrint('STOMP WebSocket Error: $error'),
        stompConnectHeaders: {'Authorization': 'Bearer $jwtToken'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $jwtToken'},
      ),
    );
    _stompClient?.activate();
  }

  void _onConnect(StompFrame frame) {
    debugPrint('Connected to WebRTC STOMP Signaling Server.');
    
    _stompClient?.subscribe(
      destination: '/user/queue/webrtc',
      callback: (frame) {
        if (frame.body != null) {
          try {
            final jsonMap = jsonDecode(frame.body!);
            final message = WebRtcSignalingMessage.fromJson(jsonMap);
            _incomingSignalingController.add(message);
          } catch (e) {
            debugPrint('Failed to parse incoming WebRTC signaling message: $e');
          }
        }
      },
    );
  }

  void disconnect() {
    _stompClient?.deactivate();
    _stompClient = null;
  }

  bool sendSignalingMessage(WebRtcSignalingMessage message) {
    if (_stompClient != null && _stompClient!.isActive) {
      _stompClient!.send(
        destination: '/app/webrtc/signal',
        body: jsonEncode(message.toJson()),
      );
      return true;
    } else {
      debugPrint('Warning: STOMP Client not active. Cannot send WebRTC signal.');
      return false;
    }
  }

  void dispose() {
    disconnect();
    _incomingSignalingController.close();
  }
}
