import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/routing/app_router.dart';
import 'package:mongroo/features/auth/presentation/auth_controller.dart';
import 'package:mongroo/features/trial/data/trial_progress_store.dart';
import 'package:mongroo/main.dart';

class _SignedOutAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedOut);
}

class _SignedInAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedIn);
}

class _MemoryTrialStorage implements TrialProgressStorage {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

void main() {
  testWidgets('로그아웃 상태에서도 체험 경로는 로그인으로 되돌아가지 않는다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedOutAuthController.new),
          trialProgressStorageProvider.overrideWithValue(
            _MemoryTrialStorage(),
          ),
        ],
        child: const MongrooApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final openTrial = find.byKey(const Key('open-local-trial'));
    expect(openTrial, findsOneWidget);
    await tester.ensureVisible(openTrial);
    await tester.tap(openTrial);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();

    expect(find.text('몽그루 3분 체험'), findsOneWidget);
    expect(find.text('회원가입 없는 로컬 체험'), findsOneWidget);
    expect(find.byKey(const Key('trial-start')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('없는 주소로 들어오면 한국어 안내와 돌아갈 길을 보여 준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_SignedInAuthController.new),
        trialProgressStorageProvider.overrideWithValue(_MemoryTrialStorage()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MongrooApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    container.read(routerProvider).go('/museum/지워진-주소');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    // go_router 기본 화면은 영어로 `Page Not Found`와 예외 문자열을 그대로
    // 보여 준다. 웹은 주소창을 고칠 수 있어서 실제로 닿는 화면이다.
    expect(find.text('Page Not Found'), findsNothing);
    expect(find.textContaining('GoException'), findsNothing);
    expect(find.text('여기엔 아무것도 없어요'), findsOneWidget);
    expect(find.byKey(const Key('route-not-found-home')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
