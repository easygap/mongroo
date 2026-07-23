import 'package:flutter/material.dart';
import 'package:mongroo/core/branding/mongroo_brand.dart';

@immutable
class MongrooPalette extends ThemeExtension<MongrooPalette> {
  const MongrooPalette({
    required this.paper,
    required this.paperDeep,
    required this.ink,
    required this.inkMuted,
    required this.leaf,
    required this.coral,
    required this.butter,
    required this.sky,
    required this.blush,
    required this.wood,
    required this.night,
  });

  final Color paper;
  final Color paperDeep;
  final Color ink;
  final Color inkMuted;
  final Color leaf;
  final Color coral;
  final Color butter;
  final Color sky;
  final Color blush;
  final Color wood;
  final Color night;

  static MongrooPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<MongrooPalette>() ??
        (theme.brightness == Brightness.dark
            ? AppTheme._darkPalette
            : AppTheme._lightPalette);
  }

  @override
  MongrooPalette copyWith({
    Color? paper,
    Color? paperDeep,
    Color? ink,
    Color? inkMuted,
    Color? leaf,
    Color? coral,
    Color? butter,
    Color? sky,
    Color? blush,
    Color? wood,
    Color? night,
  }) =>
      MongrooPalette(
        paper: paper ?? this.paper,
        paperDeep: paperDeep ?? this.paperDeep,
        ink: ink ?? this.ink,
        inkMuted: inkMuted ?? this.inkMuted,
        leaf: leaf ?? this.leaf,
        coral: coral ?? this.coral,
        butter: butter ?? this.butter,
        sky: sky ?? this.sky,
        blush: blush ?? this.blush,
        wood: wood ?? this.wood,
        night: night ?? this.night,
      );

  @override
  MongrooPalette lerp(covariant MongrooPalette? other, double t) {
    if (other == null) return this;
    return MongrooPalette(
      paper: Color.lerp(paper, other.paper, t)!,
      paperDeep: Color.lerp(paperDeep, other.paperDeep, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      leaf: Color.lerp(leaf, other.leaf, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
      butter: Color.lerp(butter, other.butter, t)!,
      sky: Color.lerp(sky, other.sky, t)!,
      blush: Color.lerp(blush, other.blush, t)!,
      wood: Color.lerp(wood, other.wood, t)!,
      night: Color.lerp(night, other.night, t)!,
    );
  }
}

abstract final class MongrooMotion {
  static const quick = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 220);
  static const enter = Cubic(0.23, 1, 0.32, 1);
}

abstract final class AppTheme {
  static const pixelFont = 'Galmuri11';
  static const seed = MongrooBrandColors.sprout;
  static const onNight = MongrooBrandColors.paper;
  static const onNightMuted = Color(0xFFD0C3B5);

  static const _lightPalette = MongrooPalette(
    paper: MongrooBrandColors.paper,
    paperDeep: Color(0xFFE9E1D3),
    ink: Color(0xFF3B1F06),
    inkMuted: Color(0xFF75685D),
    leaf: Color(0xFF68864D),
    coral: Color(0xFFB84F46),
    butter: Color(0xFFFAED27),
    sky: Color(0xFFB9E0FD),
    blush: Color(0xFFF2D5CE),
    wood: Color(0xFF936445),
    night: Color(0xFF3B1F06),
  );

  static const _darkPalette = MongrooPalette(
    paper: Color(0xFF221C16),
    paperDeep: Color(0xFF302820),
    ink: MongrooBrandColors.paper,
    inkMuted: Color(0xFFCDBFB0),
    leaf: Color(0xFFA8D984),
    coral: Color(0xFFE9978D),
    butter: Color(0xFFF4DE52),
    sky: Color(0xFF9CCAE8),
    blush: Color(0xFF4C302C),
    wood: Color(0xFFC79B7A),
    night: Color(0xFF16110D),
  );

  static ThemeData light() => _base(
        scheme: const ColorScheme.light(
          primary: MongrooBrandColors.sprout,
          onPrimary: MongrooBrandColors.soil,
          primaryContainer: Color(0xFFE2F8CC),
          onPrimaryContainer: MongrooBrandColors.soil,
          secondary: Color(0xFF9D443D),
          onSecondary: MongrooBrandColors.paper,
          secondaryContainer: Color(0xFFF2D5CE),
          onSecondaryContainer: Color(0xFF4B201C),
          tertiary: Color(0xFF536D3F),
          onTertiary: MongrooBrandColors.paper,
          tertiaryContainer: Color(0xFFDCE9D7),
          onTertiaryContainer: Color(0xFF243D29),
          error: Color(0xFFB3261E),
          onError: Color(0xFFFFFFFF),
          surface: MongrooBrandColors.paper,
          onSurface: Color(0xFF3B1F06),
          onSurfaceVariant: Color(0xFF75685D),
          outline: Color(0xFF8A7768),
          outlineVariant: Color(0xFFD8CFC2),
          shadow: Color(0xFF3B1F06),
          inverseSurface: Color(0xFF3B1F06),
          onInverseSurface: MongrooBrandColors.paper,
          inversePrimary: MongrooBrandColors.sprout,
        ),
        canvas: const Color(0xFFF2EDE3),
        palette: _lightPalette,
      );

  static ThemeData dark() => _base(
        scheme: const ColorScheme.dark(
          primary: MongrooBrandColors.sprout,
          onPrimary: MongrooBrandColors.soil,
          primaryContainer: Color(0xFF3F5830),
          onPrimaryContainer: Color(0xFFE2F8CC),
          secondary: Color(0xFFE9978D),
          onSecondary: Color(0xFF4C211D),
          secondaryContainer: Color(0xFF673832),
          onSecondaryContainer: Color(0xFFF4D7D1),
          tertiary: Color(0xFFA8D984),
          onTertiary: Color(0xFF233B27),
          tertiaryContainer: Color(0xFF36533A),
          onTertiaryContainer: Color(0xFFDCE9D7),
          error: Color(0xFFFFB4AB),
          onError: Color(0xFF690005),
          surface: Color(0xFF221C16),
          onSurface: MongrooBrandColors.paper,
          onSurfaceVariant: Color(0xFFCDBFB0),
          outline: Color(0xFFA18F7E),
          outlineVariant: Color(0xFF51463C),
          shadow: Color(0xFF000000),
          inverseSurface: MongrooBrandColors.paper,
          onInverseSurface: MongrooBrandColors.soil,
          inversePrimary: Color(0xFF668E4F),
        ),
        canvas: const Color(0xFF17130F),
        palette: _darkPalette,
      );

  static ThemeData _base({
    required ColorScheme scheme,
    required Color canvas,
    required MongrooPalette palette,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      extensions: [palette],
    );
    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontSize: 36,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.3,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 30,
        height: 1.25,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 22,
        height: 1.3,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.55,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.35,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.55),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.52),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
      ),
      labelSmall: base.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
    );

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        toolbarHeight: 60,
        backgroundColor: canvas,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontSize: 19,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 50),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.onSurface,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.onSurface,
        selectionColor: scheme.tertiary.withAlpha(130),
        selectionHandleColor: scheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.onSurface, width: 2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle:
            textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.night,
        contentTextStyle: const TextStyle(color: onNight),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.brightness == Brightness.light
            ? const Color(0xFF41671F)
            : scheme.primary,
        linearTrackColor: palette.paperDeep,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.night,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: onNight),
      ),
    );
  }
}
