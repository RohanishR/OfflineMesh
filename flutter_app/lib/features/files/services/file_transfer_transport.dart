import 'dart:io';
import '../models/file_metadata.dart';

abstract class FileTransferTransport {
  Future<void> uploadFile({
    required FileMetadata metadata,
    required File file,
    required Function(double) onProgress,
  });

  Future<File> downloadFile({
    required FileMetadata metadata,
    required String saveDirectory,
    required Function(double) onProgress,
  });
}
