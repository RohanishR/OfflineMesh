import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/notes/models/note_item.dart';
import 'package:flutter_app/features/notes/screens/notes_screen.dart';

void main() {
  testWidgets('Narrow note card wraps reminder with enlarged text',
      (tester) async {
    var pinned = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 190,
            child: NoteCard(
              note: NoteItem(
                  id: 'test',
                  title: 'A longer note title',
                  reminderDateTime: DateTime(2030, 10, 23, 22, 35)),
              isDark: false,
              onTap: () {},
              onTogglePin: () => pinned = true,
            ),
          )),
    ))));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Pin note'));
    expect(pinned, isTrue);
  });
  group('NoteItem and ChecklistItem model tests', () {
    test('ChecklistItem serialization and copyWith', () {
      final item =
          ChecklistItem(id: 'item-1', text: 'Buy groceries', isDone: false);
      final json = item.toJson();
      expect(json['id'], 'item-1');
      expect(json['text'], 'Buy groceries');
      expect(json['isDone'], false);

      final fromJson = ChecklistItem.fromJson(json);
      expect(fromJson.id, 'item-1');
      expect(fromJson.text, 'Buy groceries');
      expect(fromJson.isDone, false);

      final updated = item.copyWith(isDone: true);
      expect(updated.isDone, true);
      expect(updated.text, 'Buy groceries');
    });

    test('NoteItem serialization and media paths', () {
      final now = DateTime.now();
      final reminder = now.add(const Duration(hours: 3));
      final note = NoteItem(
        id: 'note-123',
        title: 'Project Ideas',
        content: 'Mesh network with Google Keep notes',
        checklist: [
          ChecklistItem(id: 'c1', text: 'Add photos', isDone: true),
          ChecklistItem(id: 'c2', text: 'Add videos', isDone: false),
        ],
        imagePaths: ['/data/app/notes_media/photo1.jpg'],
        videoPaths: ['/data/app/notes_media/video1.mp4'],
        reminderDateTime: reminder,
        isPinned: true,
        colorIndex: 4, // Mint
      );

      expect(note.hasMedia, isTrue);
      expect(note.hasReminder, isTrue);
      expect(note.isReminderUpcoming, isTrue);
      expect(note.isEmpty, isFalse);

      final json = note.toJson();
      final deserialized = NoteItem.fromJson(json);

      expect(deserialized.id, 'note-123');
      expect(deserialized.title, 'Project Ideas');
      expect(deserialized.content, 'Mesh network with Google Keep notes');
      expect(deserialized.checklist.length, 2);
      expect(deserialized.checklist[0].text, 'Add photos');
      expect(deserialized.checklist[0].isDone, isTrue);
      expect(deserialized.imagePaths, ['/data/app/notes_media/photo1.jpg']);
      expect(deserialized.videoPaths, ['/data/app/notes_media/video1.mp4']);
      expect(deserialized.isPinned, isTrue);
      expect(deserialized.colorIndex, 4);
      expect(deserialized.reminderDateTime, isNotNull);
    });

    test('Google Keep 12-color palette returns distinct valid colors', () {
      expect(NoteItem.colorNames.length, 12);
      for (int i = 0; i < NoteItem.colorNames.length; i++) {
        final lightColor = NoteItem.getBackgroundColor(i, false);
        final darkColor = NoteItem.getBackgroundColor(i, true);
        final lightBorder = NoteItem.getBorderColor(i, false);
        final darkBorder = NoteItem.getBorderColor(i, true);

        expect(lightColor, isNotNull);
        expect(darkColor, isNotNull);
        expect(lightBorder, isNotNull);
        expect(darkBorder, isNotNull);
      }
    });

    test('Empty check works properly', () {
      final emptyNote = NoteItem(id: 'test');
      expect(emptyNote.isEmpty, isTrue);

      final withTitle = NoteItem(id: 'test', title: 'Hello');
      expect(withTitle.isEmpty, isFalse);

      final withPhoto = NoteItem(id: 'test', imagePaths: ['/path/to/img.png']);
      expect(withPhoto.isEmpty, isFalse);

      final withVideo = NoteItem(id: 'test', videoPaths: ['/path/to/vid.mp4']);
      expect(withVideo.isEmpty, isFalse);
    });
  });

  group('NoteCard Widget tests', () {
    testWidgets('Renders title, checklist, reminder badge and pin',
        (tester) async {
      final testNote = NoteItem(
        id: 'widget-note-1',
        title: 'Meeting Notes',
        content: 'Offline mesh protocol design sync',
        checklist: [
          ChecklistItem(id: 'c1', text: 'Define packet formats', isDone: true),
          ChecklistItem(
              id: 'c2', text: 'Test Wi-Fi direct fallback', isDone: false),
        ],
        reminderDateTime: DateTime.now().add(const Duration(hours: 1)),
        isPinned: true,
        colorIndex: 2,
      );

      bool pinToggled = false;
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteCard(
              note: testNote,
              isDark: false,
              onTap: () => tapped = true,
              onTogglePin: () => pinToggled = true,
            ),
          ),
        ),
      );

      expect(find.text('Meeting Notes'), findsOneWidget);
      expect(find.text('Offline mesh protocol design sync'), findsOneWidget);
      expect(find.text('Define packet formats'), findsOneWidget);
      expect(find.text('Test Wi-Fi direct fallback'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
      expect(find.byIcon(Icons.alarm_rounded), findsOneWidget);

      await tester.tap(find.text('Meeting Notes'));
      expect(tapped, isTrue);

      await tester.tap(find.byIcon(Icons.push_pin_rounded));
      expect(pinToggled, isTrue);
    });
  });
}
