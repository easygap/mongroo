import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/api/api_providers.dart';
import 'package:mongroo/core/api/token_store.dart';
import 'package:mongroo/features/auth/data/auth_repository.dart';
import 'package:mongroo/features/auth/domain/user.dart';
import 'package:mongroo/features/auth/presentation/auth_controller.dart';

class _MemoryRefreshStorage implements RefreshTokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String token) async {}
}

class _FailingLogoutRepository extends AuthRepository {
  _FailingLogoutRepository()
      : super(Dio(), TokenStore(_MemoryRefreshStorage()));

  final Completer<User?> _restore = Completer<User?>();

  @override
  Future<User?> restoreSession() => _restore.future;

  @override
  Future<void> logout() => throw StateError('secure storage unavailable');
}

class _SessionRepository extends AuthRepository {
  _SessionRepository(this.store) : super(Dio(), store);

  final TokenStore store;
  final Completer<User?> _restore = Completer<User?>();

  @override
  Future<User?> restoreSession() => _restore.future;

  @override
  Future<void> logout() async => store.clear();
}

void main() {
  test('로컬 저장소 오류가 나도 UI 세션은 로그아웃된다', () async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FailingLogoutRepository()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).logout();

    expect(container.read(authControllerProvider).status, AuthStatus.signedOut);
    expect(container.read(authControllerProvider).user, isNull);
  });

  test('세션이 끊겨 나온 것과 스스로 로그아웃한 것을 구분한다', () async {
    // 두 경우 다 로그인 화면으로 가지만, 누른 적 없는데 나온 쪽은 왜 나왔는지
    // 알려 줘야 한다. 아무 말 없으면 앱이 고장 난 것처럼 보인다.
    final store = TokenStore(_MemoryRefreshStorage());
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(_SessionRepository(store)),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(authControllerProvider.notifier);

    // 로그인 상태를 만들고 토큰이 폐기되는 상황(refresh까지 실패)을 흉내 낸다.
    notifier.state = const AuthState(
      status: AuthStatus.signedIn,
      user: User(
        id: 1,
        email: 'qa@example.com',
        nickname: '준수',
        timezone: 'Asia/Seoul',
        seedBalance: 0,
        streakDays: 0,
      ),
    );
    await store.saveSession(accessToken: 'a', refreshToken: 'r');
    await store.clear();

    var state = container.read(authControllerProvider);
    expect(state.status, AuthStatus.signedOut);
    expect(state.sessionExpired, isTrue);

    // 다시 로그인하려는 순간 안내는 역할을 다한다.
    await notifier.login(email: 'qa@example.com', password: 'x');
    expect(container.read(authControllerProvider).sessionExpired, isFalse);

    // 스스로 누른 로그아웃은 안내를 띄우지 않는다.
    notifier.state = const AuthState(status: AuthStatus.signedIn);
    await notifier.logout();
    state = container.read(authControllerProvider);
    expect(state.status, AuthStatus.signedOut);
    expect(state.sessionExpired, isFalse);
  });
}
