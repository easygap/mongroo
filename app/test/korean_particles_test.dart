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
}
