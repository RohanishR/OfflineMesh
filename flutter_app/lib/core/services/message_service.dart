import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';

import '../config/app_config.dart';
import '../models/message.dart';
import 'local_storage_service.dart';
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

  bool get isConnected => _stompClient?.connected ?? false;

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
            final message = Message.fromJson(jsonMap).copyWith(
              transport: TransportType.INTERNET,
              status: 'delivered',
              recipientOfflineMeshId: jsonMap['recipientOfflineMeshId']?.toString() ?? encryptionService?.localOfflineMeshId,
            );

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
    if (_stompClient != null && _stompClient!.connected) {
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
            final rawMap = raw as Map<String, dynamic>;
            final msg = Message.fromJson(rawMap).copyWith(
              transport: TransportType.INTERNET,
              status: 'delivered',
              recipientOfflineMeshId: rawMap['recipientOfflineMeshId']?.toString() ?? encryptionService?.localOfflineMeshId,
            );
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
      final decoded = jsonDecode(response.body);
      final Iterable l;
      if (decoded is List) {
        l = decoded;
      } else if (decoded is Map<String, dynamic> && decoded['messages'] is List) {
        l = decoded['messages'] as List;
      } else {
        l = [];
      }
      final rawMessages = List<Message>.from(l.map((model) => Message.fromJson(model)));

      if (encryptionService == null) {
        return rawMessages;
      }

      final processedMessages = <Message>[];
      final myId = encryptionService!.localOfflineMeshId;
      for (final msg in rawMessages) {
        if (EncryptedEnvelope.isEncryptedEnvelope(msg.content)) {
          if (msg.senderOfflineMeshId == myId) {
            final envelope = EncryptedEnvelope.fromJson(jsonDecode(msg.content));
            if (envelope.messageId != msg.id) {
              await LocalStorageService().removeMessage(offlineMeshId, envelope.messageId);
            }
            String? cached = encryptionService!.getCachedSentMessage(msg.id);
            if (cached == null) {
              try {
                final env = EncryptedEnvelope.fromJson(jsonDecode(msg.content));
                cached = encryptionService!.getCachedSentMessage(env.messageId);
              } catch (_) {}
            }
            if (cached != null) {
              processedMessages.add(msg.copyWith(
                content: cached,
                recipientOfflineMeshId: offlineMeshId,
              ));
            }
          } else {
            try {
              final env = EncryptedEnvelope.fromJson(jsonDecode(msg.content));
              // Strict recipient check
              if (env.recipientId.isNotEmpty && env.recipientId != myId) {
                continue; // Do NOT add messages intended for another recipient!
              }
              final decryptedText = await encryptionService!.decryptMessage(
                env,
                checkReplay: false,
              );
              processedMessages.add(msg.copyWith(
                content: decryptedText,
                recipientOfflineMeshId: myId,
              ));
            } catch (e) {
              debugPrint('Skipping message that failed decryption or recipient check: $e');
              // Do NOT display 'Unable to decrypt message' or leak messages
            }
          }
        } else {
          // Plaintext message
          if (msg.recipientOfflineMeshId != null &&
              msg.recipientOfflineMeshId!.isNotEmpty &&
              msg.recipientOfflineMeshId != myId &&
              msg.senderOfflineMeshId != myId) {
            continue; // Mismatched recipient
          }
          processedMessages.add(msg.copyWith(
            recipientOfflineMeshId: msg.recipientOfflineMeshId ?? (msg.senderOfflineMeshId == myId ? offlineMeshId : myId),
          ));
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
