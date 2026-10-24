import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/message.dart';
import '../../features/files/models/file_metadata.dart';

class LocalStorageService {
  Directory? _documentsDir;

  LocalStorageService({Directory? baseDir}) : _documentsDir = baseDir;

  Future<Directory> _getDir() async {
    _documentsDir ??= await getApplicationDocumentsDirectory();
    return _documentsDir!;
  }

  String _sanitizeId(String id) {
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }

  // --- Conversations Persistence ---

  Future<File> _getConversationFile(String peerOfflineMeshId) async {
    final dir = await _getDir();
    final convDir = Directory(p.join(dir.path, 'conversations'));
    if (!await convDir.exists()) {
      await convDir.create(recursive: true);
    }
    return File(p.join(convDir.path, 'messages_${_sanitizeId(peerOfflineMeshId)}.json'));
  }

  Future<List<Message>> loadConversation(String peerOfflineMeshId) async {
    try {
      final file = await _getConversationFile(peerOfflineMeshId);
      if (!await file.exists()) {
        return [];
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(content);
      final messages = jsonList
          .map((j) => Message.fromJson(Map<String, dynamic>.from(j)))
          .where((m) => m.content != '[Encrypted sent message]')
          .toList();
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return messages;
    } catch (e) {
      debugPrint('Error loading conversation for $peerOfflineMeshId: $e');
      return [];
    }
  }

  Future<void> removeMessage(String peerOfflineMeshId, String messageId) async {
    final messages = await loadConversation(peerOfflineMeshId);
    messages.removeWhere((message) => message.id == messageId);
    final file = await _getConversationFile(peerOfflineMeshId);
    await file.writeAsString(jsonEncode(messages.map((m) => m.toJson()).toList()), flush: true);
  }

  Future<void> saveMessage(String peerOfflineMeshId, Message message) async {
    await saveMessages(peerOfflineMeshId, [message]);
  }

  Future<void> saveMessages(String peerOfflineMeshId, List<Message> newMessages) async {
    if (newMessages.isEmpty) return;
    try {
      final file = await _getConversationFile(peerOfflineMeshId);
      final existingMessages = await loadConversation(peerOfflineMeshId);
      
      final Map<String, Message> messageMap = {
        for (var m in existingMessages) m.id: m,
      };

      for (var msg in newMessages) {
        if (msg.content == '[Encrypted sent message]') continue;
        messageMap[msg.id] = msg;
      }

      final merged = messageMap.values.toList();
      merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final jsonStr = jsonEncode(merged.map((m) => m.toJson()).toList());
      await file.writeAsString(jsonStr, flush: true);
    } catch (e) {
      debugPrint('Error saving messages for $peerOfflineMeshId: $e');
    }
  }

  Future<void> updateMessage(String peerOfflineMeshId, Message updatedMessage) async {
    try {
      final messages = await loadConversation(peerOfflineMeshId);
      final index = messages.indexWhere((m) => m.id == updatedMessage.id);
      if (index != -1) {
        messages[index] = updatedMessage;
      } else {
        messages.add(updatedMessage);
      }
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final file = await _getConversationFile(peerOfflineMeshId);
      await file.writeAsString(jsonEncode(messages.map((m) => m.toJson()).toList()), flush: true);
    } catch (e) {
      debugPrint('Error updating message in $peerOfflineMeshId: $e');
    }
  }

  Future<void> updateMessageContent(
    String peerOfflineMeshId,
    String messageId,
    String newContent, {
    bool isEdited = false,
    bool isDeleted = false,
  }) async {
    try {
      final messages = await loadConversation(peerOfflineMeshId);
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        messages[index] = messages[index].copyWith(
          content: newContent,
          isEdited: isEdited,
          isDeleted: isDeleted,
          editedAt: isEdited ? DateTime.now() : messages[index].editedAt,
        );
        final file = await _getConversationFile(peerOfflineMeshId);
        await file.writeAsString(jsonEncode(messages.map((m) => m.toJson()).toList()), flush: true);
      }
    } catch (e) {
      debugPrint('Error updating message content in $peerOfflineMeshId: $e');
    }
  }

