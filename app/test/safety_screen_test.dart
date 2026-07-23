import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/safety/presentation/safety_screen.dart';

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
}
