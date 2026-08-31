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
    // 평범한 버튼이 제일 많은데 그동안 한 번도 안 쟀다. Material 기본
    // minimumSize는 64×40이고 48은 tapTargetSize가 채워 준다 - 스타일로
    // 높이를 직접 줄인 버튼은 그 보정을 잃는다.
    TextButton,
    OutlinedButton,
    FilledButton,
    ElevatedButton,
  ];
  final offenders = <String>[];
  for (final type in types) {
    for (final element in find.byType(type).evaluate()) {
      final finder = find.byElementPredicate((candidate) => candidate == element);
      // `CheckboxListTile`류는 체크박스를 일부러 40dp로 줄인다 - 누르는 자리가
      // 네모가 아니라 줄 전체이기 때문이다. 네모만 재면 멀쩡한 화면이
      // 위반으로 잡힌다(가입 동의 네 줄이 그랬다). 줄이 있으면 줄을 잰다.
      final row = _enclosingListTile(element);
      final size = tester.getSize(row ?? finder);
      // 화면 밖으로 접힌 위젯은 0으로 잡힌다. 그건 크기 문제가 아니다.
      if (size.isEmpty) continue;
      if (size.width < minimum || size.height < minimum) {
        final what = row == null ? '$type' : '$type(줄 전체)';
        offenders.add(
          '$what ${size.width.toStringAsFixed(1)}×${size.height.toStringAsFixed(1)}',
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

/// 조작부를 감싼 `ListTile`. 없으면 null.
///
/// `CheckboxListTile`·`SwitchListTile`·`RadioListTile`은 안쪽 조작부를
/// `shrinkWrap`으로 줄이고 누르는 자리를 줄 전체로 넓힌다. 그래서 실제로
/// 재야 하는 것은 줄이다.
Finder? _enclosingListTile(Element control) {
  Element? found;
  control.visitAncestorElements((ancestor) {
    if (ancestor.widget is ListTile) {
      found = ancestor;
      return false;
    }
    return true;
  });
  if (found == null) return null;
  return find.byElementPredicate((candidate) => candidate == found);
}
