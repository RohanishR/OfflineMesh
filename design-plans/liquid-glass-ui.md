# Cohesive OfflineMesh glass interface

Written against: fa6cf810fa54492a5b60e9ff7205d99c461a26d7, with substantial uncommitted changes inspected on 2026-10-24. Re-read the working tree before implementation. Status: implementation plan, not implemented or visually validated.

## Evidence chain

- Surface: Flutter Android application; main.dart applies MeshTheme; HomeScreen renders Chats, Friends, Notes, Files, and Profile through an IndexedStack and GlassNavigationBar. Profile opens Settings.
- Design evidence: user explicitly requests an Apple Liquid Glass-inspired design using Midnight Navy #010038, Royal Navy #293A80, Periwinkle Blue #537EC5, and Vibrant Orange #F39422, accessible light/dark modes, spring motion, real data, and unchanged functionality.
- Owners: flutter_app/lib/core/ui/mesh_theme.dart owns MeshColors, MeshTheme, and AppearanceController. flutter_app/lib/core/ui/mesh_widgets.dart owns GlassSurface, GlassNavigationBar, MeshPage, MeshSearch, MeshAvatar, and state views.
- Current discrepancy against the newly requested palette: chat_screen.dart uses explicit WhatsApp green backgrounds and action buttons; chat_list_screen.dart uses green selection styling. Existing shared surfaces already provide clipping, blur, and opaque reduced-motion/high-contrast fallbacks.
- Nearby scope limitation: flutter_app/lib/features/discovery/screens/nearby_devices_screen.dart contains only a removal notice. HomeScreen has Notes in that position. Do not replace Notes or invent discovery results.
- Uncertainty: source inspection does not verify rendering, performance, device accessibility, or network functionality. Existing documentation predates some current chat styling.

## Design decision

Extend the current shared Flutter UI instead of adding a parallel design system. Use frosted glass for navigation and grouped surfaces, solid readable message/content surfaces, restrained orange primary actions, and navy/periwinkle depth. Preserve Android back navigation and native input behavior; this is an inspired treatment, not an iOS shell.

## Reuse

- Keep all four MeshColors brand values exact. White and opacity/compositing are neutral treatments, not additional brand colors.
- Retain MeshTheme typography and existing radii: GlassSurface 26, inputs 20, buttons 18, navigation selection 22. Retain existing 24-pixel page insets where already used.
- Keep AppearanceController persistence and its Follow system, Light, Dark options.
- Extend GlassSurface in place with explicit navigation/card treatments only if needed; do not introduce a second glass component.
- Exemplar: profile_screen.dart groups identity, fingerprint, and appearance links using existing GlassSurface and theme typography.

## Changes

1. flutter_app/lib/core/ui/mesh_theme.dart
   - Centralize surface roles and selected/action colors. Light mode uses white surfaces over a lightly navy-tinted canvas; dark mode uses Midnight Navy with Royal Navy-tinted raised surfaces. Use Periwinkle Blue for secondary emphasis and Vibrant Orange for primary actions with Midnight Navy foreground.
   - Keep semantic error/success treatment distinct from decorative brand styling; include text/icon meaning, never color alone. Measure final contrast after compositing rather than assuming the palette guarantees it.
   - Preserve existing typography and appearance persistence; avoid font downloads or new dependencies.

2. flutter_app/lib/core/ui/mesh_widgets.dart
   - Extend GlassSurface's existing clipped gradient, fine border, and blur. Keep backdrop blur confined to navigation/header regions; scrolling cards should use tinted fills without individual expensive blurs.
   - Preserve opaque fallback when high contrast or disableAnimations is enabled. Ensure text is not faded along with its container.
   - Evolve GlassNavigationBar into the shared frosted dock, retaining all current destinations and selected semantics. Use one shared spring-driven selection indicator; do not animate every list item indefinitely.
   - Add shared motion parameters here or in the existing theme owner: proposed initial spring mass 1, stiffness 300, damping 30, validated on Android before acceptance. Settle directly under reduced motion. Interrupt transitions smoothly on rapid taps.
   - Retain 48 logical-pixel touch targets. Allow labels/content to expand at large text sizes rather than clipping them into fixed heights.

3. flutter_app/lib/features/home/screens/home_screen.dart
   - Preserve IndexedStack state, TickerMode, all five current tabs, and existing services. Keep dock clear of system gesture insets and content. If extending the body behind the dock, explicitly reserve scroll padding for its measured height.
   - Do not replace Notes with a fabricated Nearby destination.