  Future<void> markConversationAsRead(String peerOfflineMeshId, String myOfflineMeshId) async {
    try {
      final messages = await loadConversation(peerOfflineMeshId);
      bool changed = false;
      for (int i = 0; i < messages.length; i++) {
        final m = messages[i];
        if (m.senderOfflineMeshId == peerOfflineMeshId && m.status.toLowerCase() != 'read') {
          messages[i] = m.copyWith(status: 'read');
          changed = true;
        }
      }
      if (changed) {
        final file = await _getConversationFile(peerOfflineMeshId);
        await file.writeAsString(jsonEncode(messages.map((m) => m.toJson()).toList()), flush: true);
      }
    } catch (e) {
      debugPrint('Error marking conversation as read: $e');
    }
  }

  Future<List<String>> getAllConversationPeerIds() async {
    try {
      final dir = await _getDir();
      final convDir = Directory(p.join(dir.path, 'conversations'));
      if (!await convDir.exists()) return [];
      final files = await convDir.list().toList();
      final peerIds = <String>[];
      for (var f in files) {
        if (f is File && p.basename(f.path).startsWith('messages_') && f.path.endsWith('.json')) {
          final raw = p.basenameWithoutExtension(f.path).replaceFirst('messages_', '');
          peerIds.add(raw);
        }
      }
      return peerIds;
    } catch (e) {
      debugPrint('Error listing conversation peer IDs: $e');
      return [];
    }
  }

  // --- Conversation Flags (Pinned, Archived, Muted) ---

  Future<File> _getConversationFlagsFile() async {
    final dir = await _getDir();
    final convDir = Directory(p.join(dir.path, 'conversations'));
    if (!await convDir.exists()) {
      await convDir.create(recursive: true);
    }
    return File(p.join(convDir.path, 'conversation_flags.json'));
  }

