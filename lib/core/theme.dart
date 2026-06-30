// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

const _neon            = Color(0xFFD95D39); // Terracotta — primær accent
const _bgBlack         = Color(0xFF121110); // Scaffold-baggrund (jordsort)
const _surfaceDark     = Color(0xFF1C1A18); // Card / panel (chokolade-grå)
const _surfaceElevated = Color(0xFF252220); // Inputs, chips
const _borderSubtle    = Color(0xFF2A2624); // tynde mørke kanter
const _textPrimary     = Color(0xFFF4F0E6); // varm off-white
const _textSecondary   = Color(0xFFA0988E); // lys grå (varm tone)
const _textMuted       = Color(0xFF6B645D); // hint / disabled

ThemeData _buildClayCourt() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _neon,
    onPrimary: Colors.black,
    secondary: _neon,
    onSecondary: Colors.black,
    error: Color(0xFFEF4444),
    onError: Colors.white,
    surface: _surfaceDark,
    onSurface: _textPrimary,
    surfaceContainerLowest: _bgBlack,
    surfaceContainerLow: _surfaceDark,
    surfaceContainer: _surfaceDark,
    surfaceContainerHigh: _surfaceElevated,
    surfaceContainerHighest: _surfaceElevated,
    onSurfaceVariant: _textSecondary,
    primaryContainer: Color(0xFF4A1F12),
    onPrimaryContainer: _neon,
    outline: _borderSubtle,
    outlineVariant: _borderSubtle,
    inverseSurface: _textPrimary,
    onInverseSurface: _bgBlack,
    inversePrimary: Color(0xFF7A3220),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: _bgBlack,
    canvasColor: _bgBlack,
    dialogTheme: const DialogThemeData(
      backgroundColor: _surfaceDark,
      elevation: 0,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _bgBlack,
      foregroundColor: _textPrimary,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: _textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
      iconTheme: IconThemeData(color: _textPrimary),
    ),
    cardTheme: CardThemeData(
      color: _surfaceDark,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderSubtle, width: 1),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: _bgBlack,
      selectedIconTheme: const IconThemeData(color: _neon, size: 24),
      unselectedIconTheme: const IconThemeData(color: _textMuted, size: 24),
      selectedLabelTextStyle: const TextStyle(
        color: _neon, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: const TextStyle(color: _textSecondary),
      indicatorColor: _neon.withValues(alpha: 0.12),
      useIndicator: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: _bgBlack,
      surfaceTintColor: Colors.transparent,
      indicatorColor: _neon.withValues(alpha: 0.15),
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: states.contains(WidgetState.selected) ? _neon : _textSecondary,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? _neon : _textMuted,
          )),
    ),
    dividerTheme: const DividerThemeData(color: _borderSubtle, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceElevated,
      labelStyle: const TextStyle(color: _textSecondary),
      hintStyle: const TextStyle(color: _textMuted),
      helperStyle: const TextStyle(color: _textMuted),
      prefixIconColor: _textSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _borderSubtle, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _neon, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _neon,
        foregroundColor: Colors.black,
        disabledBackgroundColor: _surfaceElevated,
        disabledForegroundColor: _textMuted,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _neon,
        side: const BorderSide(color: _borderSubtle, width: 1),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: _neon),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: _textSecondary),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: _surfaceElevated,
      labelStyle: const TextStyle(color: _textPrimary, fontSize: 12),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _neon,
      foregroundColor: Colors.black,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: _surfaceElevated,
      contentTextStyle: TextStyle(color: _textPrimary),
      actionTextColor: _neon,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _neon;
        return _textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _neon.withValues(alpha: 0.4);
        return _surfaceElevated;
      }),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: _neon),
    listTileTheme: const ListTileThemeData(
      iconColor: _textSecondary,
      textColor: _textPrimary,
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: _neon,
      collapsedIconColor: _textSecondary,
      textColor: _textPrimary,
      collapsedTextColor: _textPrimary,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: _textPrimary, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1),
      headlineMedium: TextStyle(color: _textPrimary, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1),
      headlineSmall: TextStyle(color: _textPrimary, fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.15),
      titleLarge: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700, height: 1.25),
      titleMedium: TextStyle(color: _textPrimary, fontWeight: FontWeight.w600, height: 1.3),
      titleSmall: TextStyle(color: _textPrimary, fontWeight: FontWeight.w600, height: 1.3),
      bodyLarge: TextStyle(color: _textPrimary, height: 1.45),
      bodyMedium: TextStyle(color: _textPrimary, height: 1.45),
      bodySmall: TextStyle(color: _textSecondary, height: 1.4),
      labelLarge: TextStyle(color: _textPrimary, fontWeight: FontWeight.w600, height: 1.2),
      labelMedium: TextStyle(color: _textSecondary),
      labelSmall: TextStyle(color: _textMuted),
    ),
  );
}

