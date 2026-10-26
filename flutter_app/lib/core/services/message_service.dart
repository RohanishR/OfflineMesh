import '../network/auth_service.dart';
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
import '../../features/chat/models/conversation_summary.dart';
import 'presence_service.dart';

class MessageService {
  final String baseUrl;
  final String jwtToken;
  E2eEncryptionService? encryptionService;

  StompClient? _stompClient;
  final _incomingMessagesController = StreamController<Message>.broadcast();
  Stream<Message> get incomingMessages => _incomingMessagesController.stream;

  final _statusUpdatesController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get statusUpdates =>
      _statusUpdatesController.stream;

  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  PresenceService? _presenceService;
  PresenceService get presenceService {
    _presenceService ??= PresenceService(
      stompClient: _stompClient,
      myOfflineMeshId: encryptionService?.localOfflineMeshId ?? '',
    );
    return _presenceService!;
  }

  bool get isConnected => _stompClient?.connected ?? false;

  String? _syncCursor;
  bool _isSyncing = false;

  MessageService(
      {String? baseUrl, required this.jwtToken, this.encryptionService})
      : baseUrl = baseUrl ?? AppConfig.backendBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      };

  Future<void> connectStomp() async {
    final wsBase = baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final wsUrl = '$wsBase/ws';

    _stompClient = StompClient(
      config: StompConfig(
        url: wsUrl,
        onConnect: _onConnect,
        onStompError: (frame) {
          final error = '${frame.headers['message'] ?? ''} ${frame.body ?? ''}'
              .toLowerCase();
          if (error.contains('invalid jwt') ||
              error.contains('authentication failed')) {
            _stompClient?.deactivate();
            try {
              AuthService.checkResponse(401, jwtToken);
            } on SessionExpiredException {/* Home opens sign-in. */}
          }
        },
        onWebSocketError: (dynamic error) {
          debugPrint('Message STOMP WebSocket Error: $error');
          _connectionStateController.add(false);
        },
        stompConnectHeaders: {'Authorization': 'Bearer $jwtToken'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $jwtToken'},
      ),
    );
    _stompClient?.activate();
  }

  void _onConnect(StompFrame frame) {
    debugPrint('Connected to Message STOMP Server.');
    _connectionStateController.add(true);

    _stompClient?.subscribe(
      destination: '/user/queue/messages',
      callback: (frame) {
        if (frame.body != null) {
          try {
            final jsonMap = jsonDecode(frame.body!) as Map<String, dynamic>;
            final message = Message.fromJson(jsonMap).copyWith(
              transport: TransportType.INTERNET,
              status: 'delivered',
              recipientOfflineMeshId:
                  jsonMap['recipientOfflineMeshId']?.toString() ??
                      encryptionService?.localOfflineMeshId,
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

    _stompClient?.subscribe(
      destination: '/user/queue/messages/status',
      callback: (frame) {
        if (frame.body != null) {
          try {
            final jsonMap = jsonDecode(frame.body!) as Map<String, dynamic>;
            _statusUpdatesController.add(jsonMap);
          } catch (e) {
            debugPrint('Failed to parse status update: $e');
          }
        }
      },
    );

    // Initialize Presence Service
    presenceService.initialize(_stompClient);

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

        final uri = Uri.parse('$baseUrl/api/messages/sync')
            .replace(queryParameters: queryParams);
        final response = await http.get(uri, headers: _headers);

        AuthService.checkResponse(response.statusCode, jwtToken);

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
              recipientOfflineMeshId:
                  rawMap['recipientOfflineMeshId']?.toString() ??
                      encryptionService?.localOfflineMeshId,
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
    _connectionStateController.add(false);
  }

  void disconnect() => disconnectStomp();

  void dispose() {
    disconnectStomp();
    _presenceService?.dispose();
    _incomingMessagesController.close();
    _statusUpdatesController.close();
    _connectionStateController.close();
  }

  Future<List<Message>> getConversationHistory(String offlineMeshId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/messages/$offlineMeshId'),
      headers: _headers,
    );

    AuthService.checkResponse(response.statusCode, jwtToken);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final Iterable l;
      if (decoded is List) {
        l = decoded;
      } else if (decoded is Map<String, dynamic> &&
          decoded['messages'] is List) {
        l = decoded['messages'] as List;
      } else {
        l = [];
      }
      final rawMessages =
          List<Message>.from(l.map((model) => Message.fromJson(model)));

      if (encryptionService == null) {
        return _reconcileReactionsAndMedia(rawMessages);
      }

      final processedMessages = <Message>[];
      final myId = encryptionService!.localOfflineMeshId;
      for (final msg in rawMessages) {
        if (EncryptedEnvelope.isEncryptedEnvelope(msg.content)) {
          if (msg.senderOfflineMeshId == myId) {
            final envelope =
                EncryptedEnvelope.fromJson(jsonDecode(msg.content));
            if (envelope.messageId != msg.id) {
              await LocalStorageService()
                  .removeMessage(offlineMeshId, envelope.messageId);
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
              debugPrint(
                  'Skipping message that failed decryption or recipient check: $e');
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
            recipientOfflineMeshId: msg.recipientOfflineMeshId ??
                (msg.senderOfflineMeshId == myId ? offlineMeshId : myId),
          ));
        }
      }
      return _reconcileReactionsAndMedia(processedMessages);
    } else {
      throw Exception('Failed to load messages');
    }
  }

  /// Extracts emoji reactions and attaches them to their target messages,
  /// removing raw reaction packets from the conversation list, and transforms
  /// media messages to valid rich media items.
  List<Message> _reconcileReactionsAndMedia(List<Message> messages) {
    final cleanMessages = <Message>[];
    final reactionsToApply = <Map<String, dynamic>>[];

    for (var msg in messages) {
      final trimmed = msg.content.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        try {
          final data = jsonDecode(trimmed);
          if (data is Map && data['type'] == 'REACTION') {
            reactionsToApply.add(Map<String, dynamic>.from(data));
            continue; // Drop raw reaction packet
          } else if (data is Map && data['type'] == 'MEDIA_MESSAGE') {
            final fileName = data['fileName']?.toString() ?? 'attachment';
            msg = msg.copyWith(
              content: fileName,
              mediaType: data['mediaType']?.toString() ?? 'file',
              fileName: fileName,
              fileSize: data['fileSize'] is num
                  ? (data['fileSize'] as num).toInt()
                  : null,
              durationMs: data['durationMs'] is num
                  ? (data['durationMs'] as num).toInt()
                  : null,
              fileHash: data['fileHash']?.toString(),
              attachmentId: data['fileId']?.toString(),
            );
          }
        } catch (_) {}
      }
      cleanMessages.add(msg);
    }

    // Apply emoji reactions to target messages
    for (final r in reactionsToApply) {
      final targetId = r['targetMessageId']?.toString();
      final emoji = r['emoji']?.toString();
      final senderId = r['senderId']?.toString() ?? '';
      if (targetId != null && emoji != null) {
        final idx = cleanMessages.indexWhere((m) => m.id == targetId);
        if (idx != -1) {
          final curReactions =
              Map<String, String>.from(cleanMessages[idx].reactions ?? {});
          curReactions[senderId] = emoji;
          cleanMessages[idx] =
              cleanMessages[idx].copyWith(reactions: curReactions);
        }
      }
    }

    return cleanMessages;
  }

  Future<Message> sendMessage(String offlineMeshId, String content) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/messages/$offlineMeshId'),
      headers: _headers,
      body: jsonEncode({'content': content}),
    );

    AuthService.checkResponse(response.statusCode, jwtToken);

    if (response.statusCode == 201) {
      return Message.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to send message: ${response.body}');
    }
  }

  Future<List<ConversationSummary>> getConversations() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/messages/conversations'),
      headers: _headers,
    );

    AuthService.checkResponse(response.statusCode, jwtToken);

    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      final summaries = <ConversationSummary>[];

      for (final item in list) {
        final rawMap = item as Map<String, dynamic>;
        String lastMsg = rawMap['lastMessage']?.toString() ?? '';

        // If encrypted envelope, try to decrypt or check cached message
        if (encryptionService != null &&
            EncryptedEnvelope.isEncryptedEnvelope(lastMsg)) {
          try {
            final env = EncryptedEnvelope.fromJson(jsonDecode(lastMsg));
            if (rawMap['isLastMessageFromMe'] == true) {
              lastMsg =
                  encryptionService!.getCachedSentMessage(env.messageId) ??
                      'Sent message';
            } else {
              lastMsg = await encryptionService!
                  .decryptMessage(env, checkReplay: false);
            }
          } catch (_) {
            lastMsg = 'Encrypted message';
          }
        }

        summaries.add(ConversationSummary.fromJson({
          ...rawMap,
          'lastMessage': lastMsg,
        }));
      }

      return summaries;
    } else {
      throw Exception('Failed to load conversations: ${response.body}');
    }
  }

  Future<Message> editMessage(String messageId, String newContent) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/messages/$messageId'),
      headers: _headers,
      body: jsonEncode({'content': newContent}),
    );

    AuthService.checkResponse(response.statusCode, jwtToken);

    if (response.statusCode == 200) {
      return Message.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to edit message: ${response.body}');
    }
  }

  Future<Message> deleteMessageForEveryone(String messageId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/messages/$messageId'),
      headers: _headers,
    );

    AuthService.checkResponse(response.statusCode, jwtToken);

    if (response.statusCode == 200) {
      return Message.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to delete message: ${response.body}');
    }
  }

  Future<void> markMessagesAsRead(String senderOfflineMeshId) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/messages/read/$senderOfflineMeshId'),
        headers: _headers,
      );
    } catch (e) {
      debugPrint('Failed to send read receipts: $e');
    }
  }
}
