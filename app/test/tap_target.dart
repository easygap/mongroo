import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 화면에 그려진 조작부가 48dp보다 작지 않은지 잰다.
///
/// Android 핵심 앱 품질 지침과 대화면 지침이 48dp를, Apple 접근성 지침이
/// 44pt를 최소 입력 영역으로 잡는다. 둘 중 큰 쪽을 따른다 - 작은 쪽에 맞추면
/// 한 플랫폼에서만 통과한다.
///
/// 지금까지는 달력 한 칸, 전투 슬롯, 지도 랜드마크처럼 **눈에 띈 곳만** 하나씩
/// 검사했다. 그래서 옆에 나란히 있는 아이콘 버튼이 48인데 칩만 44인 상태가
/// 남아 있었다. 화면 단위로 한 번에 훑는다.
List<String> smallTapTargets(WidgetTester tester) {
  const minimum = 48.0;
  const types = <Type>[
    FilterChip,
    ChoiceChip,
    ActionChip,
    IconButton,
    Checkbox,
    Switch,
    Radio,
  ];
  final offenders = <String>[];
  for (final type in types) {
    for (final element in find.byType(type).evaluate()) {
      final finder = find.byElementPredicate((candidate) => candidate == element);
      final size = tester.getSize(finder);
      // 화면 밖으로 접힌 위젯은 0으로 잡힌다. 그건 크기 문제가 아니다.
      if (size.isEmpty) continue;
      if (size.width < minimum || size.height < minimum) {
        offenders.add(
          '$type ${size.width.toStringAsFixed(1)}×${size.height.toStringAsFixed(1)}',
        );
      }
    }
  }
  return offenders;
}

/// 48dp보다 작은 조작부가 없어야 한다.
void expectTapTargets(WidgetTester tester, {required String screen}) {
  final offenders = smallTapTargets(tester);
  expect(
    offenders,
    isEmpty,
    reason: '$screen에 48dp보다 작은 조작부가 있다:\n${offenders.join('\n')}',
  );
}
