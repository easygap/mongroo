import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../data/auth_repository.dart';
import '../domain/user.dart';

enum AuthStatus { restoring, signedIn, signedOut }

class AuthState {
  const AuthState({required this.status, this.user});

  final AuthStatus status;
  final User? user;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final tokenStore = ref.watch(tokenStoreProvider);
    // refresh 실패 등으로 토큰이 폐기되면 로그아웃 상태로 전환한다.
    // 라우터가 이 상태를 보고 로그인 화면으로 redirect한다.
    void onTokenChange() {
      if (!tokenStore.hasAccessToken && state.status == AuthStatus.signedIn) {
        state = const AuthState(status: AuthStatus.signedOut);
      }
    }

    tokenStore.addListener(onTokenChange);
    ref.onDispose(() => tokenStore.removeListener(onTokenChange));
    Future.microtask(_restore);
    return const AuthState(status: AuthStatus.restoring);
  }

  Future<void> _restore() async {
    try {
      final user = await ref.read(authRepositoryProvider).restoreSession();
      state = user == null
          ? const AuthState(status: AuthStatus.signedOut)
          : AuthState(status: AuthStatus.signedIn, user: user);
    } catch (_) {
      state = const AuthState(status: AuthStatus.signedOut);
    }
  }

  /// 성공 시 null, 실패 시 사용자에게 보여줄 서버 message를 돌려준다.
  Future<String?> login(
      {required String email, required String password}) async {
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .login(email: email, password: password);
      state = AuthState(status: AuthStatus.signedIn, user: user);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> signup({
    required String email,
    required String password,
    required String nickname,
  }) async {
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .signup(email: email, password: password, nickname: nickname);
      state = AuthState(status: AuthStatus.signedIn, user: user);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<void> logout() async {
    try {
      await ref.read(authRepositoryProvider).logout();
    } catch (_) {
      // 저장소/플랫폼 오류는 현재 화면의 로그아웃을 막지 않는다. 다음 인증
      // 요청은 signedOut 상태와 세션 경계에서 차단된다.
    } finally {
      // 서버 폐기나 보안 저장소 정리가 실패해도 현재 UI 세션은 즉시 닫는다.
      state = const AuthState(status: AuthStatus.signedOut);
    }
  }

  /// 퀘스트 완료·구매 응답의 최신 잔액을 전역 헤더에 즉시 반영한다.
  void updateSeedBalance(int seedBalance) {
    final user = state.user;
    if (user == null || user.seedBalance == seedBalance) return;
    state = AuthState(
      status: state.status,
      user: user.copyWith(seedBalance: seedBalance),
    );
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
