import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/api/token_store.dart';
import 'package:mongroo/core/error/api_exception.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/auth/data/auth_repository.dart';
import 'package:mongroo/features/auth/presentation/account_screen.dart';
import 'package:mongroo/features/expedition/data/expedition_settings_store.dart';

class _MemoryStorage implements RefreshTokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String token) async {}
}

/// 기기 저장소 없이 도는 설정 저장소. 보안 저장소는 테스트에서 채널이 없다.
class _MemorySettingsStorage implements ExpeditionSettingsStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String encoded) async => value = encoded;

  @override
  Future<void> clear() async => value = null;
}

class _AccountRepository extends AuthRepository {
  _AccountRepository() : super(Dio(), TokenStore(_MemoryStorage()));

  int exportCalls = 0;
  int deleteCalls = 0;
  int logoutAllCalls = 0;
  ApiException? logoutAllError;

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
  Future<void> logoutAllDevices() async {
    logoutAllCalls++;
    final error = logoutAllError;
    if (error != null) throw error;
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
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          expeditionSettingsStorageProvider
              .overrideWithValue(_MemorySettingsStorage()),
        ],
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

  testWidgets('모든 기기 로그아웃은 이 기기도 끊긴다고 먼저 알린다', (tester) async {
    final repository = _AccountRepository();
    await pumpAccount(tester, repository);

    final button = find.byKey(const Key('account-logout-all'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    // 누르자마자 끊지 않는다. 이 기기까지 로그아웃된다는 사실이 먼저다.
    expect(repository.logoutAllCalls, 0);
    expect(find.text('모든 기기에서 로그아웃할까요?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('이 기기도 함께 로그아웃돼요'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('account-logout-all-confirm')));
    // 성공하면 버튼이 진행 표시로 남는다. 라우터가 로그인 화면으로 옮길
    // 때까지 도는 표시라 `pumpAndSettle`은 영영 끝나지 않는다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(repository.logoutAllCalls, 1);
    expect(find.text('로그아웃하는 중…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('서버가 못 끊으면 이유를 보여 주고 로그인 상태를 지킨다', (tester) async {
    // 여기서 조용히 화면만 닫으면 사용자는 다른 기기가 끊긴 줄 안다.
    final repository = _AccountRepository()
      ..logoutAllError = const ApiException(
        code: 'AUTH_TOKEN_INVALID',
        message: '다시 로그인해 주세요.',
      );
    await pumpAccount(tester, repository);

    final button = find.byKey(const Key('account-logout-all'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-logout-all-confirm')));
    await tester.pumpAndSettle();

    expect(repository.logoutAllCalls, 1);
    expect(find.text('다시 로그인해 주세요.'), findsOneWidget);
    expect(find.byKey(const Key('account-logout-all')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('소리는 전투에 들어가지 않고도 계정 화면에서 끌 수 있다', (tester) async {
    // 이 값은 전투뿐 아니라 던전 발걸음·지도 확정음·모험 탭 cue·발견음을
    // 함께 다스린다. 그런데 바꾸는 자리가 전투 HUD 안에만 있었다.
    await pumpAccount(tester, _AccountRepository());

    final button = find.byKey(const Key('account-sound-mode'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(find.text('탐험 소리 · 음악·효과음'), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(find.text('탐험 소리 · 효과음만'), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(find.text('탐험 소리 · 소리 꺼짐'), findsOneWidget);

    // 세 단계를 돌면 처음으로 돌아온다 - 전투 시트와 같은 순환이다.
    await tester.tap(button);
    await tester.pump();
    expect(find.text('탐험 소리 · 음악·효과음'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    // 화면이 길어져 버튼이 접힌 아래에 있다. 스크롤이 프레임에 반영돼야
    // 탭 좌표가 뷰포트 안으로 들어온다.
    await tester.pumpAndSettle();
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
