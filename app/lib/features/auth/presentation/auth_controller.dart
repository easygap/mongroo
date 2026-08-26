import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../data/auth_repository.dart';
import '../domain/user.dart';

enum AuthStatus { restoring, signedIn, signedOut }

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.sessionExpired = false,
  });

  final AuthStatus status;
  final User? user;

  /// 사용자가 로그아웃을 누른 것이 아니라 세션이 끊겨서 나온 상태.
  ///
  /// 아무 말 없이 로그인 화면으로 떨어지면 앱이 고장 난 것처럼 보인다.
  /// 로그인 화면이 이 값을 보고 왜 나왔는지 한 줄로 알려 준다.
  final bool sessionExpired;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final tokenStore = ref.watch(tokenStoreProvider);
    // refresh 실패 등으로 토큰이 폐기되면 로그아웃 상태로 전환한다.
    // 라우터가 이 상태를 보고 로그인 화면으로 redirect한다.
    void onTokenChange() {
      if (!tokenStore.hasAccessToken && state.status == AuthStatus.signedIn) {
        // 여기로 오는 것은 refresh까지 실패해 토큰이 폐기된 경우뿐이다.
        // 사용자가 누른 로그아웃은 `logout()`이 직접 상태를 바꾼다.
        state = const AuthState(
          status: AuthStatus.signedOut,
          sessionExpired: true,
        );
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
    // 로그인을 다시 시도하는 순간 만료 안내는 역할을 다했다. 남겨 두면
    // 비밀번호를 틀렸을 때 두 문장이 같이 떠서 어느 쪽이 원인인지 흐려진다.
    _clearSessionExpiryNotice();
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
    required bool ageOver18,
    required bool termsAccepted,
    required bool privacyAccepted,
    required bool sensitiveDataConsent,
  }) async {
    _clearSessionExpiryNotice();
    try {
      final user = await ref.read(authRepositoryProvider).signup(
            email: email,
            password: password,
            nickname: nickname,
            ageOver18: ageOver18,
            termsAccepted: termsAccepted,
            privacyAccepted: privacyAccepted,
            sensitiveDataConsent: sensitiveDataConsent,
          );
      state = AuthState(status: AuthStatus.signedIn, user: user);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  void _clearSessionExpiryNotice() {
    if (state.sessionExpired) {
      state = AuthState(status: state.status, user: state.user);
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

  Future<String?> deleteAccount({
    required String password,
    required String confirmation,
  }) async {
    try {
      await ref.read(authRepositoryProvider).deleteAccount(
            password: password,
            confirmation: confirmation,
          );
      state = const AuthState(status: AuthStatus.signedOut);
      return null;
    } on ApiException catch (error) {
      return error.message;
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
