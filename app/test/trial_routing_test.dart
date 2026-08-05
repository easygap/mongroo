import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/auth/presentation/auth_controller.dart';
import 'package:mongroo/features/trial/data/trial_progress_store.dart';
import 'package:mongroo/main.dart';

class _SignedOutAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedOut);
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
}
