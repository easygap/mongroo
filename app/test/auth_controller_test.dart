import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
