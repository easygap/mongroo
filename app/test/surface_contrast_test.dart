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
}
