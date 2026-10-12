import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/message.dart';
import '../security/e2e_encryption_service.dart';
import '../security/encrypted_envelope.dart';

class MessageService {
  final String baseUrl;
  final String jwtToken;
  E2eEncryptionService? encryptionService;

  MessageService({String? baseUrl, required this.jwtToken, this.encryptionService}) 
      : baseUrl = baseUrl ?? AppConfig.backendBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      };

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
