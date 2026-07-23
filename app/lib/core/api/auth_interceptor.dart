import 'package:dio/dio.dart';

import 'token_store.dart';

/// refresh 실행 함수. 성공 시 새 access token, 실패 시 null을 돌려준다.
/// 실패 처리(토큰 폐기)는 구현체 책임이다.
typedef RefreshSession = Future<String?> Function();

/// 401 처리 뒤 원래 요청을 한 번 더 보낸다.
typedef RetryRequest = Future<Response<dynamic>> Function(
    RequestOptions options);

/// access token 부착 + 401 시 refresh 후 1회 재시도.
///
/// refresh는 single-flight: 여러 요청이 동시에 401을 받아도 진행 중인
/// refresh Future 하나를 함께 기다린다. refresh 실패 시 토큰은 폐기되고
/// onSessionExpired 콜백으로 로그인 화면 이동을 알린다.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenStore tokenStore,
    required RefreshSession refreshSession,
    required RetryRequest retry,
    void Function()? onSessionExpired,
  })  : _tokenStore = tokenStore,
        _refreshSession = refreshSession,
        _retry = retry,
        _onSessionExpired = onSessionExpired;

  static const _retriedFlag = 'auth_retried';

  final TokenStore _tokenStore;
  final RefreshSession _refreshSession;
  final RetryRequest _retry;
  final void Function()? _onSessionExpired;

  Future<String?>? _inFlightRefresh;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokenStore.accessToken;
    if (token != null && !options.headers.containsKey('Authorization')) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final status = err.response?.statusCode;
    // 로그인·가입·refresh 자체의 401은 자격 증명 오류이므로 refresh하지 않는다.
    final isAuthEndpoint = options.path.contains('/auth/');
    if (status != 401 ||
        isAuthEndpoint ||
        options.extra[_retriedFlag] == true) {
      handler.next(err);
      return;
    }

    final newToken = await _refreshSingleFlight();
    if (newToken == null) {
      _onSessionExpired?.call();
      handler.next(err);
      return;
    }

    options.headers['Authorization'] = 'Bearer $newToken';
    options.extra[_retriedFlag] = true;
    try {
      final response = await _retry(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      if (retryError.response?.statusCode == 401) {
        // 회전 직후에도 거부되면 세션을 살릴 방법이 없다.
        await _tokenStore.clear();
        _onSessionExpired?.call();
      }
      handler.next(retryError);
    } catch (_) {
      handler.next(err);
    }
  }

  Future<String?> _refreshSingleFlight() {
    final inFlight = _inFlightRefresh;
    if (inFlight != null) return inFlight;
    final future = _runRefresh().whenComplete(() => _inFlightRefresh = null);
    _inFlightRefresh = future;
    return future;
  }

  Future<String?> _runRefresh() async {
    try {
      return await _refreshSession();
    } catch (_) {
      return null;
    }
  }
}
