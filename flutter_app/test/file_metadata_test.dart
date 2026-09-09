import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/files/models/file_metadata.dart';

void main() {
  group('FileMetadata', () {
    test('fromJson and toJson', () {
      final json = {
        'id': 'b1c67e89-1234-4a8b-90f6-ab1234567890',
        'senderOfflineMeshId': 'SENDER123',
        'recipientOfflineMeshId': 'RECIPIENT123',
        'originalFileName': 'test.txt',
        'contentType': 'text/plain',
        'fileSize': 1024,
        'checksum': 'abcd1234efgh5678',
        'status': 'PENDING',
        'createdAt': '2023-01-01T10:00:00.000Z',
        'updatedAt': null,
      };

      final metadata = FileMetadata.fromJson(json);

      expect(metadata.id, 'b1c67e89-1234-4a8b-90f6-ab1234567890');
      expect(metadata.originalFileName, 'test.txt');
      expect(metadata.fileSize, 1024);

      final outJson = metadata.toJson();

      expect(outJson['id'], 'b1c67e89-1234-4a8b-90f6-ab1234567890');
      expect(outJson['createdAt'], '2023-01-01T10:00:00.000Z');
      expect(outJson['updatedAt'], null);
    });
  });
}
