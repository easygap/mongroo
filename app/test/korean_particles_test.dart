import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/text/korean_particles.dart';

void main() {
  test('이름의 받침에 맞는 한국어 조사를 붙인다', () {
    expect(koreanObject('여우비'), '여우비를');
    expect(koreanObject('별솔'), '별솔을');
    expect(koreanSubject('뽀또'), '뽀또가');
    expect(koreanSubject('새싹몬'), '새싹몬이');
  });
}
