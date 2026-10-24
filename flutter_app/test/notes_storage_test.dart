import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/notes/models/note_item.dart';
import 'package:flutter_app/features/notes/services/notes_service.dart';

void main() {
  test('Concurrent saves keep every note and labels survive reopening', () async {
    final directory = await Directory.systemTemp.createTemp('mesh-notes-test-');
    final service = NotesService.withStorageDirectory(directory);
    await service.initialize();
    await Future.wait(List.generate(12, (i) => service.saveNote(
      NoteItem(id: '$i', title: 'Note $i', labels: ['Work']))));
    final reopened = NotesService.withStorageDirectory(directory);
    await reopened.initialize();
    expect(reopened.currentNotes.length, 12);
    expect(reopened.currentNotes.every((note) => note.labels.contains('Work')), true);
    await directory.delete(recursive: true);
  });

  test('Deleting an imported note never removes an external original', () async {
    final directory = await Directory.systemTemp.createTemp('mesh-media-test-');
    final source = File('${directory.path}/original.jpg');
    await source.writeAsString('fixture');
    final service = NotesService.withStorageDirectory(directory);
    await service.initialize();
    final copy = await service.copyMediaFile(source.path, isVideo: false);
    await service.saveNote(NoteItem(id: 'media', imagePaths: [source.path, copy]));
    await service.deleteNote('media');
    expect(await source.exists(), true);
    expect(await File(copy).exists(), false);
    await directory.delete(recursive: true);
  });
}
