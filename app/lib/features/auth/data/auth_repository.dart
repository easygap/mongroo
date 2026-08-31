import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/api/token_store.dart';
import '../../../core/config/app_config.dart';
import '../../../core/error/api_exception.dart';
import '../domain/user.dart';

class AuthRepository {
  AuthRepository(this._dio, this._tokenStore);

  final Dio _dio;
  final TokenStore _tokenStore;

  Future<User> login({required String email, required String password}) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/auth/login',
          data: {'email': email, 'password': password},
        );
        return _applyAuthResponse(response.data!);
      });

  Future<User> signup({
    required String email,
    required String password,
    required String nickname,
    required bool ageOver18,
    required bool termsAccepted,
    required bool privacyAccepted,
    required bool sensitiveDataConsent,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/auth/signup',
          data: {
            'email': email,
            'password': password,
            'nickname': nickname,
            'age_over_18': ageOver18,
            'terms_accepted': termsAccepted,
            'privacy_accepted': privacyAccepted,
            'sensitive_data_consent': sensitiveDataConsent,
            'terms_version': AppConfig.termsVersion,
            'privacy_version': AppConfig.privacyVersion,
            'sensitive_consent_version': AppConfig.sensitiveConsentVersion,
          },
        );
        return _applyAuthResponse(response.data!);
      });

  Future<Map<String, dynamic>> exportAccount() => guardApi(() async {
        final response =
            await _dio.get<Map<String, dynamic>>('/users/me/export');
        return response.data ?? <String, dynamic>{};
      });

  Future<void> deleteAccount({
    required String password,
    required String confirmation,
  }) async {
    await guardApi(() async {
      await _dio.delete<void>(
        '/users/me',
        data: {'password': password, 'confirmation': confirmation},
      );
    });
    try {
      // 서버 삭제가 성공한 뒤 로컬 저장소 오류를 계정 삭제 실패로 오인시키지 않는다.
      // 남은 refresh token도 서버에서 이미 폐기되어 다음 복원 요청에 쓸 수 없다.
      await _tokenStore.clear();
    } catch (_) {
      // TokenStore가 메모리 토큰 제거와 상태 알림은 finally에서 보장한다.
    }
  }

  /// 앱 시작 시 저장된 refresh token으로 세션을 복원한다.
  /// AuthResponse에 user가 포함되므로 별도 프로필 조회가 필요 없다.
  Future<User?> restoreSession() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) return null;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      return await _applyAuthResponse(response.data!);
    } on DioException {
      await _tokenStore.clear();
      return null;
    }
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    try {
      if (refreshToken != null) {
        await _dio.post<void>(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
        );
      }
    } on DioException {
      // 서버 폐기가 실패해도 로컬 토큰은 지운다.
    } finally {
      await _tokenStore.clear();
    }
  }

  /// 이 계정의 모든 로그인 세션을 서버에서 끊는다.
  ///
  /// 지금 쓰는 기기도 함께 끊긴다 — 서버가 폐기하지 않은 세션 전부를 지우고,
  /// 접근 토큰 검사도 매번 세션이 살아 있는지 본다. 잃어버린 기기에 열려
  /// 있는 일기를 닫는 것이 목적이므로 그게 맞는 동작이다.
  ///
  /// `logout()`과 달리 실패를 삼키지 않는다. 여기서 조용히 넘어가면 사용자는
  /// 다른 기기가 끊긴 줄 알고 화면을 닫는다.
  Future<void> logoutAllDevices() async {
    await guardApi(() => _dio.post<void>('/auth/logout-all'));
    try {
      await _tokenStore.clear();
    } catch (_) {
      // 서버가 이미 다 끊었으므로 남은 토큰은 다음 요청에서 어차피 거절된다.
      // 저장소 정리 실패를 `못 끊었다`로 보여 주지 않는다.
    }
  }

  Future<User> _applyAuthResponse(Map<String, dynamic> body) async {
    final access = body['access_token'] as String?;
    final refresh = body['refresh_token'] as String?;
    final userJson = body['user'] as Map<String, dynamic>?;
    if (access == null || refresh == null || userJson == null) {
      throw const ApiException(
        code: 'AUTH_RESPONSE_INVALID',
        message: '로그인 응답 형식이 올바르지 않아요.',
      );
    }
    await _tokenStore.saveSession(accessToken: access, refreshToken: refresh);
    return User.fromJson(userJson);
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) =>
      AuthRepository(ref.watch(dioProvider), ref.watch(tokenStoreProvider)),
);
