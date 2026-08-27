import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/text/korean_particles.dart';

void main() {
  test('이름의 받침에 맞는 한국어 조사를 붙인다', () {
    expect(koreanObject('여우비'), '여우비를');
    expect(koreanObject('별솔'), '별솔을');
    expect(koreanSubject('뽀또'), '뽀또가');
    expect(koreanSubject('새싹몬'), '새싹몬이');
  });

  test('전투 프롬프트가 쓰는 보조사(은/는)를 붙인다', () {
    expect(koreanTopic('뽀또'), '뽀또는');
    expect(koreanTopic('새싹몬'), '새싹몬은');
    expect(koreanTopic('해답이'), '해답이는');
    expect(koreanTopic('별솔'), '별솔은');
  });

  test('로/으로는 ㄹ 받침을 받침 없는 것처럼 다룬다', () {
    // 다른 조사와 규칙이 하나 다르다. `모아결으로`는 홈 화면에 그대로 나갔다.
    expect(koreanDirection('모아결'), '모아결로');
    expect(koreanDirection('햇살결'), '햇살결로');
    expect(koreanDirection('모자이크형'), '모자이크형으로');
    expect(koreanDirection('뽀또'), '뽀또로');
    // 숫자는 한국어로 읽었을 때를 따른다 - 일·칠·팔은 ㄹ 받침이다.
    expect(koreanDirection('109'), '109로');
    expect(koreanDirection('1391'), '1391로');
    expect(koreanDirection('1393'), '1393으로');
    expect(koreanDirection('112'), '112로');
  });

  test('자리표시자를 화면 문자열에 그대로 두지 않는다', () {
    // 서버 쪽에서 `새싹몬이(가) 고른 길과…`가 그대로 나갔다. 앱에도 같은
    // 모양이 하나 있었다 - `집중력 2이(가) 필요해요`.
    final lib = Directory('lib');
    const placeholders = ['이(가)', '을(를)', '은(는)', '와(과)', '과(와)'];
    final offenders = <String>[];
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // 조사 헬퍼는 규칙을 설명하느라 이름을 적어 둘 수 있다.
      if (entity.path.endsWith('korean_particles.dart')) continue;
      final text = entity.readAsStringSync();
      for (final placeholder in placeholders) {
        if (text.contains(placeholder)) {
          offenders.add('${entity.path}: $placeholder');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
