import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/api/token_store.dart';
import 'package:mongroo/core/branding/mongroo_brand.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/auth/data/auth_repository.dart';
import 'package:mongroo/features/auth/domain/user.dart';
import 'package:mongroo/features/auth/presentation/auth_scene.dart';
import 'package:mongroo/features/auth/presentation/login_screen.dart';
import 'package:mongroo/features/auth/presentation/signup_screen.dart';
import 'package:mongroo/features/auth/presentation/splash_screen.dart';

class _MemoryRefreshStorage implements RefreshTokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String token) async {}
}

class _DelayedAuthRepository extends AuthRepository {
  _DelayedAuthRepository() : super(Dio(), TokenStore(_MemoryRefreshStorage()));

  final loginGate = Completer<User>();
  final signupGate = Completer<User>();
  int loginCalls = 0;
  int signupCalls = 0;

  @override
  Future<User?> restoreSession() async => null;

  @override
  Future<User> login({required String email, required String password}) {
    loginCalls++;
    return loginGate.future;
  }

  @override
  Future<User> signup({
    required String email,
    required String password,
    required String nickname,
    required bool ageOver18,
    required bool termsAccepted,
    required bool privacyAccepted,
    required bool sensitiveDataConsent,
  }) {
    signupCalls++;
    return signupGate.future;
  }
}

const _authUser = User(
  id: 1,
  email: 'mood@example.com',
  nickname: '무드',
  timezone: 'Asia/Seoul',
  seedBalance: 0,
  streakDays: 0,
);

