import 'package:material_ui/material_ui.dart';

import 'lineism.dart';

class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.surfaceElevated,
    required this.bubble,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textCaption,
    required this.border,
    required this.borderStrong,
    required this.brand,
    required this.brandHover,
    required this.codeBackground,
    required this.codeBanner,
    required this.inlineCode,
    required this.citation,
    required this.error,
    required this.signal,
    required this.hover,
    required this.active,
    required this.toast,
    required this.shadow,
    required this.accent,
    required this.onAccent,
    required this.accentWash,
  });

  final Brightness brightness;
  final Color background;
  final Color sidebar;
  final Color surface;
  final Color surfaceElevated;
  final Color bubble;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textCaption;
  final Color border;
  final Color borderStrong;
  final Color brand;
  final Color brandHover;
  final Color codeBackground;
  final Color codeBanner;
  final Color inlineCode;
  final Color citation;
  final Color error;
  final Color signal;
  final Color hover;
  final Color active;
  final Color toast;
  final Color shadow;

  /// Drum one: the working ink for primary actions and the user's voice.
  final Color accent;
  final Color onAccent;

  /// A translucent pass of [accent] for selected rows and user paper.
  final Color accentWash;

  bool get isDark => brightness == Brightness.dark;
}

extension LineismPalette on AppPalette {
  Color get linePaper => background;
  Color get lineInk => textPrimary;
  Color get lineInk2 => textSecondary;
  Color get lineRule => border;
  Color get lineSignal => signal;
  Color get lineAccent => accent;
}

const lightPalette = AppPalette(
  brightness: Brightness.light,
  background: Lineism.paper,
  sidebar: Lineism.paper2,
  surface: Lineism.paper,
  surfaceElevated: Lineism.paper2,
  bubble: Lineism.paper,
  textPrimary: Lineism.ink,
  textSecondary: Lineism.ink2,
  textTertiary: Color(0xFF6E6F7C),
  textCaption: Color(0xFF6A6A76),
  border: Lineism.rule,
  borderStrong: Lineism.ink2,
  brand: Lineism.cobalt,
  brandHover: Color(0xFF1B37A6),
  codeBackground: Color(0xFFE6DECB),
  codeBanner: Color(0xFFDDD3BD),
  inlineCode: Color(0xFFE6DECB),
  citation: Lineism.paper2,
  error: Color(0xFFD9381A),
  signal: Lineism.signal,
  hover: Color(0x0F171B2E),
  active: Color(0x1C171B2E),
  toast: Lineism.ink,
  shadow: Color(0x00000000),
  accent: Lineism.cobalt,
  onAccent: Color(0xFFF7F2E6),
  accentWash: Color(0x242547C9),
);

/// Night press: the same two drums printed on blue-black stock.
const darkPalette = AppPalette(
  brightness: Brightness.dark,
  background: Color(0xFF12141F),
  sidebar: Color(0xFF0E1019),
  surface: Color(0xFF12141F),
  surfaceElevated: Color(0xFF1A1D2B),
  bubble: Color(0xFF12141F),
  textPrimary: Color(0xFFEFE8D8),
  textSecondary: Color(0xFFB9B3A4),
  textTertiary: Color(0xFF9893A0),
  textCaption: Color(0xFF8F8B98),
  border: Color(0xFF2E3244),
  borderStrong: Color(0xFFB9B3A4),
  brand: Color(0xFF7D97FF),
  brandHover: Color(0xFF9AAEFF),
  codeBackground: Color(0xFF191C2A),
  codeBanner: Color(0xFF20243A),
  inlineCode: Color(0xFF20243A),
  citation: Color(0xFF1A1D2B),
  error: Color(0xFFFF6A4A),
  signal: Color(0xFFFF6A4A),
  hover: Color(0x12EFE8D8),
  active: Color(0x21EFE8D8),
  toast: Color(0xFF262A3D),
  shadow: Color(0x00000000),
  accent: Color(0xFF7D97FF),
  onAccent: Color(0xFF0E1019),
  accentWash: Color(0x247D97FF),
);

TextTheme buildTextTheme(AppPalette palette) {
  final base = Lineism.serif.copyWith(
    color: palette.textPrimary,
    fontSize: 14,
    height: 1.5,
  );
  final display = Lineism.display.copyWith(color: palette.textPrimary);
  return TextTheme(
    displayLarge: display.copyWith(fontSize: 56),
    displayMedium: display.copyWith(fontSize: 44),
    displaySmall: display.copyWith(fontSize: 34),
    headlineLarge: display.copyWith(fontSize: 30),
    headlineMedium: display.copyWith(fontSize: 26),
    headlineSmall: display.copyWith(fontSize: 22),
    titleLarge: display.copyWith(fontSize: 22),
    titleMedium: base.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
    titleSmall: base.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
    bodyLarge: base.copyWith(fontSize: 16, height: 1.65),
    bodyMedium: base,
    bodySmall: base.copyWith(fontSize: 13, color: palette.textSecondary),
    labelLarge: base.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
    labelMedium: base.copyWith(fontSize: 13),
    labelSmall: base.copyWith(fontSize: 12, color: palette.textTertiary),
  );
}

