import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/ui/mesh_theme.dart';
import 'package:flutter_app/features/chat/widgets/media_message_bubbles.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'Attachment picker ${brightness.name} fits large text and selects document',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = false;
      await tester.pumpWidget(MaterialApp(
        theme: MeshTheme.build(brightness),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                    body: TextButton(
                  child: const Text('Attach'),
                  onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      useSafeArea: true,
                      builder: (_) => AttachmentPickerSheet(
                          onCameraTap: () {},
                          onGalleryTap: () {},
                          onVideoTap: () {},
                          onDocumentTap: () => selected = true)),
                ))),
      ));
      await tester.tap(find.text('Attach'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Document'));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(find.text('Add to conversation'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
