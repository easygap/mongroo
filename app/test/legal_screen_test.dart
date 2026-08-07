import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/auth/presentation/legal_screen.dart';

void main() {
  Future<void> pumpLegal(
    WidgetTester tester,
    LegalDocument document, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: LegalScreen(document: document),
      ),
    );
    await tester.pump();
  }

  testWidgets('세 법적 문서는 버전과 운영 정보 영역을 함께 표시한다', (tester) async {
    for (final document in LegalDocument.values) {
      await pumpLegal(tester, document);

      expect(find.textContaining('버전 2026-08-05'), findsOneWidget);
      expect(find.text('개발 빌드 안내'), findsOneWidget);
      expect(find.textContaining('운영자 정보 미설정'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('320px 200% 글자에서도 개인정보처리방침이 오버플로우하지 않는다', (tester) async {
    await pumpLegal(
      tester,
      LegalDocument.privacy,
      size: const Size(320, 640),
      textScale: 2,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('개인정보처리방침'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