ThemeData buildTheme(AppPalette palette) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.signal,
        brightness: palette.brightness,
      ).copyWith(
        primary: palette.accent,
        onPrimary: palette.onAccent,
        secondary: palette.signal,
        onSecondary: palette.background,
        surface: palette.background,
        onSurface: palette.textPrimary,
        error: palette.signal,
        onError: palette.background,
        outline: palette.border,
        outlineVariant: palette.border,
        surfaceContainerHighest: palette.codeBackground,
        surfaceContainerHigh: palette.surfaceElevated,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: palette.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    dividerColor: palette.border,
    textTheme: buildTextTheme(palette),
    fontFamily: Lineism.serifFamily,
    fontFamilyFallback: Lineism.serifFallback,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.standard,
    iconTheme: IconThemeData(color: palette.textSecondary, size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: palette.textPrimary,
      titleTextStyle: Lineism.serif.copyWith(
        color: palette.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      hintStyle: TextStyle(color: palette.textCaption, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: palette.border, width: Lineism.hair),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: palette.border, width: Lineism.hair),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: palette.accent, width: Lineism.emphasis),
      ),
      errorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: palette.signal, width: Lineism.base),
      ),
      focusedErrorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: palette.signal, width: Lineism.emphasis),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: palette.textPrimary, width: Lineism.base),
      ),
      titleTextStyle: Lineism.display.copyWith(
        color: palette.textPrimary,
        fontSize: 24,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: palette.border, width: Lineism.base),
      ),
      textStyle: Lineism.serif.copyWith(
        color: palette.textPrimary,
        fontSize: 14,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.toast,
      contentTextStyle: Lineism.serif.copyWith(
        color: palette.background,
        fontSize: 13,
        letterSpacing: 0.2,
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      elevation: 0,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.textPrimary,
        borderRadius: BorderRadius.zero,
      ),
      textStyle: Lineism.serif.copyWith(
        color: palette.background,
        fontSize: 12,
      ),
      waitDuration: const Duration(milliseconds: 400),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.accent,
      selectionColor: palette.accent.withValues(alpha: 0.24),
      selectionHandleColor: palette.accent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(
        palette.textPrimary.withValues(alpha: 0.18),
      ),
      radius: Radius.zero,
      thickness: const WidgetStatePropertyAll(5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.border
              : states.contains(WidgetState.hovered)
              ? palette.brandHover
              : palette.accent,
        ),
        foregroundColor: WidgetStatePropertyAll(palette.onAccent),
        elevation: const WidgetStatePropertyAll(0),
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: palette.signal, width: Lineism.emphasis)
              : BorderSide.none,
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        overlayColor: WidgetStatePropertyAll(palette.hover),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(palette.textPrimary),
        overlayColor: WidgetStatePropertyAll(palette.hover),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(palette.textPrimary),
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: palette.signal, width: Lineism.emphasis)
              : states.contains(WidgetState.hovered)
              ? BorderSide(color: palette.textPrimary, width: Lineism.base)
              : BorderSide(color: palette.border, width: Lineism.base),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        overlayColor: WidgetStatePropertyAll(palette.hover),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.textPrimary
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.background
              : palette.textSecondary,
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: palette.textPrimary, width: Lineism.base),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: Lineism.displayFamily,
            fontFamilyFallback: [Lineism.serifFamily],
            fontSize: 15,
            letterSpacing: .6,
          ),
        ),
        overlayColor: WidgetStatePropertyAll(palette.hover),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      side: BorderSide(color: palette.border, width: Lineism.hair),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      labelStyle: Lineism.serif.copyWith(
        color: palette.textSecondary,
        fontSize: 12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    cardTheme: CardThemeData(
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: palette.border, width: Lineism.hair),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: palette.sidebar,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    dividerTheme: DividerThemeData(
      color: palette.border,
      thickness: Lineism.hair,
      space: Lineism.hair,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.onAccent
            : palette.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.accent
            : Colors.transparent,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.accent
            : palette.borderStrong,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.accent
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(palette.onAccent),
      side: BorderSide(color: palette.borderStrong, width: Lineism.base),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.accent,
      linearTrackColor: palette.border,
      circularTrackColor: palette.border,
    ),
  );
}
