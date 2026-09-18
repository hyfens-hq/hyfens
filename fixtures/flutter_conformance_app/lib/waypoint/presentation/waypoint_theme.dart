import 'package:flutter/material.dart';

import '../application/waypoint_ui_state.dart';
import '../data/waypoint_asset_paths.dart';

final class WaypointColors {
  static const Color canvas = Color(0xFFF5F7F3);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF18342D);
  static const Color muted = Color(0xFF65756F);
  static const Color line = Color(0xFFDDE6E0);
  static const Color accent = Color(0xFFE47755);
  static const Color accentDeep = Color(0xFFB84E32);
  static const Color mint = Color(0xFFB9DED2);
  static const Color lavender = Color(0xFFD9D1EC);
  static const Color sky = Color(0xFFC5DDE8);
  static const Color danger = Color(0xFFB64D4D);

  const WaypointColors._();
}

Color waypointColor(String hex) {
  final normalized = hex.replaceFirst('#', '');
  if (normalized.length != 6) {
    return WaypointColors.mint;
  }
  return Color(int.parse('FF$normalized', radix: 16));
}

ThemeData waypointTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: dark ? WaypointColors.mint : WaypointColors.accent,
        brightness: brightness,
      ).copyWith(
        primary: dark ? WaypointColors.mint : WaypointColors.accentDeep,
        onPrimary: dark ? WaypointColors.ink : Colors.white,
        secondary: dark ? WaypointColors.sky : WaypointColors.ink,
        surface: dark ? const Color(0xFF1E2925) : WaypointColors.paper,
        onSurface: dark ? const Color(0xFFEAF1ED) : WaypointColors.ink,
        outline: dark ? const Color(0xFF3C4D46) : WaypointColors.line,
      );
  final baseText = ThemeData(
    brightness: brightness,
    colorScheme: scheme,
  ).textTheme.apply(fontFamily: WaypointAssetPaths.fontFamily);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF15201C)
        : WaypointColors.canvas,
    canvasColor: dark ? const Color(0xFF15201C) : WaypointColors.canvas,
    dividerColor: scheme.outline,
    fontFamily: WaypointAssetPaths.fontFamily,
    textTheme: baseText.copyWith(
      headlineLarge: baseText.headlineLarge?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
        height: 1.08,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontSize: 27,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: baseText.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: baseText.bodyMedium?.copyWith(height: 1.4),
      labelLarge: baseText.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: baseText.labelMedium?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.7,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF15201C) : WaypointColors.canvas,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF25342E) : WaypointColors.paper,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      hintStyle: TextStyle(
        color: dark ? const Color(0xFFABC0B7) : WaypointColors.muted,
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF1E2925) : WaypointColors.paper,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1E2925) : WaypointColors.paper,
      indicatorColor: dark ? WaypointColors.mint : WaypointColors.mint,
      labelTextStyle: WidgetStatePropertyAll<TextStyle?>(
        baseText.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

ThemeMode waypointThemeMode(WaypointThemeChoice choice) => switch (choice) {
  WaypointThemeChoice.system => ThemeMode.system,
  WaypointThemeChoice.light => ThemeMode.light,
  WaypointThemeChoice.dark => ThemeMode.dark,
};
