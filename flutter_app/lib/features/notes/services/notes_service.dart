import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/note_item.dart';

class NotesService {
  static final NotesService _instance = NotesService._internal();
  factory NotesService() => _instance;
  NotesService._internal();
  @visibleForTesting
  NotesService.withStorageDirectory(Directory directory) : _storageDirectory = directory;
  Directory? _storageDirectory;

  final List<NoteItem> _cachedNotes = [];
  final StreamController<List<NoteItem>> _notesController =
      StreamController<List<NoteItem>>.broadcast();

  Stream<List<NoteItem>> get notesStream => _notesController.stream;
  List<NoteItem> get currentNotes => List.unmodifiable(_cachedNotes);

  Directory? _notesDir;
  Directory? _mediaDir;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final appDir = (_storageDirectory ?? await getApplicationDocumentsDirectory());
      _notesDir = Directory(p.join(appDir.path, 'notes'));
      if (!await _notesDir!.exists()) {
        await _notesDir!.create(recursive: true);
      }
      _mediaDir = Directory(p.join(appDir.path, 'notes_media'));
      if (!await _mediaDir!.exists()) {
        await _mediaDir!.create(recursive: true);
      }
      await loadNotes();
      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing NotesService: $e');
    }
  }

  Future<File> _getNotesFile() async {
    if (_notesDir == null) {
      final appDir = (_storageDirectory ?? await getApplicationDocumentsDirectory());
      _notesDir = Directory(p.join(appDir.path, 'notes'));
      if (!await _notesDir!.exists()) {
        await _notesDir!.create(recursive: true);
      }
    }
    return File(p.join(_notesDir!.path, 'keep_notes.json'));
  }

  Future<List<NoteItem>> loadNotes() async {
    try {
      final file = await _getNotesFile();
      if (!await file.exists()) {
        _cachedNotes.clear();
        _notify();
        return [];
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        _cachedNotes.clear();
        _notify();
        return [];
      }
      final List<dynamic> jsonList = jsonDecode(content);
      _cachedNotes.clear();
      for (var j in jsonList) {
        try {
          _cachedNotes.add(NoteItem.fromJson(j as Map<String, dynamic>));
        } catch (e) {
          debugPrint('Error parsing note item: $e');
        }
      }
      _sortNotes();
      _notify();
      return List.unmodifiable(_cachedNotes);
    } catch (e) {
      debugPrint('Failed to load notes: $e');
      return [];
    }
  }

  void _sortNotes() {
    _cachedNotes.sort((a, b) {
      // Pinned notes come first
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      // Then newest updated notes
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  Future<void> _pendingWrite = Future.value();

  Future<void> _persist() {
    final snapshot = jsonEncode(_cachedNotes.map((n) => n.toJson()).toList());
    final operation = _pendingWrite.then((_) async {
      final file = await _getNotesFile();
      await file.writeAsString(snapshot, flush: true);
      _notify();
    });
    _pendingWrite = operation.catchError((Object error) {
      debugPrint('Failed to persist notes: $error');
    });
    return operation;
  }

  void _notify() {
    _notesController.add(List.unmodifiable(_cachedNotes));
  }

  Future<void> saveNote(NoteItem note) async {
    note.updatedAt = DateTime.now();
    final index = _cachedNotes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      _cachedNotes[index] = note;
    } else {
      _cachedNotes.add(note);
    }
    _sortNotes();
    await _persist();
  }

  Future<void> deleteNote(String id) async {
    final note = _cachedNotes.firstWhere((n) => n.id == id,
        orElse: () => NoteItem(id: ''));
    if (note.id.isNotEmpty) {
      // Clean up media files
      for (var path in [...note.imagePaths, ...note.videoPaths]) {
        try {
          final file = File(path);
          if (_mediaDir != null &&
              p.isWithin(_mediaDir!.path, file.absolute.path) &&
              await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
      _cachedNotes.removeWhere((n) => n.id == id);
      await _persist();
    }
  }

  Future<void> togglePin(String id) async {
    final index = _cachedNotes.indexWhere((n) => n.id == id);
    if (index != -1) {
      _cachedNotes[index].isPinned = !_cachedNotes[index].isPinned;
      _sortNotes();
      await _persist();
    }
  }

  Future<void> toggleArchive(String id) async {
    final index = _cachedNotes.indexWhere((n) => n.id == id);
    if (index != -1) {
      _cachedNotes[index].isArchived = !_cachedNotes[index].isArchived;
      // If archiving, unpin
      if (_cachedNotes[index].isArchived) {
        _cachedNotes[index].isPinned = false;
      }
      _sortNotes();
      await _persist();
    }
  }

  Future<void> setReminder(String id, DateTime? reminder) async {
    final index = _cachedNotes.indexWhere((n) => n.id == id);
    if (index != -1) {
      _cachedNotes[index].reminderDateTime = reminder;
      _cachedNotes[index].isReminderDone = false;
      await _persist();
    }
  }

  /// Copies an image or video to private notes storage so it is permanently accessible.
  Future<String> copyMediaFile(String originalPath,
      {required bool isVideo}) async {
    try {
      if (_mediaDir == null) {
        final appDir = (_storageDirectory ?? await getApplicationDocumentsDirectory());
        _mediaDir = Directory(p.join(appDir.path, 'notes_media'));
        if (!await _mediaDir!.exists()) {
          await _mediaDir!.create(recursive: true);
        }
      }
      final source = File(originalPath);
      if (!await source.exists()) {
        throw Exception('Source file does not exist: $originalPath');
      }
      final ext = p.extension(originalPath);
      final safeName = '${const Uuid().v4()}$ext';
      final destPath = p.join(_mediaDir!.path, safeName);
      final copied = await source.copy(destPath);
      return copied.path;
    } catch (e) {
      debugPrint('Failed to copy media file: $e');
      rethrow; // Do not claim an attachment was imported when its copy failed.
    }
  }
}
