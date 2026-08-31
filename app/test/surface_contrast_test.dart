import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';

/// 색이 정해진 면 위에 글자를 얹는 자리들의 대비 계약.
///
/// 한 화면에서만 잡으면 같은 실수가 다른 화면에서 또 난다. 실제로 붉은 면
/// 위에 본문 기본색을 얹은 곳이 세 군데였고 전부 2.32:1이었다 — 약관의 개발
/// 빌드 안내, 체험의 저장소 경고, 대화 시작 패널의 오류 문구다.
void main() {
  double contrastRatio(Color foreground, Color background) {
    final first = foreground.computeLuminance();
    final second = background.computeLuminance();
    final lighter = first > second ? first : second;
    final darker = first > second ? second : first;
    return (lighter + 0.05) / (darker + 0.05);
  }

  test('붉은 경고 면 위의 글자는 두 테마에서 AA를 넘는다', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final scheme = theme.colorScheme;
      expect(
        contrastRatio(scheme.onErrorContainer, scheme.errorContainer),
        greaterThanOrEqualTo(4.5),
        reason: '${scheme.brightness} errorContainer',
      );
      // 잘못이 아닌 안내(세션 만료 등)는 붉은 면 대신 이 면을 쓴다.
      expect(
        contrastRatio(scheme.onSecondaryContainer, scheme.secondaryContainer),
        greaterThanOrEqualTo(4.5),
        reason: '${scheme.brightness} secondaryContainer',
      );
      // 본문 기본색을 그대로 얹으면 왜 안 되는지도 함께 남긴다.
      if (scheme.brightness == Brightness.light) {
        expect(
          contrastRatio(scheme.onSurface, scheme.errorContainer),
          lessThan(4.5),
          reason: '이 값이 4.5를 넘으면 위 계약이 의미를 잃습니다',
        );
      }
    }
  });

  test('밤색 면 위의 글자는 두 테마에서 AA를 넘는다', () {
    // 밤색 패널은 테마와 무관하게 늘 어둡다. 그래서 밝은 테마의 `error`를
    // 얹으면 오히려 안 읽힌다.
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final palette = theme.extension<MongrooPalette>()!;
      for (final pair in <(String, Color)>[
        ('onNight', AppTheme.onNight),
        ('onNightMuted', AppTheme.onNightMuted),
        ('onNightError', AppTheme.onNightError),
      ]) {
        expect(
          contrastRatio(pair.$2, palette.night),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.colorScheme.brightness} ${pair.$1}',
        );
      }
      // 어두운 테마의 `error`는 밝은 빨강이라 밤색 위에서도 읽힌다. 문제는
      // 밝은 테마 쪽이고, 그래서 테마로 갈라 쓰면 안 된다.
      if (theme.colorScheme.brightness == Brightness.light) {
        expect(
          contrastRatio(theme.colorScheme.error, palette.night),
          lessThan(4.5),
          reason: '밝은 테마 error를 밤색 위에 쓰면 안 되는 이유가 사라졌습니다',
        );
      }
    }
  });

  test('흐리게 깐 경고 면 위의 글자도 AA를 넘는다', () {
    // 대화 오류 막대와 전투 라운드 경고는 경고색을 알파로 깔아 쓴다. 그 위에
    // 진한 빨강 면을 위한 짝(`onErrorContainer`)을 얹어 2.1:1이었다.
    Color over(Color background, Color tint, int alpha) =>
        Color.lerp(background, tint, alpha / 255)!;

    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final scheme = theme.colorScheme;
      final faded = over(scheme.surface, scheme.errorContainer, 90);
      expect(
        contrastRatio(scheme.onSurface, faded),
        greaterThanOrEqualTo(4.5),
        reason: '${scheme.brightness} 흐린 경고 면의 본문',
      );
      // 아이콘은 비텍스트라 3:1이면 된다. 경고색을 그대로 살린다.
      expect(
        contrastRatio(scheme.error, faded),
        greaterThanOrEqualTo(3),
        reason: '${scheme.brightness} 흐린 경고 면의 아이콘',
      );
      expect(
        contrastRatio(scheme.onErrorContainer, faded),
        lessThan(4.5),
        reason: '진한 면용 짝을 흐린 면에 써도 되는 상태가 됐습니다',
      );
    }
  });

  test('색 구성표의 짝 전체가 두 테마에서 AA를 넘는다', () {
    // 지금까지는 눈에 띈 짝 셋만 쟀다. 실제로 화면 대부분은
    // `onSurfaceVariant`로 보조 문장을 쓰는데 그 짝은 검사에 없었다.
    // 구성표가 정한 짝을 통째로 잰다 - 팔레트를 조금만 손봐도 여기서 걸린다.
    //
    // 밝은 테마의 `onSurfaceVariant/surface`가 4.69로 가장 아슬아슬하다.
    // 이 값이 4.5 아래로 내려가면 앱 전체의 보조 문장이 한꺼번에 안 읽힌다.
    for (final entry in {
      '밝은': AppTheme.light(),
      '어두운': AppTheme.dark(),
    }.entries) {
      final scheme = entry.value.colorScheme;
      final pairs = <String, (Color, Color)>{
        'onSurface/surface': (scheme.onSurface, scheme.surface),
        'onSurfaceVariant/surface': (scheme.onSurfaceVariant, scheme.surface),
        'onSurfaceVariant/surfaceContainerLowest': (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerLowest,
        ),
        'onSurfaceVariant/surfaceContainer': (
          scheme.onSurfaceVariant,
          scheme.surfaceContainer,
        ),
        'onSurfaceVariant/surfaceContainerHighest': (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest,
        ),
        'onPrimary/primary': (scheme.onPrimary, scheme.primary),
        'onPrimaryContainer/primaryContainer': (
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
        ),
        'onSecondary/secondary': (scheme.onSecondary, scheme.secondary),
        'onSecondaryContainer/secondaryContainer': (
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
        ),
        'onTertiary/tertiary': (scheme.onTertiary, scheme.tertiary),
        'onTertiaryContainer/tertiaryContainer': (
          scheme.onTertiaryContainer,
          scheme.tertiaryContainer,
        ),
        'onError/error': (scheme.onError, scheme.error),
        'onErrorContainer/errorContainer': (
          scheme.onErrorContainer,
          scheme.errorContainer,
        ),
        'onInverseSurface/inverseSurface': (
          scheme.onInverseSurface,
          scheme.inverseSurface,
        ),
      };
      for (final pair in pairs.entries) {
        expect(
          contrastRatio(pair.value.$1, pair.value.$2),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} 테마의 ${pair.key}',
        );
      }
    }
  });
}
