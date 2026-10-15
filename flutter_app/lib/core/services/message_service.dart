import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';

import '../config/app_config.dart';
import '../models/message.dart';
import '../security/e2e_encryption_service.dart';
import '../security/encrypted_envelope.dart';
import '../transport/transport_type.dart';

class MessageService {
  final String baseUrl;
  final String jwtToken;
  E2eEncryptionService? encryptionService;

  StompClient? _stompClient;
  final _incomingMessagesController = StreamController<Message>.broadcast();
  Stream<Message> get incomingMessages => _incomingMessagesController.stream;

  bool get isConnected => _stompClient?.isActive ?? false;

  String? _syncCursor;
  bool _isSyncing = false;

  MessageService({String? baseUrl, required this.jwtToken, this.encryptionService}) 
      : baseUrl = baseUrl ?? AppConfig.backendBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      };

  Future<void> connectStomp() async {
    final wsUrl = baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://') + '/ws';

    _stompClient = StompClient(
      config: StompConfig(
        url: wsUrl,
        onConnect: _onConnect,
        onWebSocketError: (dynamic error) => debugPrint('Message STOMP WebSocket Error: $error'),
        stompConnectHeaders: {'Authorization': 'Bearer $jwtToken'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $jwtToken'},
      ),
    );
    _stompClient?.activate();
  }

  void _onConnect(StompFrame frame) {
    debugPrint('Connected to Message STOMP Server.');

    _stompClient?.subscribe(
      destination: '/user/queue/messages',
      callback: (frame) {
        if (frame.body != null) {
          try {
            final jsonMap = jsonDecode(frame.body!) as Map<String, dynamic>;
            final message = Message.fromJson(jsonMap);
            message.transport = TransportType.INTERNET;
            message.status = 'delivered';

            // Send ACK back to the server
            acknowledgeMessage(message.id);

            _incomingMessagesController.add(message);
          } catch (e) {
            debugPrint('Failed to parse incoming STOMP message: $e');
          }
        }
      },
    );

    // Sync catch-up on connect
    syncPendingMessages();
  }

  void acknowledgeMessage(String messageId) {
    if (_stompClient != null && _stompClient!.isActive) {
      _stompClient!.send(
        destination: '/app/messages/ack',
        body: jsonEncode({'messageId': messageId}),
      );
    }
  }

  Future<void> syncPendingMessages() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      bool hasMore = true;
      while (hasMore) {
        final queryParams = <String, String>{'limit': '50'};
        if (_syncCursor != null) {
          queryParams['cursor'] = _syncCursor!;
        }

        final uri = Uri.parse('$baseUrl/api/messages/sync').replace(queryParameters: queryParams);
        final response = await http.get(uri, headers: _headers);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final rawList = data['messages'] as List<dynamic>? ?? [];
          _syncCursor = data['nextCursor'] as String?;
          hasMore = data['hasMore'] as bool? ?? false;

          for (final raw in rawList) {
            final msg = Message.fromJson(raw as Map<String, dynamic>);
            msg.transport = TransportType.INTERNET;
            msg.status = 'delivered';
            acknowledgeMessage(msg.id);
            _incomingMessagesController.add(msg);
          }
        } else {
          hasMore = false;
        }
      }
    } catch (e) {
      debugPrint('Error syncing messages: $e');
    } finally {
      _isSyncing = false;
    }
  }

  void disconnectStomp() {
    _stompClient?.deactivate();
    _stompClient = null;
  }

  void dispose() {
    disconnectStomp();
    _incomingMessagesController.close();
  }

  Future<List<Message>> getConversationHistory(String offlineMeshId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/messages/$offlineMeshId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      Iterable l = jsonDecode(response.body);
      final rawMessages = List<Message>.from(l.map((model) => Message.fromJson(model)));

      if (encryptionService == null) {
        return rawMessages;
      }

      final processedMessages = <Message>[];
      for (final msg in rawMessages) {
        if (EncryptedEnvelope.isEncryptedEnvelope(msg.content)) {
          if (msg.senderOfflineMeshId == encryptionService!.localOfflineMeshId) {
            final cached = encryptionService!.getCachedSentMessage(msg.id);
            if (cached != null) {
              processedMessages.add(msg.copyWith(content: cached));
            } else {
              processedMessages.add(msg.copyWith(content: '[Encrypted sent message]'));
            }
          } else {
            try {
              final decryptedText = await encryptionService!.decryptMessage(
                msg.content,
                checkReplay: false,
              );
              processedMessages.add(msg.copyWith(content: decryptedText));
            } catch (e) {
              processedMessages.add(msg.copyWith(content: 'Unable to decrypt message.'));
            }
          }
        } else {
          processedMessages.add(msg);
        }
      }
      return processedMessages;
    } else {
      throw Exception('Failed to load messages');
    }
  }

  Future<Message> sendMessage(String offlineMeshId, String content) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/messages/$offlineMeshId'),
      headers: _headers,
      body: jsonEncode({'content': content}),
    );

    if (response.statusCode == 201) {
      return Message.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to send message: ${response.body}');
    }
  }
}
