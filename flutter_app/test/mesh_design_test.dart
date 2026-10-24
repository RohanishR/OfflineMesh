import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app/core/ui/mesh_widgets.dart';
import 'package:flutter_app/core/models/user.dart';
import 'package:flutter_app/core/services/friend_service.dart';
import 'package:flutter_app/core/network/auth_service.dart';
import 'package:flutter_app/features/auth/screens/login_screen.dart';
import 'package:flutter_app/features/friends/screens/friends_list_screen.dart';
import 'package:flutter_app/features/profile/screens/settings_screen.dart';

class _Friends extends FriendService {
  _Friends() : super(baseUrl: '', jwtToken: '');
  @override
  Future<List<UserProfile>> getFriends() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Glass becomes opaque without a blur under reduced motion',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: MeshTheme.build(Brightness.dark),
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(
            body: GlassSurface(blur: true, child: Text('Real content'))),
      ),
    ));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Real content'), findsOneWidget);
  });

  test('Navigation spring stays bounded and reaches its destination', () {
    const curve = MeshSpringCurve();
    expect(curve.transform(0), 0);
    expect(curve.transform(1), 1);
    var previous = 0.0;
    for (var i = 1; i <= 100; i++) {
      final value = curve.transform(i / 100);
      expect(value, inInclusiveRange(previous, 1.0));
      previous = value;
    }
  });

  testWidgets('Appearance selection persists across a new controller',
      (tester) async {
    final controller = AppearanceController();
    await controller.select(ThemeMode.dark);
    final restored = AppearanceController();
    await restored.load();
    expect(restored.value, ThemeMode.dark);
    controller.dispose();
    restored.dispose();
  });

  testWidgets('Dock selects all five tabs at narrow width and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var index = 0;
    await tester.pumpWidget(MaterialApp(
        theme: MeshTheme.build(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(1.8),
              disableAnimations: true),
          child: StatefulBuilder(
              builder: (context, update) => Scaffold(
                  bottomNavigationBar: GlassNavigationBar(
                      index: index,
                      onChanged: (v) => update(() => index = v)))),
        )));
    await tester.tap(find.text('Profile'));
    await tester.pump();
    expect(index, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty friends has a working add dialog, no fabricated people',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: MeshTheme.build(Brightness.dark),
        home: FriendsListScreen(friendService: _Friends())));
    await tester.pumpAndSettle();
    expect(find.text('Make your first connection'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add friend'));
    await tester.pumpAndSettle();
    expect(find.text('Enter OfflineMesh ID'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Enter OfflineMesh ID'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduced motion radar settles while discovery is active',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: DiscoveryRadar(scanning: true)))));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Design previews render light and dark with actual UI widgets',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Optional local preview export. CI does not depend on a machine-specific font path.
    const fonts = String.fromEnvironment('PREVIEW_FONTS');
    if (fonts.isNotEmpty) {
      await tester.runAsync(() async {
        final loader = FontLoader('Ahem')
          ..addFont(Future.value(ByteData.sublistView(
              File('$fonts/roboto-regular.ttf').readAsBytesSync())));
        await loader.load();
        final roboto = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(
              File('$fonts/roboto-regular.ttf').readAsBytesSync())));
        await roboto.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(
              File('$fonts/materialicons-regular.otf').readAsBytesSync())));
        await icons.load();
      });
    }
    for (final brightness in Brightness.values) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: MeshTheme.build(brightness),
          home: RepaintBoundary(
              key: key,
              child: LoginScreen(
                  authService: AuthService(baseUrl: 'http://localhost')))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (fonts.isNotEmpty) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/design-previews').create(recursive: true);
          await File('build/design-previews/login-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.pumpWidget(MaterialApp(
        theme: MeshTheme.build(Brightness.dark),
        home: SettingsScreen(
            authService: AuthService(baseUrl: 'http://localhost'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(AppearanceController.instance.value, ThemeMode.dark);
    expect(tester.takeException(), isNull);
  });
}
