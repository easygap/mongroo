import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mongroo/core/routing/app_shell.dart';
import 'package:mongroo/core/theme/app_theme.dart';

void main() {
  testWidgets('넓은 화면에서도 본문 경로가 탐험 메뉴의 접근성 영역을 숨기지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final router = GoRouter(initialLocation: '/home', routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          for (final path in [
            'home',
            'calendar',
            'garden',
            'explore',
            'report'
          ])
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/$path',
                  builder: (context, state) =>
                      Scaffold(body: Text('$path 본문'))),
            ]),
        ],
      ),
    ]);
    await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light(), routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('탐험'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('탐험'));
    await tester.pumpAndSettle();
    expect(find.text('explore 본문'), findsOneWidget);
    expect(find.bySemanticsLabel('정원'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
}
