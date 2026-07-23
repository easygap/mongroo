import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import 'auth_interceptor.dart';
import 'token_store.dart';

/// 요청마다 X-Request-ID를 붙여 서버 로그와 추적을 맞춘다.
class RequestIdInterceptor extends Interceptor {
  static const _uuid = Uuid();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.putIfAbsent('X-Request-ID', () => _uuid.v4());
    handler.next(options);
  }
}

/// POST /auth/refresh를 전용 Dio(인터셉터 없음)로 수행한다.
/// 실패하면 저장된 토큰을 폐기하고 null을 돌려준다.
class TokenRefresher {
  TokenRefresher({required TokenStore tokenStore, required Dio refreshDio})
      : _tokenStore = tokenStore,
        _dio = refreshDio;

  final TokenStore _tokenStore;
  final Dio _dio;

  Future<String?> refresh() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) return null;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final body = response.data;
      final access = body?['access_token'] as String?;
      final rotated = body?['refresh_token'] as String?;
      if (access == null || rotated == null) {
        await _tokenStore.clear();
        return null;
      }
      await _tokenStore.saveSession(accessToken: access, refreshToken: rotated);
      return access;
    } on DioException {
      await _tokenStore.clear();
      return null;
    }
  }
}

/// 앱 전역에서 쓰는 Dio 구성.
class DioClient {
  static Dio build({
    required TokenStore tokenStore,
    void Function()? onSessionExpired,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    final refreshDio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: const Duration(seconds: 15),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    final refresher =
        TokenRefresher(tokenStore: tokenStore, refreshDio: refreshDio);

    dio.interceptors.add(RequestIdInterceptor());
    dio.interceptors.add(
      AuthInterceptor(
        tokenStore: tokenStore,
        refreshSession: refresher.refresh,
        retry: (options) => dio.fetch<dynamic>(options),
        onSessionExpired: onSessionExpired,
      ),
    );
    return dio;
  }
}
