import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class MeshColors {
  static const midnight = Color(0xFF010038);
  static const navy = Color(0xFF293A80);
  static const blue = Color(0xFF537EC5);
  static const orange = Color(0xFFF39422);
  static const porcelain = Color(0xFFF5F7FC);
}

/// Appearance is presentation state; it never changes transport or account state.
class AppearanceController extends ValueNotifier<ThemeMode> {
  AppearanceController() : super(ThemeMode.system);
  static final instance = AppearanceController();
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('appearance');
    value = ThemeMode.values.where((m) => m.name == saved).firstOrNull ??
        ThemeMode.system;
  }

  Future<void> select(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('appearance', mode.name)) {
      throw StateError('Appearance could not be saved');
    }
    value = mode;
  }
}

abstract final class MeshTheme {
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(seedColor: MeshColors.navy, brightness: brightness)
            .copyWith(
      primary: dark ? const Color(0xFFB5CCF4) : MeshColors.navy,
      onPrimary: dark ? MeshColors.midnight : Colors.white,
      secondary: MeshColors.blue,
      tertiary: MeshColors.orange,
      surface: dark ? const Color(0xFF11143F) : Colors.white,
      onSurface: dark ? const Color(0xFFF5F7FC) : MeshColors.midnight,
      onSurfaceVariant:
          dark ? const Color(0xFFB8C5E1) : const Color(0xFF515D7B),
      outlineVariant: dark ? const Color(0xFF303D64) : const Color(0xFFDFE5F1),
      error: dark ? MeshColors.orange : const Color(0xFF804800),
      onError: dark ? MeshColors.midnight : Colors.white,
    );
    final base = ThemeData(
        useMaterial3: true, colorScheme: scheme, brightness: brightness);
    return base.copyWith(
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      scaffoldBackgroundColor:
          dark ? MeshColors.midnight : MeshColors.porcelain,
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: TextStyle(
                fontSize: 34,
                height: 1.15,
                letterSpacing: -1.4,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface),
            headlineMedium: TextStyle(
                fontSize: 28,
                height: 1.2,
                letterSpacing: -.8,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface),
            titleLarge: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w600,
                letterSpacing: -.4,
                color: scheme.onSurface),
            titleMedium: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface),
            bodyMedium:
                TextStyle(fontSize: 14, height: 1.5, color: scheme.onSurface),
            bodySmall: TextStyle(
                fontSize: 12, height: 1.4, color: scheme.onSurfaceVariant),
          )
          .apply(fontFamily: 'Roboto'),
      appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          foregroundColor: scheme.onSurface),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: scheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: MeshColors.blue, width: 2)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: MeshColors.orange,
          foregroundColor: MeshColors.midnight,
          elevation: 3,
          shape: StadiumBorder()),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: MeshColors.orange,
              foregroundColor: MeshColors.midnight,
              minimumSize: const Size(48, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)))),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              elevation: 0,
              foregroundColor: scheme.primary,
              backgroundColor: scheme.surface,
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)))),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MeshColors.navy,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
      dividerTheme:
          DividerThemeData(color: scheme.outlineVariant, thickness: .7),
    );
  }
}
