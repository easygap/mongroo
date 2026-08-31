import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 화면에 나가는 말이 한 가지로 모여 있는지 본다.
///
/// 이 저장소는 같은 것을 두 이름으로 부르던 것을 여러 번 고쳤다 — 퀘스트·미션·
/// 작은 행동을 하나로 맞췄고, 탐험을 여섯 군데에서만 모험이라고 부르던 것도
/// 고쳤다. 그런데 매번 눈으로 찾아야 했고, 그래서 `출처 · 스킬북` 한 줄과
/// `몬스터 소굴` 한 줄이 오래 남아 있었다.
///
/// 목록을 손으로 관리하는 대신 **금지어를 구조로 막는다.** 새 화면이 옛 어휘를
/// 들고 들어오면 여기서 걸린다.
void main() {
  /// 쓰면 안 되는 말과, 대신 쓰는 말.
  ///
  /// 세계관이 정한 어휘다. `엉킴`은 처치하는 몬스터가 아니라 돌보는 손이
  /// 모자라 엉켜 버린 물건이고(실행 계약 9장이 처치·사냥 언어를 금지한다),
  /// 전투 밖에서는 `기록서`가 정식 이름이다.
  const banned = <String, String>{
    '몬스터': '엉킴 또는 수호자',
    '스킬북': '기록서',
    '퀘스트': '작은 행동',
    '미션': '작은 행동',
    '레벨업': '성장',
  };

  /// 코드 주석과 파일 안쪽 이름은 화면에 안 나간다. 문자열만 본다.
  final koreanString = RegExp(r"'([^'\\\n]*[가-힣][^'\\\n]*)'");
  final lineComment = RegExp(r'^\s*//');

  test('화면에 나가는 문구가 옛 어휘를 쓰지 않는다', () {
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (lineComment.hasMatch(line)) continue;
        for (final match in koreanString.allMatches(line)) {
          final text = match.group(1)!;
          for (final entry in banned.entries) {
            if (text.contains(entry.key)) {
              offenders.add(
                '${file.path}:${index + 1}  "$text"  '
                '→ ${entry.key} 대신 ${entry.value}',
              );
            }
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