  Future<Map<String, dynamic>> _loadAllFlags() async {
    try {
      final file = await _getConversationFlagsFile();
      if (!await file.exists()) return {};
      final content = await file.readAsString();
      if (content.trim().isEmpty) return {};
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  Future<Map<String, bool>> getConversationFlags(String peerOfflineMeshId) async {
    final all = await _loadAllFlags();
    final item = all[_sanitizeId(peerOfflineMeshId)];
    if (item is Map) {
      return {
        'pinned': item['pinned'] == true,
        'archived': item['archived'] == true,
        'muted': item['muted'] == true,
      };
    }
    return {'pinned': false, 'archived': false, 'muted': false};
  }

  Future<void> setConversationFlag(String peerOfflineMeshId, String flag, bool value) async {
    try {
      final all = await _loadAllFlags();
      final key = _sanitizeId(peerOfflineMeshId);
      final current = Map<String, dynamic>.from(all[key] as Map? ?? {});
      current[flag] = value;
      all[key] = current;
      final file = await _getConversationFlagsFile();
      await file.writeAsString(jsonEncode(all), flush: true);
    } catch (e) {
      debugPrint('Error saving flag $flag for $peerOfflineMeshId: $e');
    }
  }

  // --- File Metadata Persistence ---

  Future<File> _getFileMetadataFile(String type) async {
    final dir = await _getDir();
    final fileDir = Directory(p.join(dir.path, 'transfers'));
    if (!await fileDir.exists()) {
      await fileDir.create(recursive: true);
    }
    return File(p.join(fileDir.path, '$type.json'));
  }

  Future<List<FileMetadata>> loadSentFiles() async {
    return _loadFileMetadataList('sent_files');
  }

  Future<List<FileMetadata>> loadReceivedFiles() async {
    return _loadFileMetadataList('received_files');
  }

  Future<List<FileMetadata>> _loadFileMetadataList(String type) async {
    try {
      final file = await _getFileMetadataFile(type);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(content);
      final files = jsonList.map((j) => FileMetadata.fromJson(Map<String, dynamic>.from(j))).toList();
      files.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return files;
    } catch (e) {
      debugPrint('Error loading $type: $e');
      return [];
    }
  }

  Future<void> saveSentFile(FileMetadata metadata) async {
    await _saveFileMetadata('sent_files', metadata);
  }

  Future<void> saveReceivedFile(FileMetadata metadata) async {
    await _saveFileMetadata('received_files', metadata);
  }

  Future<void> _saveFileMetadata(String type, FileMetadata metadata) async {
    try {
      final file = await _getFileMetadataFile(type);
      final existing = await _loadFileMetadataList(type);
      
      final Map<String, FileMetadata> fileMap = {
        for (var f in existing) f.id: f,
      };
      fileMap[metadata.id] = metadata;

      final updated = fileMap.values.toList();
      updated.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final jsonStr = jsonEncode(updated.map((f) => f.toJson()).toList());
      await file.writeAsString(jsonStr, flush: true);
    } catch (e) {
      debugPrint('Error saving $type metadata: $e');
    }
  }

  // --- Offline Outbox Persistence ---

  Future<File> _getOutboxFile() async {
    final dir = await _getDir();
    final outboxDir = Directory(p.join(dir.path, 'outbox'));
    if (!await outboxDir.exists()) {
      await outboxDir.create(recursive: true);
    }
    return File(p.join(outboxDir.path, 'offline_outbox.json'));
  }

  Future<List<Map<String, dynamic>>> loadOutbox() async {
    try {
      final file = await _getOutboxFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error loading outbox: $e');
      return [];
    }
  }

  Future<void> addToOutbox({
    required String recipientOfflineMeshId,
    required Message message,
    required String wireContent,
  }) async {
    try {
      final file = await _getOutboxFile();
      final outbox = await loadOutbox();

      // Check if message ID already queued
      outbox.removeWhere((item) => item['messageId'] == message.id);

      outbox.add({
        'messageId': message.id,
        'recipientOfflineMeshId': recipientOfflineMeshId,
        'message': message.toJson(),
        'wireContent': wireContent,
        'queuedAt': DateTime.now().toIso8601String(),
        'retryCount': 0,
      });

      await file.writeAsString(jsonEncode(outbox), flush: true);
    } catch (e) {
      debugPrint('Error adding to outbox: $e');
    }
  }

  Future<void> removeFromOutbox(String messageId) async {
    try {
      final file = await _getOutboxFile();
      final outbox = await loadOutbox();
      outbox.removeWhere((item) => item['messageId'] == messageId);
      await file.writeAsString(jsonEncode(outbox), flush: true);
    } catch (e) {
      debugPrint('Error removing from outbox: $e');
    }
  }

  Future<void> updateOutboxItem(
    String messageId, {
    int? retryCount,
    String? lastError,
    String? status,
  }) async {
    try {
      final file = await _getOutboxFile();
      final outbox = await loadOutbox();
      final index = outbox.indexWhere((item) => item['messageId'] == messageId);
      if (index != -1) {
        if (retryCount != null) {
          outbox[index]['retryCount'] = retryCount;
        }
        if (lastError != null) {
          outbox[index]['lastError'] = lastError;
        }
        if (status != null) {
          outbox[index]['status'] = status;
        }
        outbox[index]['lastAttemptAt'] = DateTime.now().toIso8601String();
        await file.writeAsString(jsonEncode(outbox), flush: true);
      }
    } catch (e) {
      debugPrint('Error updating outbox item $messageId: $e');
    }
  }

  // --- Persistent Deduplication Cache ---

  Future<File> _getProcessedMessagesFile() async {
    final dir = await _getDir();
    final convDir = Directory(p.join(dir.path, 'conversations'));
    if (!await convDir.exists()) {
      await convDir.create(recursive: true);
    }
    return File(p.join(convDir.path, 'processed_messages.json'));
  }

  Future<Map<String, String>> _loadProcessedMessages() async {
    try {
      final file = await _getProcessedMessagesFile();
      if (!await file.exists()) return {};
      final content = await file.readAsString();
      if (content.trim().isEmpty) return {};
      final Map<String, dynamic> raw = jsonDecode(content);
      final now = DateTime.now();

      // Prune expired entries
      final valid = <String, String>{};
      for (final entry in raw.entries) {
        final expiry = DateTime.tryParse(entry.value.toString());
        if (expiry != null && expiry.isAfter(now)) {
          valid[entry.key] = entry.value.toString();
        }
      }
      return valid;
    } catch (e) {
      debugPrint('Error loading processed messages: $e');
      return {};
    }
  }

  Future<bool> hasMessageBeenProcessed(String messageId) async {
    try {
      final processed = await _loadProcessedMessages();
      return processed.containsKey(messageId);
    } catch (e) {
      return false;
    }
  }

  Future<void> markMessageProcessed(
    String messageId, {
    Duration expiry = const Duration(days: 7),
  }) async {
    try {
      final processed = await _loadProcessedMessages();
      final expiryTime = DateTime.now().add(expiry).toIso8601String();
      processed[messageId] = expiryTime;

      // Keep cache bounded to 2000 entries
      if (processed.length > 2000) {
        final keysToRemove = processed.keys.take(processed.length - 2000).toList();
        for (final k in keysToRemove) {
          processed.remove(k);
        }
      }

      final file = await _getProcessedMessagesFile();
      await file.writeAsString(jsonEncode(processed), flush: true);
    } catch (e) {
      debugPrint('Error marking message $messageId as processed: $e');
    }
  }

  // --- Store-and-Forward Wi-Fi Relay Buffer ---

  Future<File> _getRelayBufferFile() async {
    final dir = await _getDir();
    final outboxDir = Directory(p.join(dir.path, 'outbox'));
    if (!await outboxDir.exists()) {
      await outboxDir.create(recursive: true);
    }
    return File(p.join(outboxDir.path, 'relay_buffer.json'));
  }

  Future<List<Map<String, dynamic>>> loadRelayBuffer() async {
    try {
      final file = await _getRelayBufferFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error loading relay buffer: $e');
      return [];
    }
  }

  Future<void> addToRelayBuffer(Map<String, dynamic> packet) async {
    try {
      final file = await _getRelayBufferFile();
      final buffer = await loadRelayBuffer();

      final packetId = packet['packetId']?.toString() ??
          packet['message']?['id']?.toString() ??
          packet['id']?.toString() ??
          '';

      if (packetId.isNotEmpty) {
        buffer.removeWhere((item) {
          final id = item['packetId']?.toString() ??
              item['message']?['id']?.toString() ??
              item['id']?.toString();
          return id == packetId;
        });
      }

      final relayItem = {
        'packetId': packetId,
        'recipientOfflineMeshId': packet['recipientOfflineMeshId'],
        'senderOfflineMeshId': packet['senderOfflineMeshId'],
        'packet': packet,
        'hopCount': packet['hopCount'] ?? 1,
        'bufferedAt': DateTime.now().toIso8601String(),
      };

      buffer.add(relayItem);

      // Keep relay buffer bounded to 500 items max
      if (buffer.length > 500) {
        buffer.removeRange(0, buffer.length - 500);
      }

      await file.writeAsString(jsonEncode(buffer), flush: true);
    } catch (e) {
      debugPrint('Error adding to relay buffer: $e');
    }
  }

  Future<void> removeFromRelayBuffer(String packetId) async {
    try {
      final file = await _getRelayBufferFile();
      final buffer = await loadRelayBuffer();
      buffer.removeWhere((item) {
        final id = item['packetId']?.toString() ??
            item['message']?['id']?.toString() ??
            item['id']?.toString();
        return id == packetId;
      });
      await file.writeAsString(jsonEncode(buffer), flush: true);
    } catch (e) {
      debugPrint('Error removing from relay buffer: $e');
    }
  }

  Future<void> pruneExpiredRelayPackets({
    Duration maxAge = const Duration(hours: 24),
  }) async {
    try {
      final file = await _getRelayBufferFile();
      final buffer = await loadRelayBuffer();
      final now = DateTime.now();
      final beforeCount = buffer.length;

      buffer.removeWhere((item) {
        final bufferedAt = DateTime.tryParse(item['bufferedAt']?.toString() ?? '');
        if (bufferedAt == null) return false;
        return now.difference(bufferedAt) > maxAge;
      });

      if (buffer.length != beforeCount) {
        await file.writeAsString(jsonEncode(buffer), flush: true);
      }
    } catch (e) {
      debugPrint('Error pruning relay buffer: $e');
    }
  }
}
