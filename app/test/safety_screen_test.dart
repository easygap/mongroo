import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/safety/presentation/safety_screen.dart';

import 'tap_target.dart';

void main() {
  testWidgets('다크 모드와 200% 글자 크기에서도 안전 안내가 읽힌다', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const SafetyScreen(),
      ),
    );

    final context = tester.element(find.byType(SafetyScreen));
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      scaffold.backgroundColor,
      Theme.of(context).colorScheme.surfaceContainerLowest,
    );
    expect(find.text('지금 도움받을 수 있는 곳'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px 200% 글자에서도 연락처가 넘치지 않고 크게 남는다', (tester) async {
    // 위기 상황에서 여는 화면이라 가장 좁은 폭과 가장 큰 글자에서 먼저
    // 확인한다. 여기서 버튼이 잘리면 전화를 걸 수 없다.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const SafetyScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('자살예방 상담전화 · 109'), findsOneWidget);
    expectTapTargets(tester, screen: '안전 지원');
    expect(tester.takeException(), isNull);
  });
}
