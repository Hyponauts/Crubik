import 'package:flutter/material.dart';

abstract final class CrubikColors {
  static const background = Color(0xFF0A0C0E);
  static const surface = Color(0xFF121518);
  static const elevated = Color(0xFF181C20);
  static const border = Color(0xFF2A3036);
  static const text = Color(0xFFF2F5F3);
  static const muted = Color(0xFF919A9E);
  static const primaryAccent = Color(0xFFB7F34A);
  static const accentStatusBackground = Color(0x12B7F34A);
  static const accentIconBackground = Color(0x16B7F34A);
  static const navigationIndicator = Color(0x22B7F34A);
  static const reconnectStatusBorder = Color(0x55B7F34A);
  static const activeInputBorder = Color(0x66B7F34A);
  static const secondaryAccent = Color(0xFF58D8DA);
  static const warning = Color(0xFFFFC857);
  static const danger = Color(0xFFFF6B6B);
}

abstract final class CrubikLayout {
  static const desktopBreakpoint = 900.0;
  static const largeTextScale = 1.3;
  static const compactPreparationHeight = 520.0;
  static const desktopAttemptMaxWidth = 1100.0;
  static const desktopAttemptMaxHeight = 620.0;
  static const desktopContentMaxWidth = 800.0;
  static const sessionSidebarWidth = 330.0;
  static const connectionDialogMaxWidth = 520.0;
  static const connectionDialogMaxHeight = 650.0;
}

abstract final class CrubikTheme {
  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: CrubikColors.primaryAccent,
          brightness: Brightness.dark,
          surface: CrubikColors.surface,
        ).copyWith(
          primary: CrubikColors.primaryAccent,
          onPrimary: CrubikColors.background,
          secondary: CrubikColors.secondaryAccent,
          surface: CrubikColors.surface,
          onSurface: CrubikColors.text,
          error: CrubikColors.danger,
          outline: CrubikColors.border,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: CrubikColors.background,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: base.textTheme.displayLarge?.copyWith(
          color: CrubikColors.text,
          fontWeight: FontWeight.w700,
          letterSpacing: -3,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: CrubikColors.text,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: CrubikColors.text,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: CrubikColors.text,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(color: CrubikColors.text),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: CrubikColors.muted,
          height: 1.35,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      dividerColor: CrubikColors.border,
      iconTheme: const IconThemeData(color: CrubikColors.muted),
      appBarTheme: const AppBarTheme(
        backgroundColor: CrubikColors.background,
        foregroundColor: CrubikColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: CrubikColors.background,
        indicatorColor: CrubikColors.navigationIndicator,
        selectedIconTheme: IconThemeData(color: CrubikColors.primaryAccent),
        unselectedIconTheme: IconThemeData(color: CrubikColors.muted),
        selectedLabelTextStyle: TextStyle(
          color: CrubikColors.text,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: CrubikColors.muted),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: CrubikColors.surface,
        selectedItemColor: CrubikColors.primaryAccent,
        unselectedItemColor: CrubikColors.muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: CrubikColors.elevated,
        contentTextStyle: TextStyle(color: CrubikColors.text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
