import 'package:flutter/material.dart';

/// VS Code Dark Theme Colors
class VSCodeColors {
  // Activity Bar
  static const Color activityBarBackground = Color(0xFF333333);
  static const Color activityBarForeground = Color(0xFFFFFFFF);
  static const Color activityBarInactiveForeground = Color(0xFF858585);
  static const Color activityBarBadge = Color(0xFF007ACC);

  // Side Bar
  static const Color sideBarBackground = Color(0xFF252526);
  static const Color sideBarForeground = Color(0xFFCCCCCC);
  static const Color sideBarBorder = Color(0xFF1E1E1E);

  // Title Bar
  static const Color titleBarBackground = Color(0xFF3C3C3C);
  static const Color titleBarForeground = Color(0xFFCCCCCC);

  // Editor
  static const Color editorBackground = Color(0xFF1E1E1E);
  static const Color editorForeground = Color(0xFFD4D4D4);
  static const Color editorLineNumber = Color(0xFF858585);

  // Tabs
  static const Color tabActiveBackground = Color(0xFF1E1E1E);
  static const Color tabInactiveBackground = Color(0xFF2D2D2D);
  static const Color tabActiveForeground = Color(0xFFFFFFFF);
  static const Color tabInactiveForeground = Color(0xFF969696);
  static const Color tabBorder = Color(0xFF252526);
  static const Color tabActiveBorderTop = Color(0xFF007ACC);

  // Status Bar
  static const Color statusBarBackground = Color(0xFF007ACC);
  static const Color statusBarForeground = Color(0xFFFFFFFF);
  static const Color statusBarDisconnected = Color(0xFF6C6C6C);

  // List/Tree
  static const Color listHoverBackground = Color(0xFF2A2D2E);
  static const Color listActiveSelectionBackground = Color(0xFF094771);
  static const Color listFocusBackground = Color(0xFF062F4A);

  // Input
  static const Color inputBackground = Color(0xFF3C3C3C);
  static const Color inputForeground = Color(0xFFCCCCCC);
  static const Color inputBorder = Color(0xFF3C3C3C);
  static const Color inputFocusBorder = Color(0xFF007ACC);

  // Button
  static const Color buttonBackground = Color(0xFF0E639C);
  static const Color buttonForeground = Color(0xFFFFFFFF);
  static const Color buttonHoverBackground = Color(0xFF1177BB);

  // Accent
  static const Color accent = Color(0xFF007ACC);
  static const Color errorForeground = Color(0xFFF48771);
  static const Color warningForeground = Color(0xFFCCA700);
  static const Color successForeground = Color(0xFF89D185);

  // Scrollbar
  static const Color scrollbarSlider = Color(0xFF424242);
  static const Color scrollbarSliderHover = Color(0xFF4F4F4F);

  // Divider
  static const Color divider = Color(0xFF3C3C3C);

  // Context Menu
  static const Color menuBackground = Color(0xFF3C3C3C);
  static const Color menuForeground = Color(0xFFCCCCCC);
  static const Color menuSeparator = Color(0xFF606060);
}

/// VS Code Theme Data
ThemeData vsCodeDarkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: VSCodeColors.editorBackground,
    primaryColor: VSCodeColors.accent,
    colorScheme: const ColorScheme.dark(
      primary: VSCodeColors.accent,
      secondary: VSCodeColors.accent,
      surface: VSCodeColors.sideBarBackground,
      error: VSCodeColors.errorForeground,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: VSCodeColors.titleBarBackground,
      foregroundColor: VSCodeColors.titleBarForeground,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: VSCodeColors.sideBarBackground,
      elevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: VSCodeColors.divider,
      thickness: 1,
    ),
    iconTheme: const IconThemeData(
      color: VSCodeColors.sideBarForeground,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: VSCodeColors.editorForeground),
      bodyMedium: TextStyle(color: VSCodeColors.editorForeground),
      bodySmall: TextStyle(color: VSCodeColors.sideBarForeground),
      titleMedium: TextStyle(color: VSCodeColors.editorForeground),
      titleSmall: TextStyle(color: VSCodeColors.sideBarForeground),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VSCodeColors.inputBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(0),
        borderSide: const BorderSide(color: VSCodeColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(0),
        borderSide: const BorderSide(color: VSCodeColors.inputFocusBorder),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: VSCodeColors.buttonBackground,
        foregroundColor: VSCodeColors.buttonForeground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0),
        ),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return VSCodeColors.scrollbarSliderHover;
        }
        return VSCodeColors.scrollbarSlider;
      }),
      thickness: WidgetStateProperty.all(10),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: VSCodeColors.menuBackground,
      textStyle: TextStyle(color: VSCodeColors.menuForeground),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: VSCodeColors.sideBarBackground,
      titleTextStyle: TextStyle(
        color: VSCodeColors.editorForeground,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: VSCodeColors.menuBackground,
      contentTextStyle: TextStyle(color: VSCodeColors.menuForeground),
    ),
  );
}
