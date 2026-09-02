import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 연출을 만들어 놓고 `pubspec.yaml`에 폴더를 안 적으면, 빌드는 멀쩡히 끝나고
/// 재생할 때가 되어서야 프레임을 못 찾는다. 단위 테스트도 위젯 테스트도 에셋을
/// 실제로 열지 않으니 아무도 안 잡는다.
///
/// 실제로 한 번 그랬다 — 모아결 기본 공격 시트를 새로 구워 manifest까지 넣고
/// pubspec만 빠뜨렸다. 손으로 세 보다 알았다.
void main() {
  test('manifest에 있는 연출 폴더는 pubspec에도 다 적혀 있다', () {
    final manifest = jsonDecode(
      File('assets/adventure/effects/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final pubspec = File('pubspec.yaml').readAsStringSync();

    final declared = RegExp(r'assets/adventure/effects/([^/\s]+)/')
        .allMatches(pubspec)
        .map((match) => match.group(1)!)
        .toSet();

    final needed = <String>{
      for (final effect in manifest['effects'] as List)
        (effect as Map<String, dynamic>)['directory'] as String,
    };

    expect(needed, isNotEmpty);
    expect(
      needed.difference(declared),
      isEmpty,
      reason: 'pubspec에 없는 연출 폴더는 실기에서 프레임을 못 찾는다',
    );
  });

  test('연출 폴더의 프레임 수가 manifest가 적어 둔 수와 같다', () {
    final manifest = jsonDecode(
      File('assets/adventure/effects/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    for (final entry in manifest['effects'] as List) {
      final effect = entry as Map<String, dynamic>;
      final directory =
          Directory('assets/adventure/effects/${effect['directory']}');
      expect(directory.existsSync(), isTrue, reason: '${effect['family']}');

      final frames = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('frame-'))
          .length;
      expect(frames, effect['frame_count'], reason: '${effect['family']}');
    }
  });
}
