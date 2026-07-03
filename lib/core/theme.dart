// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — "warm dark" (redesign 2026). Konstant-navnene bevares fra
// den tidligere palette, så hele appen arver de nye værdier uden ændringer.
// ─────────────────────────────────────────────────────────────────────────────
const _neon            = Color(0xFFE8622C); // Accent — orange (primær handling/brand)
const _bgBlack         = Color(0xFF161210); // Scaffold-baggrund (--bg)
const _header          = Color(0xFF241914); // Top-bar / sidebar / nav (--header)
const _surfaceDark     = Color(0xFF211A16); // Card / panel (--card)
const _surfaceElevated = Color(0xFF2A211C); // Nested / dato-blok / inputs (--card2)
const _borderSubtle    = Color(0x14FFFFFF); // rgba(255,255,255,.08) — hairline
const _textPrimary     = Color(0xFFF3ECE4); // varm off-white (--text)
const _textSecondary   = Color(0xFFA2968B); // sekundær tekst (--muted)
const _textMuted       = Color(0xFF8B8079); // hint / inaktiv / disabled

// Semantiske farver (redesign-spec)
const _success   = Color(0xFF34C759); // tilmeld / betalt / deltog
const _onSuccess = Color(0xFF08210F); // tekst på grøn
const _danger    = Color(0xFFE5544E); // afbud / skyldig / fravær
const _gold      = Color(0xFFF2A63B); // advarsel / guld-rang / afventer
const _onGold    = Color(0xFF3A2600); // tekst på guld
const _silver    = Color(0xFFC9C0B6); // sølv-rang

// ─────────────────────────────────────────────────────────────────────────────
// Typografi — Barlow (brødtekst/labels/knapper) + Barlow Condensed (titler/tal).
// Hentes via google_fonts og caches. Uppercase styres på anvendelsesstedet.
// ─────────────────────────────────────────────────────────────────────────────
TextStyle _cond(
        {required double size,
        FontWeight weight = FontWeight.w800,
        Color color = _textPrimary,
        double spacing = 0,
        double height = 1.1}) =>
    GoogleFonts.barlowCondensed(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: height,
    );

TextStyle _body(
        {required double size,
        FontWeight weight = FontWeight.w400,
        Color color = _textPrimary,
        double spacing = 0,
        double height = 1.4}) =>
    GoogleFonts.barlow(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: height,
    );

ThemeData _buildClayCourt() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _neon,
    onPrimary: Colors.white,
    secondary: _neon,
    onSecondary: Colors.white,
    error: _danger,
    onError: Colors.white,
    surface: _surfaceDark,
    onSurface: _textPrimary,
    surfaceContainerLowest: _bgBlack,
    surfaceContainerLow: _surfaceDark,
    surfaceContainer: _surfaceDark,
    surfaceContainerHigh: _surfaceElevated,
    surfaceContainerHighest: _surfaceElevated,
    onSurfaceVariant: _textSecondary,
    primaryContainer: Color(0xFF3A2116),
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
    appBarTheme: AppBarTheme(
      backgroundColor: _header,
      foregroundColor: _textPrimary,
      elevation: 0,
      titleTextStyle: _cond(
        size: 18,
        weight: FontWeight.w800,
        color: _textPrimary,
        spacing: 0.5,
      ),
      iconTheme: const IconThemeData(color: _textSecondary),
    ),
    cardTheme: CardThemeData(
      color: _surfaceDark,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderSubtle, width: 1),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: _header,
      selectedIconTheme: const IconThemeData(color: _neon, size: 24),
      unselectedIconTheme: const IconThemeData(color: _textMuted, size: 24),
      selectedLabelTextStyle: _body(
          size: 13, weight: FontWeight.w700, color: _neon),
      unselectedLabelTextStyle: _body(size: 13, color: _textSecondary),
      indicatorColor: _neon.withValues(alpha: 0.14),
      useIndicator: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: _header,
      surfaceTintColor: Colors.transparent,
      indicatorColor: _neon.withValues(alpha: 0.15),
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => _body(
            size: 11,
            weight: FontWeight.w600,
            spacing: 0.2,
            color: states.contains(WidgetState.selected) ? _neon : _textMuted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected) ? _neon : _textMuted,
          )),
    ),
    dividerTheme: const DividerThemeData(color: _borderSubtle, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceElevated,
      labelStyle: _body(size: 14, color: _textSecondary),
      hintStyle: _body(size: 14, color: _textMuted),
      helperStyle: _body(size: 12, color: _textMuted),
      prefixIconColor: _textSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: _borderSubtle, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: _neon, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _neon,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _surfaceElevated,
        disabledForegroundColor: _textMuted,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        textStyle: _body(size: 14, weight: FontWeight.w700, spacing: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _neon,
        side: const BorderSide(color: _borderSubtle, width: 1),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        textStyle: _body(size: 14, weight: FontWeight.w700, spacing: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _neon,
        textStyle: _body(size: 14, weight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: _textSecondary),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: _surfaceElevated,
      labelStyle: _body(size: 12, color: _textPrimary),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _neon,
      foregroundColor: Colors.white,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _surfaceElevated,
      contentTextStyle: _body(size: 14, color: _textPrimary),
      actionTextColor: _neon,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return _textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _success;
        return _surfaceElevated;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _success;
        return _borderSubtle;
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
    textTheme: TextTheme(
      // Overskrifter / titler / tal → Barlow Condensed
      headlineLarge:  _cond(size: 34, weight: FontWeight.w800, spacing: 0.3),
      headlineMedium: _cond(size: 30, weight: FontWeight.w800, spacing: 0.3),
      headlineSmall:  _cond(size: 24, weight: FontWeight.w800, spacing: 0.4),
      titleLarge:     _cond(size: 20, weight: FontWeight.w700, spacing: 0.3, height: 1.15),
      titleMedium:    _cond(size: 17, weight: FontWeight.w700, spacing: 0.2, height: 1.2),
      titleSmall:     _cond(size: 15, weight: FontWeight.w700, spacing: 0.2, height: 1.2),
      // Brødtekst / labels → Barlow
      bodyLarge:  _body(size: 15, height: 1.45),
      bodyMedium: _body(size: 14, height: 1.45),
      bodySmall:  _body(size: 13, color: _textSecondary, height: 1.4),
      labelLarge:  _body(size: 14, weight: FontWeight.w600, height: 1.2),
      labelMedium: _body(size: 12, color: _textSecondary),
      labelSmall:  _body(size: 11, color: _textMuted),
    ),
  );
}
