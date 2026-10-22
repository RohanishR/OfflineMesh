import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class FileViewerService {
  static const MethodChannel _channel = MethodChannel('com.offlinemesh/file_viewer');

  static Future<bool> openFile(String filePath, {String mimeType = '*/*'}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File does not exist: $filePath');
        return false;
      }
      final bool? success = await _channel.invokeMethod<bool>('openFile', {
        'filePath': filePath,
        'mimeType': mimeType,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('Error opening file via platform channel: $e');
      return false;
    }
  }

  static Future<bool> shareFile(String filePath, {String mimeType = '*/*'}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File does not exist: $filePath');
        return false;
      }
      final bool? success = await _channel.invokeMethod<bool>('shareFile', {
        'filePath': filePath,
        'mimeType': mimeType,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('Error sharing file via platform channel: $e');
      return false;
    }
  }
}
