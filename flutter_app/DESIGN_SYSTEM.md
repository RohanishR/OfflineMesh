# OfflineMesh interface

The Flutter interface uses midnight (#010038), royal navy (#293A80), periwinkle (#537EC5), and orange (#F39422). Orange highlights primary actions; navy anchors navigation and outgoing messages. Shared tokens and typography live in `lib/core/ui/mesh_theme.dart`; reusable surfaces, navigation, empty states, and discovery animation live in `mesh_widgets.dart`.

Settings offers Light, Dark, and System appearance, persisted locally. Glass is restricted to grouped surfaces and navigation. Reduced motion stops the discovery animation and makes glass opaque; high contrast also uses opaque surfaces. Discovery animation follows actual scan state and pauses outside the selected tab.

The current dock contains Chats, Friends, Notes, Files, and Profile. Nearby Devices has been removed in this checkout; the decorative radar component does not constitute a working discovery screen. Shared glass uses brand-tinted gradients with clipped blur only when requested. Navigation selection uses a normalized damped spring over 500 ms, disabled under reduced motion. Dialogs and bottom sheets share 26-pixel corners; primary filled actions use orange with midnight foreground. Chat bubbles use royal navy with white text. Device performance and composite contrast still require visual validation.

The redesigned screens use existing account, friend, messaging, discovery, and file services. Empty lists remain empty; the interface does not manufacture contacts, connection status, typing indicators, or security guarantees. Public-key fingerprints remain available for comparison.

Verification: the Flutter suite includes appearance persistence, narrow navigation with enlarged text, an empty friend list and add dialog, reduced-motion discovery, and login/settings rendering. Live authentication, physical-device discovery, file delivery, and calls still require testing with the backend and real devices. A successful debug APK build does not verify those network flows.

Run `flutter test` for automated checks. Optional local screenshot export uses `flutter test test/mesh_design_test.dart --dart-define=PREVIEW_FONTS=<Flutter SDK>/bin/cache/artifacts/material_fonts`; output is under `build/design-previews`.