void main() {
  final mongrooSymbol = find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == MongrooBrandMark.assetPath,
    description: '몽그루 심볼 이미지',
  );

  Future<void> pumpAuth(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(390, 844),
    double textScale = 1,
    ThemeData? theme,
    AuthRepository? repository,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (repository != null)
            authRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await tester.pump();
  }

  test('한글 본문 서체는 외부 네트워크 없이 제공한다', () {
    expect(
        AppTheme.light().textTheme.bodyMedium?.fontFamily, AppTheme.bodyFont);
    expect(AppTheme.dark().textTheme.bodyMedium?.fontFamily, AppTheme.bodyFont);
    expect(
      AppTheme.light().textTheme.bodyMedium?.fontFamilyFallback,
      contains('Noto Sans KR'),
    );
  });

  testWidgets('로그인은 몽그루 심볼과 필수 입력만 간결하게 보여 준다', (tester) async {
    await pumpAuth(tester, const LoginScreen());

    expect(find.text('로그인'), findsWidgets);
    expect(find.text('이메일로 기록을 이어가세요.'), findsOneWidget);
    expect(find.text('CURATOR ACCESS'), findsNothing);
    expect(mongrooSymbol, findsOneWidget);
    expect(find.byType(MongrooPocketMark), findsOneWidget);
    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(find.text('회원가입 없이 3분 체험'), findsOneWidget);
    expect(find.textContaining('이 기기에만 저장'), findsOneWidget);

    final fields =
        tester.widgetList<EditableText>(find.byType(EditableText)).toList();
    expect(fields, hasLength(2));
    expect(fields[0].autofillHints, contains(AutofillHints.email));
    expect(fields[1].autofillHints, contains(AutofillHints.password));
    expect(
      tester.widget<Text>(find.text('몽그루')).style?.fontFamily,
      AppTheme.pixelFont,
    );
  });

  testWidgets('잘못된 로그인 제출은 첫 입력으로 포커스한다', (tester) async {
    await pumpAuth(tester, const LoginScreen());

    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pump();

    expect(find.text('올바른 이메일을 입력해 주세요.'), findsOneWidget);
    expect(find.text('비밀번호는 8자 이상 입력해 주세요.'), findsOneWidget);
    final email = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(email.focusNode.hasFocus, isTrue);
  });

  testWidgets('제출 후 값을 고치면 지난 입력 오류를 즉시 지운다', (tester) async {
    await pumpAuth(tester, const LoginScreen());

    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pump();
    expect(find.text('올바른 이메일을 입력해 주세요.'), findsOneWidget);
    expect(find.text('비밀번호는 8자 이상 입력해 주세요.'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'mood@example.com');
    await tester.enterText(fields.at(1), 'password1');
    await tester.pump();

    expect(find.text('올바른 이메일을 입력해 주세요.'), findsNothing);
    expect(find.text('비밀번호는 8자 이상 입력해 주세요.'), findsNothing);
  });

  testWidgets('지연된 로그인은 키보드와 버튼을 연속 제출해도 한 번만 요청한다', (tester) async {
    final repository = _DelayedAuthRepository();
    await pumpAuth(
      tester,
      const LoginScreen(),
      repository: repository,
    );
    final fields = find.byType(TextFormField);

    await tester.enterText(fields.at(0), 'mood@example.com');
    await tester.enterText(fields.at(1), 'password1');
    await tester.tap(fields.at(1));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pump();

    expect(repository.loginCalls, 1);
    expect(
      tester.widgetList<TextFormField>(fields).every((field) => !field.enabled),
      isTrue,
    );
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .every((field) => !field.focusNode.hasFocus),
      isTrue,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '로그인 중…'),
          )
          .onPressed,
      isNull,
    );

    repository.loginGate.complete(_authUser);
    await tester.pump();
    expect(repository.loginCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('가입 화면은 넓은 화면에서 타이틀과 평면 폼을 나란히 놓는다', (tester) async {
    await pumpAuth(
      tester,
      const SignupScreen(),
      size: const Size(1100, 760),
    );

    expect(find.text('처음 시작하기'), findsOneWidget);
    expect(find.text('계정을 만들고 첫 식물을 받으세요.'), findsOneWidget);
    expect(find.text('NEW SPECIMEN CARD'), findsNothing);
    expect(mongrooSymbol, findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.text('이용약관에 동의해요'), findsOneWidget);
    expect(find.text('개인정보 수집·이용에 동의해요'), findsOneWidget);
    expect(find.text('마음 기록의 민감정보 처리에 동의해요'), findsOneWidget);
    expect(
      tester.getCenter(find.text('몽그루')).dx,
      lessThan(tester.getCenter(find.text('처음 시작하기')).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('지연된 가입 중에는 재제출과 입력 변경, 뒤로가기를 막는다', (tester) async {
    final repository = _DelayedAuthRepository();
    await pumpAuth(
      tester,
      const SignupScreen(),
      repository: repository,
    );
    final fields = find.byType(TextFormField);

    await tester.enterText(fields.at(0), '무드');
    await tester.enterText(fields.at(1), 'mood@example.com');
    await tester.enterText(fields.at(2), 'password1');
    for (var index = 0; index < 4; index++) {
      final checkbox = find.byType(Checkbox).at(index);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pump();
    }
    await tester.ensureVisible(fields.at(2));
    await tester.tap(fields.at(2));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    final submit = find.byType(FilledButton);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(repository.signupCalls, 1);
    expect(
      tester.widgetList<TextFormField>(fields).every((field) => !field.enabled),
      isTrue,
    );
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .every((field) => !field.focusNode.hasFocus),
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<PopScope<dynamic>>(find.byType(PopScope)).canPop,
      isFalse,
    );

    repository.signupGate.complete(_authUser);
    await tester.pump();
    expect(repository.signupCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px과 200% 글자에서도 인증 폼이 오버플로우하지 않는다', (tester) async {
    await pumpAuth(
      tester,
      const LoginScreen(),
      size: const Size(320, 640),
      textScale: 2,
    );

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('로그인'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px 200% 글자에서도 네 가지 가입 확인과 제출 버튼을 읽을 수 있다', (tester) async {
    await pumpAuth(
      tester,
      const SignupScreen(),
      size: const Size(320, 640),
      textScale: 2,
    );

    final sensitiveConsent = find.text('마음 기록의 민감정보 처리에 동의해요');
    await tester.ensureVisible(sensitiveConsent);
    await tester.pump();
    expect(sensitiveConsent, findsOneWidget);
    final submit = find.widgetWithText(FilledButton, '가입하기');
    await tester.ensureVisible(submit);
    await tester.pump();
    expect(submit, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('인증 제출 버튼은 보조 기기에서도 탭할 수 있다', (tester) async {
    final semantics = tester.ensureSemantics();
    Finder submitSemantics(String label) => find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.button == true &&
              widget.properties.label == label,
        );

    await pumpAuth(tester, const LoginScreen());
    final login = submitSemantics('로그인');
    expect(login, findsOneWidget);
    expect(
      tester
          .getSemantics(login)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    await pumpAuth(tester, const SignupScreen());
    final signup = submitSemantics('가입하기');
    expect(signup, findsOneWidget);
    await tester.ensureVisible(signup);
    await tester.pump();
    expect(
      tester
          .getSemantics(signup)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    semantics.dispose();
  });

  testWidgets('스플래시는 몽그루 심볼과 짧은 로딩 안내만 보여 준다', (tester) async {
    await pumpAuth(tester, const SplashScreen(), theme: AppTheme.dark());
    final semantics = tester.ensureSemantics();

    expect(mongrooSymbol, findsOneWidget);
    expect(find.byType(MongrooPocketMark), findsOneWidget);
    expect(find.text('마음을 기록하고 식물을 키워요.'), findsOneWidget);
    expect(find.text('불러오는 중…'), findsOneWidget);
    expect(find.bySemanticsLabel('몽그루를 시작하는 중입니다'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('320px 200% 글자에서도 가입 폼과 동의 항목이 넘치지 않는다',
      (tester) async {
    // 동의 네 줄과 약관 링크가 한 화면에 몰려 있어 큰 글자에서 제일 위험하다.
    await pumpAuth(
      tester,
      const SignupScreen(),
      size: const Size(320, 720),
      textScale: 2,
    );

    expect(find.text('처음 시작하기'), findsOneWidget);
    await tester.ensureVisible(find.text('가입하기'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