4. flutter_app/lib/features/chat/screens/chat_list_screen.dart and chat_screen.dart
   - Replace decorative WhatsApp greens with shared brand roles: orange compose/send actions, navy outgoing bubbles, periwinkle selection emphasis. Use matching readable foregrounds in both modes; leave media colors unchanged.
   - Retain search, filters, unread counts, groups, drafts, reactions, replies, editing/deletion, forwarding, notes, attachment/voice controls, calling, and security dialogs exactly as implemented.
   - Keep identity and status readable in narrow headers; use the existing overflow menu for secondary actions when space is insufficient. Keep call actions discoverable with labels/tooltips.
   - Scope search copy to what is actually searched. Display online status only from supported peer presence/discovery evidence, never from the mere existence of a login token. This is a presentation correction, not a networking redesign.
   - Give message actions and sheets the same theme and surface treatment. Do not insert demo messages, typing animations, or guaranteed encryption claims.

5. flutter_app/lib/features/friends/screens/friends_list_screen.dart
   - Restyle existing GlassSurface rows through shared owners. Maintain a clear name/ID hierarchy, wrapping long IDs and preserving real friend/add/retry actions. Apply subtle selection/press feedback only to actionable controls.

6. flutter_app/lib/features/files/screens/file_list_screen.dart
   - Apply shared card, search, icon, and action roles. Preserve actual filenames, metadata, upload progress, selection and transfer actions. Long filenames must wrap or truncate with access to the complete name.
   - Never replace indeterminate work with invented progress percentages or mark transfers complete for visual polish.

7. flutter_app/lib/features/profile/screens/profile_screen.dart and settings_screen.dart
   - Retain current identity/security grouping, copy actions, key rotation, server configuration, account actions, and appearance controls. Use shared cards, typography, spacing, and semantic destructive-action styling.
   - Animate appearance changes without flashing unreadable intermediate foreground/background pairs. Respect system motion settings.

8. flutter_app/lib/features/discovery/screens/nearby_devices_screen.dart
   - No implementation in this UI scope: there is no live screen to restyle. A separate functional restoration decision and verified discovery integration are required first. Preserve existing Notes functionality and its navigation.

## Scope

- Inherit: live screens consuming MeshTheme and shared widgets, including Notes and authentication.
- Verify: group chat, notes editor, server dialog, call screen, and authentication for inherited theme regressions even though they are not redesigned here.
- Exclude: backend, transport changes, service duplication, dependency upgrades, sample data, reintroducing removed Bluetooth/BLE code, and changing account/security behavior.

## Validation

- Product: use existing real/test fixtures to verify chat search/actions, notes saving, friend flows, file progress/actions, profile copy, appearance persistence, server configuration, and back navigation retain their behavior. Report any existing failures separately.
- Interface: capture light/dark/system views at 360 and 412 logical-pixel widths and a wider layout; exercise 200% text, long names/IDs/filenames, empty/loading/error/populated states, keyboard open, TalkBack, reduced motion, and high contrast. Check 4.5:1 normal-text contrast and 3:1 large-text/control contrast on actual composite backgrounds.
- Motion/performance: profile on a physical Android device with real lists and rapid tab changes. Check raster/UI frame timing against the device refresh interval, lifecycle pause behavior, and blur cost. No production-quality claim before these checks.
- System: all affected controls use existing owners; no duplicated navigation or glass framework. No real content obscured by dock, keyboard, or system bars.
- Repository: from flutter_app run `flutter analyze`, `flutter test`, and `flutter build apk --debug`. Record actual results and distinguish baseline failures from introduced ones. Extend existing test/mesh_design_test.dart for theme inheritance, narrow navigation, large text, and reduced motion where needed; do not regenerate snapshots merely to hide regressions.

## Stop conditions

- Reconcile concurrent working-tree changes before edits; never revert unrelated modifications.
- Stop only the Nearby portion if the screen remains removed; continue independent visual work on existing screens.
- If implementation requires changing a service contract or real behavior, separate that work from the visual redesign and document why.

## Design documentation

- After implementation acceptance and validation, update flutter_app/DESIGN_SYSTEM.md with actual glass roles, brand roles, motion behavior, fallbacks, current navigation, and verified device results. Do not claim future validation as completed.
