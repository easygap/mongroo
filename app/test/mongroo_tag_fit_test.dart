import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/core/theme/mongroo_ui.dart';

/// `MongrooTag`가 받은 폭 안에서 접히는지 본다.
///
/// 예전에는 `maxWidth`를 넘긴 태그만 글자를 줄였다. 폭을 안 넘긴 태그는 제
/// 자연 크기를 고집해서, 글자를 키우면 부모를 그대로 넘겼다 — 기록 상세의
/// `읽힌 감정` 태그가 320px·200%에서 30px 넘쳤다. 태그는 앱 전체가 쓰는
/// 공용 조각이라 한 곳에서 막는다.
void main() {
  Future<void> pumpTag(
    WidgetTester tester, {
    required double width,
    required double textScale,
    IconData? icon,
    double? maxWidth,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  // Column은 가로 폭을 그대로 물려준다. Row에 그냥 넣으면
                  // 자식이 무한 폭을 받아서 정작 태그가 아니라 바깥 Row가
                  // 넘치므로, 화면에서 실제로 놓이는 모양대로 맞춘다.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MongrooTag(
                        label: '아주 긴 상태 이름이 들어오는 자리',
                        icon: icon,
                        maxWidth: maxWidth,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('폭을 지정하지 않아도 좁은 자리에서 넘치지 않는다', (tester) async {
    await pumpTag(tester, width: 120, textScale: 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('글자 200%에서도 넘치지 않는다', (tester) async {
    // 실제로 터진 조건이다. 폭은 320px 화면의 카드 안쪽에 가깝게 잡았다.
    await pumpTag(tester, width: 232, textScale: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('아이콘이 붙어도 넘치지 않는다', (tester) async {
    await pumpTag(
      tester,
      width: 140,
      textScale: 2,
      icon: Icons.auto_awesome_rounded,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('maxWidth를 준 태그는 그 폭을 넘지 않는다', (tester) async {
    await pumpTag(tester, width: 400, textScale: 1, maxWidth: 140);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(MongrooTag)).width, lessThanOrEqualTo(140));
  });

  testWidgets('접혀도 전체 문장은 스크린리더에 남는다', (tester) async {
    // 눈으로는 말줄임이지만 읽어 주는 말까지 잘리면 정보가 사라진다.
    final handle = tester.ensureSemantics();
    await pumpTag(tester, width: 120, textScale: 2);

    expect(
      find.bySemanticsLabel('아주 긴 상태 이름이 들어오는 자리'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
