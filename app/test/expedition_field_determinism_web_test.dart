@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/expedition/presentation/expedition_screen.dart';

/// 지형 생성기가 **웹에서도** 같은 땅을 만드는지 본다.
///
/// 이 파일만 브라우저에서 돌린다:
///
/// ```powershell
/// flutter test --platform chrome test/expedition_field_determinism_web_test.dart
/// ```
///
/// 나머지 테스트와 값이 같아야 한다. 앞 판은 `hash * 16777619`를 한 번에
/// 곱해서, 웹에서만 아래 비트가 날아가 출발 칸부터 달랐다. 네이티브에서만
/// 검사하면 이런 어긋남을 영영 못 잡는다.
///
/// `@TestOn('browser')`라 평소 `flutter test`에서는 건너뛴다. 돌릴 때는 앱
/// 전체를 dart2js로 컴파일하므로 몇 분 걸린다 — 내 환경에서는 10분을 넘겨
/// 끝을 못 봤다. 지형 생성기를 건드렸을 때만 시간을 두고 돌리면 된다.
void main() {
  test('출발 칸이 네이티브와 같다', () {
    const expected = <String, List<int>>{
      'moss_archive': <int>[9, 44],
      'echo_well': <int>[9, 44],
      'starlight_seed_vault': <int>[9, 44],
      'heartwood_observatory': <int>[10, 44],
    };
    expected.forEach((region, spawn) {
      final diagnostics = expeditionTileWorldTravelDiagnostics(region, 1);
      expect(diagnostics['spawnX'], spawn.first, reason: region);
      expect(diagnostics['spawnY'], spawn.last, reason: region);
    });
  });

  test('네 지역 여덟 장이 모두 제단까지 이어진다', () {
    for (final region in <String>[
      'moss_archive',
      'echo_well',
      'starlight_seed_vault',
      'heartwood_observatory',
    ]) {
      for (var stage = 1; stage <= 8; stage++) {
        expect(
          expeditionTileWorldHasRoute(region, stage),
          isTrue,
          reason: '$region $stage장',
        );
      }
    }
  });
}
