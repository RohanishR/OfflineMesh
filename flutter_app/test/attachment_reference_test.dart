import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/models/message.dart';

void main() {
  test(
      'Attachment ID survives persistence and status updates independently of message ID',
      () {
    final message = Message(
        id: 'message-1',
        senderOfflineMeshId: 'sender',
        content: 'voice.m4a',
        createdAt: DateTime(2026),
        mediaType: 'audio',
        attachmentId: 'file-2');
    final restored =
        Message.fromJson(message.toJson()).copyWith(status: 'read');
    expect(restored.id, 'message-1');
    expect(restored.attachmentId, 'file-2');
    expect(
        Message.fromJson({...message.toJson()}..remove('attachmentId'))
            .attachmentId,
        isNull);
  });
}
