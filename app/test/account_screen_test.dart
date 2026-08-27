import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/api/token_store.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/auth/data/auth_repository.dart';
import 'package:mongroo/features/auth/presentation/account_screen.dart';

class _MemoryStorage implements RefreshTokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String token) async {}
}

class _AccountRepository extends AuthRepository {
  _AccountRepository() : super(Dio(), TokenStore(_MemoryStorage()));

  int exportCalls = 0;
  int deleteCalls = 0;

  @override
  Future<Map<String, dynamic>> exportAccount() async {
    exportCalls++;
    return {
      'format_version': 1,
      'profile': {'email': 'mood@example.com'},
      'data': {
        'mood_entries': [
          {'content': '개인적인 기록'}
        ],
      },
    };
  }

  @override
  Future<void> deleteAccount({
    required String password,
    required String confirmation,
  }) async {
    deleteCalls++;
  }

  @override
  Future<Never?> restoreSession() async => null;
}

void main() {
  Future<void> pumpAccount(
    WidgetTester tester,
    _AccountRepository repository, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: const AccountScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('가입한 뒤에도 약관과 처리방침을 다시 읽을 수 있다', (tester) async {
    // 세 문서는 가입 화면에만 링크가 있었다. 가입하고 나면 내가 무엇에
    // 동의했는지 앱 안에서 확인할 길이 없었다.
    await pumpAccount(tester, _AccountRepository());

    for (final entry in const [
      ('terms', '이용약관'),
      ('privacy', '개인정보처리방침'),
      ('sensitive', '민감정보 처리 동의'),
    ]) {
      final button = find.byKey(Key('account-legal-${entry.$1}'));
      expect(button, findsOneWidget, reason: entry.$2);
      await tester.ensureVisible(button);
      expect(
        find.descendant(of: button, matching: find.text(entry.$2)),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('내보내기는 비밀 데이터 경고 뒤에만 복사 버튼을 보여 준다', (tester) async {
    final repository = _AccountRepository();
    await pumpAccount(tester, repository);

    await tester.tap(find.widgetWithText(FilledButton, '내 데이터 내보내기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.exportCalls, 1);
    expect(find.text('내보내기 준비 완료'), findsOneWidget);
    expect(find.textContaining('다른 앱이 읽을 수 있으니'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '클립보드에 복사'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('영구 삭제는 현재 비밀번호와 정확한 확인 문구를 요구한다', (tester) async {
    final repository = _AccountRepository();
    await pumpAccount(tester, repository);

    final deleteButton = find.widgetWithText(OutlinedButton, '계정 영구 삭제');
    await tester.ensureVisible(deleteButton);
    await tester.pump();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    var submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '영구 삭제'),
    );
    expect(submit.onPressed, isNull);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'password123');
    await tester.enterText(fields.at(1), '몽그루 탈퇴');
    await tester.pump();
    submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '영구 삭제'),
    );
    expect(submit.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, '영구 삭제'));
    await tester.pump();
    expect(repository.deleteCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('계정 화면에서 번들 서체 라이선스를 확인할 수 있다', (tester) async {
    final repository = _AccountRepository();
    await pumpAccount(tester, repository);

    final licenses = find.widgetWithText(OutlinedButton, '오픈소스 라이선스');
    await tester.ensureVisible(licenses);
    await tester.tap(licenses);
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('라이선스'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px 200% 글자에서도 계정 화면과 삭제 확인이 오버플로우하지 않는다', (tester) async {
    final repository = _AccountRepository();
    await pumpAccount(
      tester,
      repository,
      size: const Size(320, 640),
      textScale: 2,
    );

    final deleteButton = find.widgetWithText(OutlinedButton, '계정 영구 삭제');
    await tester.dragUntilVisible(
      deleteButton,
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pump();
    await tester.tap(deleteButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('계정을 영구 삭제할까요?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
