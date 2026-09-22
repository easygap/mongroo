import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 화면마다 용어가 다시 달라지는 일을 막는다.
/// 세계관 설명보다 처음 보는 사람이 이해할 수 있는 말을 우선한다.
void main() {
  const banned = <String, String>{
    '성장결': '성장 타입',
    '공유 집중력': '팀 기력',
    '자동 지휘': '자동 전투',
    '마음 지키기': '방어',
    '온실 루트': '오늘 할 일',
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
