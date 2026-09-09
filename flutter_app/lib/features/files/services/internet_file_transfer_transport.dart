import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/file_metadata.dart';
import 'file_transfer_transport.dart';
import 'package:path/path.dart' as p;

class InternetFileTransferTransport implements FileTransferTransport {
  final String baseUrl;
  final String jwtToken;

  InternetFileTransferTransport({required this.baseUrl, required this.jwtToken});

  @override
  Future<void> uploadFile({
    required FileMetadata metadata,
    required File file,
    required Function(double) onProgress,
  }) async {
    final uri = Uri.parse('$baseUrl/api/files/${metadata.id}/upload');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $jwtToken'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();

    // In a real-world scenario, we'd use a custom ByteStream to track upload progress accurately.
    // Since http.MultipartRequest doesn't support fine-grained upload progress easily without 
    // overriding ByteStream, we simulate progress based on response completion for now.
    
    if (response.statusCode == 200) {
      onProgress(1.0);
    } else {
      throw Exception('Failed to upload file: ${response.statusCode}');
    }
  }

  @override
  Future<File> downloadFile({
    required FileMetadata metadata,
    required String saveDirectory,
    required Function(double) onProgress,
  }) async {
    final uri = Uri.parse('$baseUrl/api/files/${metadata.id}/download');
    final request = http.Request('GET', uri)
      ..headers['Authorization'] = 'Bearer $jwtToken';

    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('Failed to download file: ${response.statusCode}');
    }

    final file = File(p.join(saveDirectory, metadata.originalFileName));
    final sink = file.openWrite();
    
    final contentLength = response.contentLength ?? metadata.fileSize;
    int downloaded = 0;

    await for (final chunk in response.stream) {
      sink.add(chunk);
      downloaded += chunk.length;
      if (contentLength > 0) {
        onProgress(downloaded / contentLength);
      }
    }

    await sink.flush();
    await sink.close();

    return file;
  }
}
