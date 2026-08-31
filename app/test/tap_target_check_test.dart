import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';

import 'tap_target.dart';

/// 48dp 검사 자신을 검사한다.
///
/// 이 검사는 화면 열다섯 곳이 기대는 자리다. 조용히 아무것도 안 잡게 되면
/// 모든 화면이 초록불인 채로 조작부가 작아질 수 있다. 실제로 한 번은 반대로
/// 틀렸다 — `CheckboxListTile`의 네모만 재서 멀쩡한 가입 화면을 위반으로
/// 잡았다. 그래서 잡아야 할 것과 잡으면 안 되는 것을 둘 다 세워 둔다.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('기본 버튼은 통과한다', (tester) async {
    await pump(tester, TextButton(onPressed: () {}, child: const Text('확인')));
    expect(smallTapTargets(tester), isEmpty);
  });

  testWidgets('높이를 줄인 버튼은 걸린다', (tester) async {
    await pump(
      tester,
      TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(30, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
        onPressed: () {},
        child: const Text('x'),
      ),
    );
    expect(smallTapTargets(tester), isNotEmpty);
  });

  testWidgets('보정을 끈 아이콘 버튼은 걸린다', (tester) async {
    // `tapTargetSize`가 padded면 아이콘을 아무리 작게 그려도 눌리는 상자는
    // 48로 채워진다. 그래서 아이콘 크기를 줄이는 것만으로는 위반이 아니다 -
    // 보정을 직접 끈 경우가 진짜 위반이고, 이 검사가 잡아야 하는 것도 그쪽이다.
    await pump(
      tester,
      IconButton(
        iconSize: 12,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(24, 24),
          padding: EdgeInsets.zero,
        ),
        onPressed: () {},
        icon: const Icon(Icons.close),
      ),
    );
    expect(smallTapTargets(tester), isNotEmpty);
  });

  testWidgets('아이콘만 작고 보정이 살아 있으면 통과한다', (tester) async {
    await pump(
      tester,
      IconButton(
        iconSize: 12,
        onPressed: () {},
        icon: const Icon(Icons.close),
      ),
    );
    expect(smallTapTargets(tester), isEmpty);
  });

  testWidgets('체크박스 줄은 네모가 작아도 통과한다', (tester) async {
    // `CheckboxListTile`은 네모를 40으로 줄이고 줄 전체를 누르게 한다.
    // 네모를 재면 위반, 줄을 재면 통과다. 줄을 재는 쪽이 맞다.
    await pump(
      tester,
      SizedBox(
        width: 320,
        child: CheckboxListTile(
          value: true,
          onChanged: (_) {},
          title: const Text('약관에 동의합니다'),
        ),
      ),
    );
    expect(tester.getSize(find.byType(Checkbox)).height, lessThan(48));
    expect(smallTapTargets(tester), isEmpty);
  });

  testWidgets('줄 자체가 낮으면 그때는 걸린다', (tester) async {
    // 줄을 잰다고 해서 무조건 봐주는 것은 아니다.
    await pump(
      tester,
      SizedBox(
        width: 320,
        height: 32,
        child: CheckboxListTile(
          value: true,
          onChanged: (_) {},
          title: const Text('낮은 줄'),
        ),
      ),
    );
    expect(smallTapTargets(tester), isNotEmpty);
  });
}
