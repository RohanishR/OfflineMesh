import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/models/message.dart';
import 'package:flutter_app/core/transport/transport_type.dart';
import 'package:flutter_app/core/services/voice_note_service.dart';

void main() {
  group('WhatsApp Phase 2: Rich Media & Voice Messaging Tests', () {
    test('Voice Note message serialization and duration calculation', () {
      final now = DateTime.now();
      final voiceMsg = Message(
        id: 'vn-msg-1',
        senderOfflineMeshId: 'alice-mesh',
        recipientOfflineMeshId: 'bob-mesh',
        content: 'voice_note_001.m4a',
        createdAt: now,
        status: 'sent',
        transport: TransportType.WIFI_LAN,
        mediaType: 'audio',
        mediaPath: '/data/user/0/com.example.flutter_app/cache/voice_notes/vn_001.m4a',
        fileName: 'voice_note_001.m4a',
        fileSize: 48200,
        durationMs: 14200, // 14.2 seconds
        fileHash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );

      final json = voiceMsg.toJson();
      expect(json['id'], 'vn-msg-1');
      expect(json['mediaType'], 'audio');
      expect(json['fileName'], 'voice_note_001.m4a');
      expect(json['fileSize'], 48200);
      expect(json['durationMs'], 14200);
      expect(json['fileHash'], 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');

      final deserialized = Message.fromJson(json);
      expect(deserialized.id, 'vn-msg-1');
      expect(deserialized.mediaType, 'audio');
      expect(deserialized.durationMs, 14200);
      expect(deserialized.fileSize, 48200);
      expect(deserialized.mediaPath, '/data/user/0/com.example.flutter_app/cache/voice_notes/vn_001.m4a');
    });

    test('Image, Video, and Document message serialization', () {
      final imgMsg = Message(
        id: 'img-1',
        senderOfflineMeshId: 'alice',
        recipientOfflineMeshId: 'bob',
        content: 'sunset.jpg',
        createdAt: DateTime.now(),
        mediaType: 'image',
        mediaPath: '/storage/emulated/0/Download/sunset.jpg',
        fileName: 'sunset.jpg',
        fileSize: 1548200,
      );

      final videoMsg = Message(
        id: 'vid-1',
        senderOfflineMeshId: 'alice',
        recipientOfflineMeshId: 'bob',
        content: 'walkthrough.mp4',
        createdAt: DateTime.now(),
        mediaType: 'video',
        mediaPath: '/storage/emulated/0/Download/walkthrough.mp4',
        fileName: 'walkthrough.mp4',
        fileSize: 12480200,
        durationMs: 45000,
      );

      final docMsg = Message(
        id: 'doc-1',
        senderOfflineMeshId: 'alice',
        recipientOfflineMeshId: 'bob',
        content: 'contract.pdf',
        createdAt: DateTime.now(),
        mediaType: 'file',
        mediaPath: '/storage/emulated/0/Documents/contract.pdf',
        fileName: 'contract.pdf',
        fileSize: 320400,
      );

      expect(imgMsg.mediaType, 'image');
      expect(imgMsg.fileSize, 1548200);

      expect(videoMsg.mediaType, 'video');
      expect(videoMsg.durationMs, 45000);

      expect(docMsg.mediaType, 'file');
      expect(docMsg.fileName, 'contract.pdf');

      // Roundtrip
      final desImg = Message.fromJson(imgMsg.toJson());
      expect(desImg.mediaType, 'image');
      expect(desImg.fileName, 'sunset.jpg');

      final desDoc = Message.fromJson(docMsg.toJson());
      expect(desDoc.mediaType, 'file');
      expect(desDoc.fileSize, 320400);
    });

    test('VoiceRecordingResult metadata holds duration, path, and size', () {
      final result = VoiceRecordingResult(
        filePath: '/tmp/vn_test.m4a',
        durationMs: 8400,
        fileSize: 32100,
      );

      expect(result.filePath, '/tmp/vn_test.m4a');
      expect(result.durationMs, 8400);
      expect(result.fileSize, 32100);
    });

    test('Media type deduction from file extensions and mime types', () {
      String getMediaType(String fileName, String contentType) {
        final ext = fileName.split('.').last.toLowerCase();
        if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext) || contentType.startsWith('image/')) {
          return 'image';
        } else if (['mp4', 'mov', 'avi', 'mkv'].contains(ext) || contentType.startsWith('video/')) {
          return 'video';
        } else if (['m4a', 'mp3', 'wav', 'aac', 'ogg'].contains(ext) || contentType.startsWith('audio/')) {
          return 'audio';
        }
        return 'file';
      }

      expect(getMediaType('photo.PNG', 'image/png'), 'image');
      expect(getMediaType('audio_clip.m4a', 'audio/mp4'), 'audio');
      expect(getMediaType('clip.mp4', 'video/mp4'), 'video');
      expect(getMediaType('specs.pdf', 'application/pdf'), 'file');
      expect(getMediaType('archive.zip', 'application/zip'), 'file');
    });

    test('Media message delivery state transitions maintain media integrity', () {
      final base = Message(
        id: 'media-trans-1',
        senderOfflineMeshId: 'alice',
        recipientOfflineMeshId: 'bob',
        content: 'photo.jpg',
        createdAt: DateTime.now(),
        status: 'sending',
        mediaType: 'image',
        mediaPath: '/local/photo.jpg',
        fileName: 'photo.jpg',
        fileSize: 500000,
      );

      final sent = base.copyWith(status: 'sent');
      expect(sent.status, 'sent');
      expect(sent.mediaPath, '/local/photo.jpg');

      final delivered = sent.copyWith(status: 'delivered');
      expect(delivered.status, 'delivered');

      final read = delivered.copyWith(status: 'read');
      expect(read.status, 'read');
      expect(read.mediaType, 'image');
    });
  });
}
