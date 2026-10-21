import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/message.dart';
import '../../features/files/models/file_metadata.dart';

class LocalStorageService {
  Directory? _documentsDir;

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
      final messages = jsonList.map((j) => Message.fromJson(Map<String, dynamic>.from(j))).toList();
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return messages;
    } catch (e) {
      debugPrint('Error loading conversation for $peerOfflineMeshId: $e');
      return [];
    }
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
        // If already exists, update status or transport if newer
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
}
