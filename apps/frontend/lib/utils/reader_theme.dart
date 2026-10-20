import 'package:flutter/material.dart';

ThemeData readerTheme({Brightness brightness = Brightness.dark}) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF1565C0),
        brightness: brightness,
      ).copyWith(
        surface: dark ? const Color(0xFF2D2D2D) : const Color(0xFFFAFAFA),
        onSurface: dark ? const Color(0xFFEEEEEE) : const Color(0xFF202020),
      );
  final cursor = WidgetStateProperty.resolveWith<MouseCursor>(
    (states) => states.contains(WidgetState.disabled)
        ? SystemMouseCursors.basic
        : SystemMouseCursors.click,
  );
  final foreground = WidgetStateProperty.resolveWith<Color>(
    (states) => states.contains(WidgetState.disabled)
        ? colors.onSurface.withValues(alpha: .38)
        : colors.primary,
  );
  final overlay = WidgetStateProperty.resolveWith<Color?>(
    (states) => states.contains(WidgetState.focused)
        ? colors.primary.withValues(alpha: .24)
        : states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed)
        ? colors.primary.withValues(alpha: .12)
        : null,
  );
  final style = ButtonStyle(
    mouseCursor: cursor,
    foregroundColor: foreground,
    overlayColor: overlay,
  );
  return ThemeData(
    colorScheme: colors,
    useMaterial3: true,
    scaffoldBackgroundColor: dark ? const Color(0xFF212121) : colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      elevation: 2,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      hintStyle: TextStyle(color: colors.onSurfaceVariant),
    ),
    textButtonTheme: TextButtonThemeData(style: style),
    outlinedButtonTheme: OutlinedButtonThemeData(style: style),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: style.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: .38)
              : colors.onPrimary,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: .12)
              : colors.primary,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: style),
    listTileTheme: ListTileThemeData(
      mouseCursor: cursor,
      iconColor: colors.onSurface,
      selectedTileColor: colors.primaryContainer,
    ),
    iconTheme: IconThemeData(color: colors.onSurface),
    textTheme: TextTheme(
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: colors.onSurface,
      ),
      bodyMedium: TextStyle(fontSize: 14, color: colors.onSurface),
    ),
  );
}
