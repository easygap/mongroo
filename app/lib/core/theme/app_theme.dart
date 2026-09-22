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
  static const bodyFont = 'WantedSans';
  static const pixelFont = 'Galmuri11';
  static const seed = MongrooBrandColors.sprout;
  static const onNight = MongrooBrandColors.paper;
  static const onNightMuted = Color(0xFFC8C8C8);

  /// 밤색 면 위의 오류 문구.
  ///
  /// 밤색 패널은 테마와 무관하게 늘 어둡다. 밝은 테마의 `error`(진한 빨강)를
  /// 얹으면 2.3:1이라 오류 문구만 안 읽힌다. 두 테마 모두 이 밝은 빨강을 쓴다.
  static const onNightError = Color(0xFFFFB4AB);

  static const _lightPalette = MongrooPalette(
    paper: MongrooBrandColors.paper,
    paperDeep: Color(0xFFEBEBEB),
    ink: MongrooBrandColors.ink,
    inkMuted: Color(0xFF616161),
    leaf: MongrooBrandColors.action,
    coral: Color(0xFF6A4B44),
    butter: Color(0xFFD5D5D5),
    sky: Color(0xFFE2E5E9),
    blush: Color(0xFFF4E7E9),
    wood: Color(0xFF686868),
    night: Color(0xFF202020),
  );

  static const _darkPalette = MongrooPalette(
    paper: Color(0xFF1B1B1B),
    paperDeep: Color(0xFF2A2A2A),
    ink: MongrooBrandColors.paper,
    inkMuted: Color(0xFFBDBDBD),
    leaf: Color(0xFFF0F0F0),
    coral: Color(0xFFDFB9B1),
    butter: Color(0xFFD5D5D5),
    sky: Color(0xFFC9CDD4),
    blush: Color(0xFF3C282D),
    wood: Color(0xFFBDBDBD),
    night: Color(0xFF121212),
  );

  static ThemeData light() => _base(
        scheme: const ColorScheme.light(
          primary: MongrooBrandColors.action,
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFEFEFEF),
          onPrimaryContainer: Color(0xFF242424),
          secondary: Color(0xFF6A4B44),
          onSecondary: MongrooBrandColors.paper,
          secondaryContainer: Color(0xFFF1E9E6),
          onSecondaryContainer: Color(0xFF54342F),
          tertiary: Color(0xFF5F6268),
          onTertiary: MongrooBrandColors.paper,
          tertiaryContainer: Color(0xFFECEDEF),
          onTertiaryContainer: Color(0xFF303236),
          error: Color(0xFFBE233C),
          onError: Color(0xFFFFFFFF),
          errorContainer: Color(0xFFFFE9EE),
          onErrorContainer: Color(0xFF6A1026),
          surface: MongrooBrandColors.paper,
          surfaceDim: Color(0xFFE3E3E3),
          surfaceBright: Colors.white,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Color(0xFFFAFAFA),
          surfaceContainer: Color(0xFFF3F3F3),
          surfaceContainerHigh: Color(0xFFEBEBEB),
          surfaceContainerHighest: Color(0xFFE3E3E3),
          surfaceTint: Colors.transparent,
          onSurface: MongrooBrandColors.ink,
          onSurfaceVariant: Color(0xFF616161),
          outline: Color(0xFF808080),
          outlineVariant: Color(0xFFDEDEDE),
          shadow: MongrooBrandColors.ink,
          inverseSurface: Color(0xFF232323),
          onInverseSurface: MongrooBrandColors.paper,
          inversePrimary: MongrooBrandColors.sprout,
        ),
        canvas: const Color(0xFFF7F7F7),
        palette: _lightPalette,
      );

  static ThemeData dark() => _base(
        scheme: const ColorScheme.dark(
          primary: Color(0xFFF0F0F0),
          onPrimary: Color(0xFF202020),
          primaryContainer: Color(0xFF343434),
          onPrimaryContainer: Color(0xFFF3F3F3),
          secondary: Color(0xFFDFB9B1),
          onSecondary: Color(0xFF45302B),
          secondaryContainer: Color(0xFF41332F),
          onSecondaryContainer: Color(0xFFF1DED9),
          tertiary: Color(0xFFCACCD1),
          onTertiary: Color(0xFF2E3035),
          tertiaryContainer: Color(0xFF34363B),
          onTertiaryContainer: Color(0xFFE4E5E8),
          error: Color(0xFFFF9BAC),
          onError: Color(0xFF670018),
          errorContainer: Color(0xFF4B202D),
          onErrorContainer: Color(0xFFFFDCE3),
          surface: Color(0xFF1B1B1B),
          surfaceDim: Color(0xFF121212),
          surfaceBright: Color(0xFF3D3D3D),
          surfaceContainerLowest: Color(0xFF121212),
          surfaceContainerLow: Color(0xFF202020),
          surfaceContainer: Color(0xFF242424),
          surfaceContainerHigh: Color(0xFF2A2A2A),
          surfaceContainerHighest: Color(0xFF323232),
          surfaceTint: Colors.transparent,
          onSurface: MongrooBrandColors.paper,
          onSurfaceVariant: Color(0xFFBDBDBD),
          outline: Color(0xFF919191),
          outlineVariant: Color(0xFF404040),
          shadow: Color(0xFF000000),
          inverseSurface: MongrooBrandColors.paper,
          onInverseSurface: MongrooBrandColors.soil,
          inversePrimary: MongrooBrandColors.action,
        ),
        canvas: const Color(0xFF121212),
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
      fontFamily: bodyFont,
      // CanvasKit이 한글 글리프를 원격 Noto CDN에서 동적으로 찾지 않도록
      // pubspec에 같은 로컬 파일로 등록한 fallback family만 사용한다.
      fontFamilyFallback: const ['Noto Sans KR', 'Roboto'],
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
        letterSpacing: -1.0,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 30,
        height: 1.25,
        fontWeight: FontWeight.w800,
        letterSpacing: -.75,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 22,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
      ),
      bodyLarge:
          base.textTheme.bodyLarge?.copyWith(height: 1.55, letterSpacing: -.15),
      bodyMedium:
          base.textTheme.bodyMedium?.copyWith(height: 1.5, letterSpacing: -.1),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelSmall: base.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w500,
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
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.onSurface,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withAlpha(45),
        selectionHandleColor: scheme.primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 2),
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
        color: scheme.primary,
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
