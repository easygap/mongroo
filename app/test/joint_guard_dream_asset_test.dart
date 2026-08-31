import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/expedition/presentation/joint_guard_screen.dart';

/// 짐승마다 자기 꿈 배경이 실제 파일로 있는지 본다.
///
/// 배경이 없으면 `dreamSceneFor`가 조용히 공용 수호전 무대로 물러난다. 화면은
/// 멀쩡해 보이지만 넷이 같은 곳에서 싸우게 되고, 그러면 `깊은 꿈`이 그냥 한 판
/// 더가 된다. 조용한 폴백은 눈으로 잡기 어려우니 여기서 막는다.
void main() {
  /// 서버 `joint_guard.BEAST_CATALOG`의 code와 같다. 짐승이 늘면 여기가 먼저
  /// 빨간불이 되어 원화를 빠뜨린 채로 나가지 않는다.
  const beasts = <String>[
    'ledger_keeper',
    'echo_keeper',
    'seed_keeper',
    'record_keeper',
  ];

  test('네 짐승이 모두 자기 꿈 배경을 가진다', () {
    for (final beast in beasts) {
      final scene = dreamSceneFor(beast);
      expect(
        scene.assetPath,
        contains('joint-guard-dream-'),
        reason: '$beast의 꿈 배경이 공용 무대로 물러났습니다',
      );
      expect(
        File(scene.assetPath).existsSync(),
        isTrue,
        reason: '${scene.assetPath} 파일이 없습니다',
      );
    }
  });

  test('꿈 배경은 짐승마다 서로 다르다', () {
    final paths = beasts.map((beast) => dreamSceneFor(beast).assetPath).toList();
    expect(paths.toSet().length, beasts.length, reason: paths.toString());
  });

  test('모바일 파생본도 함께 있다', () {
    // 좁은 화면은 절반 크기 파일을 읽는다. 없으면 매번 큰 원본을 내려받는다.
    for (final beast in beasts) {
      final full = dreamSceneFor(beast).assetPath;
      final mobile = full.replaceFirst('.webp', '-mobile.webp');
      expect(File(mobile).existsSync(), isTrue, reason: '$mobile 파일이 없습니다');
    }
  });

  test('강조색이 짐승마다 따로 있다', () {
    // 넷이 같은 색이면 겹 진행 배지와 예고 강조가 어느 꿈이든 똑같아진다.
    final accents = beasts.map((beast) => dreamSceneFor(beast).accent).toSet();
    expect(accents.length, beasts.length);
  });
}
