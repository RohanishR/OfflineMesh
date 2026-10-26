import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class FileViewerService {
  static const MethodChannel _channel =
      MethodChannel('com.offlinemesh/file_viewer');

  static String mimeFor(String path) {
    final extension = path.split('.').last.toLowerCase();
    return const {
          'pdf': 'application/pdf',
          'txt': 'text/plain',
          'csv': 'text/csv',
          'doc': 'application/msword',
          'docx':
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'xls': 'application/vnd.ms-excel',
          'xlsx':
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'ppt': 'application/vnd.ms-powerpoint',
          'pptx':
              'application/vnd.openxmlformats-officedocument.presentationml.presentation',
          'mp4': 'video/mp4',
          'mkv': 'video/x-matroska',
          'mov': 'video/quicktime',
          'avi': 'video/x-msvideo',
          'webm': 'video/webm',
          '3gp': 'video/3gpp',
          'mp3': 'audio/mpeg',
          'm4a': 'audio/mp4',
          'wav': 'audio/wav',
          'aac': 'audio/aac',
          'ogg': 'audio/ogg',
          'opus': 'audio/opus',
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'png': 'image/png',
          'gif': 'image/gif',
          'webp': 'image/webp',
          'zip': 'application/zip',
          'rar': 'application/x-rar-compressed',
          '7z': 'application/x-7z-compressed',
        }[extension] ??
        '*/*';
  }

  static Future<bool> openFile(String filePath,
      {String mimeType = '*/*'}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File does not exist: $filePath');
        return false;
      }
      final resolvedMime = mimeType == '*/*' ? mimeFor(filePath) : mimeType;
      final bool? success = await _channel.invokeMethod<bool>('openFile', {
        'filePath': filePath,
        'mimeType': resolvedMime,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('Error opening file via platform channel: $e');
      return false;
    }
  }

  static Future<bool> shareFile(String filePath,
      {String mimeType = '*/*'}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File does not exist: $filePath');
        return false;
      }
      final resolvedMime = mimeType == '*/*' ? mimeFor(filePath) : mimeType;
      final bool? success = await _channel.invokeMethod<bool>('shareFile', {
        'filePath': filePath,
        'mimeType': resolvedMime,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('Error sharing file via platform channel: $e');
      return false;
    }
  }

  static Future<bool> saveToDownloads(String filePath,
      {String? fileName, String mimeType = '*/*'}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File does not exist: $filePath');
        return false;
      }
      final resolvedMime = mimeType == '*/*' ? mimeFor(filePath) : mimeType;
      final name = fileName ?? file.path.split(Platform.pathSeparator).last;
      final bool? success = await _channel.invokeMethod<bool>('saveToDownloads', {
        'filePath': filePath,
        'fileName': name,
        'mimeType': resolvedMime,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('Error saving file to Downloads via platform channel: $e');
      return false;
    }
  }
}
