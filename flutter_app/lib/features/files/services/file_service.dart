import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/file_metadata.dart';
import 'file_transfer_transport.dart';
import 'internet_file_transfer_transport.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class FileService {
  final String baseUrl;
  final String jwtToken;
  late final FileTransferTransport _transport;

  FileService({required this.baseUrl, required this.jwtToken}) {
    _transport = InternetFileTransferTransport(baseUrl: baseUrl, jwtToken: jwtToken);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      };

  Future<FileMetadata> createMetadata({
    required String recipientOfflineMeshId,
    required String originalFileName,
    required String contentType,
    required int fileSize,
    String? checksum,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/files/metadata'),
      headers: _headers,
      body: jsonEncode({
        'recipientOfflineMeshId': recipientOfflineMeshId,
        'originalFileName': originalFileName,
        'contentType': contentType,
        'fileSize': fileSize,
        'checksum': checksum,
      }),
    );

    if (response.statusCode == 200) {
      return FileMetadata.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create file metadata: ${response.body}');
    }
  }

  Future<FileMetadata> getMetadata(String fileId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/files/$fileId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return FileMetadata.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load file metadata');
    }
  }

  Future<List<FileMetadata>> getSentFiles() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/files/sent'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      Iterable l = jsonDecode(response.body);
      return List<FileMetadata>.from(l.map((model) => FileMetadata.fromJson(model)));
    } else {
      throw Exception('Failed to load sent files');
    }
  }

  Future<List<FileMetadata>> getReceivedFiles() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/files/received'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      Iterable l = jsonDecode(response.body);
      return List<FileMetadata>.from(l.map((model) => FileMetadata.fromJson(model)));
    } else {
      throw Exception('Failed to load received files');
    }
  }

  Future<void> uploadFile(FileMetadata metadata, File file, Function(double) onProgress) async {
    await _transport.uploadFile(metadata: metadata, file: file, onProgress: onProgress);
  }

  Future<File> downloadFile(FileMetadata metadata, Function(double) onProgress) async {
    final directory = await getApplicationDocumentsDirectory();
    return await _transport.downloadFile(
      metadata: metadata, 
      saveDirectory: directory.path, 
      onProgress: onProgress,
    );
  }
}
