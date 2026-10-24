import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

class VoiceNoteService {
  AudioRecorder? _recorder;
  AudioPlayer? _player;

  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;

  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;

  AudioPlayer get player {
    _player ??= AudioPlayer();
    return _player!;
  }

  /// Request microphone permission
  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Check if microphone permission is granted
  Future<bool> hasMicrophonePermission() async {
    return await Permission.microphone.isGranted;
  }

  /// Start recording voice note
  Future<bool> startRecording() async {
    try {
      _recorder ??= AudioRecorder();

      final hasPermission = await _recorder!.hasPermission();
      if (!hasPermission) {
        final granted = await requestMicrophonePermission();
        if (!granted) return false;
      }

      final tempDir = await getTemporaryDirectory();
      final voiceDir = Directory(p.join(tempDir.path, 'voice_notes'));
      if (!await voiceDir.exists()) {
        await voiceDir.create(recursive: true);
      }

      final fileName = 'VN_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final filePath = p.join(voiceDir.path, fileName);
      _currentRecordingPath = filePath;
      _recordingStartTime = DateTime.now();

      await _recorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      _isRecording = true;
      return true;
    } catch (e) {
      debugPrint('VoiceNoteService.startRecording error: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      return false;
    }
  }

  /// Stop recording and return recording result
  Future<VoiceRecordingResult?> stopRecording() async {
    if (!_isRecording || _recorder == null) return null;

    try {
      final path = await _recorder!.stop();
      _isRecording = false;

      final durationMs = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inMilliseconds
          : 0;

      final recordedPath = path ?? _currentRecordingPath;
      if (recordedPath == null) return null;

      final file = File(recordedPath);
      if (!await file.exists()) return null;

      final fileSize = await file.length();
      if (fileSize < 200 || durationMs < 500) {
        // Discard accidental clicks under 0.5s or empty files
        if (await file.exists()) await file.delete();
        return null;
      }

      return VoiceRecordingResult(
        filePath: recordedPath,
        durationMs: durationMs,
        fileSize: fileSize,
      );
    } catch (e) {
      debugPrint('VoiceNoteService.stopRecording error: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Cancel current recording and cleanup file
  Future<void> cancelRecording() async {
    if (_recorder != null && _isRecording) {
      try {
        final path = await _recorder!.stop();
        _isRecording = false;
        final targetPath = path ?? _currentRecordingPath;
        if (targetPath != null) {
          final file = File(targetPath);
          if (await file.exists()) {
            await file.delete();
          }
        }
      } catch (e) {
        debugPrint('VoiceNoteService.cancelRecording error: $e');
      }
    }
    _currentRecordingPath = null;
    _recordingStartTime = null;
  }

  /// Play audio file
  Future<void> playVoiceNote(String filePath, {double speed = 1.0}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('Voice note file not found: $filePath');
        return;
      }
      await player.stop();
      await player.setPlaybackRate(speed);
      await player.play(DeviceFileSource(filePath));
    } catch (e) {
      debugPrint('VoiceNoteService.playVoiceNote error: $e');
    }
  }

  /// Pause playback
  Future<void> pause() async {
    await _player?.pause();
  }

  /// Resume playback
  Future<void> resume() async {
    await _player?.resume();
  }

  /// Stop playback
  Future<void> stop() async {
    await _player?.stop();
  }

  /// Seek playback
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  /// Set playback speed (e.g. 1.0, 1.5, 2.0)
  Future<void> setPlaybackRate(double rate) async {
    await _player?.setPlaybackRate(rate);
  }

  void dispose() {
    _recorder?.dispose();
    _player?.dispose();
    _recorder = null;
    _player = null;
  }
}

class VoiceRecordingResult {
  final String filePath;
  final int durationMs;
  final int fileSize;

  VoiceRecordingResult({
    required this.filePath,
    required this.durationMs,
    required this.fileSize,
  });
}
