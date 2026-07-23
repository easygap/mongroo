import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/api/token_store.dart';
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
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/auth/signup',
          data: {'email': email, 'password': password, 'nickname': nickname},
        );
        return _applyAuthResponse(response.data!);
      });

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
