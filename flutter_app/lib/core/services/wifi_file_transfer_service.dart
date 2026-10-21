import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/user.dart';
import '../models/discovered_peer.dart';
import '../../features/files/models/file_metadata.dart';

class _DigestSink implements Sink<Digest> {
  final Function(Digest) onDigest;
  _DigestSink(this.onDigest);
  @override
  void add(Digest data) => onDigest(data);
  @override
  void close() {}
}

class WifiFileTransferService {
  static const int _fileTransferPort = 45456;
  ServerSocket? _serverSocket;
  final UserProfile currentUser;

  final _incomingFilesController = StreamController<FileMetadata>.broadcast();
  Stream<FileMetadata> get incomingFiles => _incomingFilesController.stream;

  WifiFileTransferService({required this.currentUser});

  Future<void> initialize() async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, _fileTransferPort);
      _serverSocket!.listen((Socket client) {
        _handleIncomingFile(client);
      });
      debugPrint('WIFI_LAN File TCP Server listening on $_fileTransferPort');
    } catch (e) {
      debugPrint('Error starting WIFI_LAN File TCP Server: $e');
    }
  }

  void shutdown() {
    _serverSocket?.close();
    _serverSocket = null;
  }

  Future<void> _handleIncomingFile(Socket client) async {
    bool metadataParsed = false;
    FileMetadata? parsedMetadata;
    File? tempFile;
    IOSink? fileSink;
    int receivedBytes = 0;
    bool hasError = false;
    String? calculatedHash;

    final hashSink = sha256.startChunkedConversion(_DigestSink((digest) {
      calculatedHash = digest.toString();
    }));

    final List<int> headerBuffer = [];
    try {
      await for (final chunk in client) {
        if (!metadataParsed) {
          final newlineIndex = chunk.indexOf(10); // '\n' is 10
          if (newlineIndex != -1) {
            headerBuffer.addAll(chunk.sublist(0, newlineIndex));
            final headerStr = utf8.decode(headerBuffer);
            final payload = jsonDecode(headerStr);
            
            if (payload['protocolVersion'] == 1 && payload['metadata'] != null) {
              parsedMetadata = FileMetadata.fromJson(payload['metadata']);
              
              if (parsedMetadata.recipientOfflineMeshId != currentUser.offlineMeshId) {
                debugPrint('File not intended for this user. Dropping.');
                client.destroy();
                return;
              }
              
              final directory = await getTemporaryDirectory();
              tempFile = File(p.join(directory.path, 'temp_${parsedMetadata.id}'));
              fileSink = tempFile.openWrite();
              metadataParsed = true;
              
              final remaining = chunk.sublist(newlineIndex + 1);
              if (remaining.isNotEmpty) {
                fileSink.add(remaining);
                hashSink.add(remaining);
                receivedBytes += remaining.length;
              }
            } else {
              client.destroy();
              return;
            }
          } else {
            headerBuffer.addAll(chunk);
          }
        } else {
          fileSink?.add(chunk);
          hashSink.add(chunk);
          receivedBytes += chunk.length;
        }
      }
    } catch (e) {
      debugPrint('Error receiving Wi-Fi LAN file: $e');
      hasError = true;
    } finally {
      if (fileSink != null) {
        try {
          await fileSink.flush();
          await fileSink.close();
        } catch (_) {}
      }
      hashSink.close();
      client.destroy();

      if (parsedMetadata != null && tempFile != null && await tempFile.exists()) {
        if (hasError || receivedBytes != parsedMetadata.fileSize) {
          debugPrint('Incomplete file transfer! Expected ${parsedMetadata.fileSize} bytes, got $receivedBytes bytes. Deleting temporary file.');
          try {
            await tempFile.delete();
          } catch (_) {}
        } else if (parsedMetadata.checksum != null && calculatedHash != null && parsedMetadata.checksum != calculatedHash) {
          debugPrint('Checksum mismatch! Expected ${parsedMetadata.checksum}, got $calculatedHash. Deleting corrupted file.');
          try {
            await tempFile.delete();
          } catch (_) {}
        } else {
          // Success: Rename temp file to permanent documents directory
          try {
            final directory = await getApplicationDocumentsDirectory();
            final safeName = parsedMetadata.originalFileName.replaceAll(RegExp(r'[^a-zA-Z0-9.\-_]'), '_');
            final finalPath = p.join(directory.path, safeName);
            
            await tempFile.rename(finalPath);
            parsedMetadata.localFilePath = finalPath;

            final completedMetadata = FileMetadata(
              id: parsedMetadata.id,
              senderOfflineMeshId: parsedMetadata.senderOfflineMeshId,
              recipientOfflineMeshId: parsedMetadata.recipientOfflineMeshId,
              originalFileName: parsedMetadata.originalFileName,
              contentType: parsedMetadata.contentType,
              fileSize: parsedMetadata.fileSize,
              checksum: parsedMetadata.checksum,
              status: 'COMPLETED',
              createdAt: parsedMetadata.createdAt,
              updatedAt: DateTime.now(),
              localFilePath: finalPath,
              isEncrypted: parsedMetadata.isEncrypted,
              encryptedKeyEnvelope: parsedMetadata.encryptedKeyEnvelope,
            );
            
            _incomingFilesController.add(completedMetadata);
          } catch (e) {
            debugPrint('Failed to save completed file: $e');
          }
        }
      }
    }
  }

  Future<void> sendFile(DiscoveredPeer peer, FileMetadata metadata, File file, Function(double) onProgress) async {
    Socket? socket;
    try {
      socket = await Socket.connect(peer.ipAddress, _fileTransferPort, timeout: const Duration(seconds: 5));
      
      final payload = {
        'protocolVersion': 1,
        'metadata': metadata.toJson(),
      };
      
      final jsonPayload = jsonEncode(payload);
      final headerStr = '$jsonPayload\n';
      socket.add(utf8.encode(headerStr));
      
      final fileSize = metadata.fileSize;
      int sentBytes = 0;
      
      final fileStream = file.openRead();
      await for (final chunk in fileStream) {
        socket.add(chunk);
        sentBytes += chunk.length;
        if (fileSize > 0) {
          onProgress(sentBytes / fileSize);
        }
      }
      
      await socket.flush();
    } catch (e) {
      throw Exception('Failed to send file over WIFI_LAN: $e');
    } finally {
      socket?.destroy();
    }
  }
}

