import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/api/auth_interceptor.dart';
import 'package:mongroo/core/api/token_store.dart';

/// 네트워크 없이 응답을 만드는 dio 어댑터 fake.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

class InMemoryRefreshStorage implements RefreshTokenStorage {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

ResponseBody _jsonBody(String json, int status) => ResponseBody.fromString(
      json,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  group('AuthInterceptor single-flight refresh', () {
    late TokenStore tokenStore;
    late Dio dio;
    late int refreshCalls;
    late int sessionExpiredCalls;

    Dio buildDio({required Future<String?> Function() refreshSession}) {
      final client = Dio(BaseOptions(baseUrl: 'http://fake.local/api/v1'));
      client.interceptors.add(
        AuthInterceptor(
          tokenStore: tokenStore,
          refreshSession: refreshSession,
          retry: (options) => client.fetch<dynamic>(options),
          onSessionExpired: () => sessionExpiredCalls++,
        ),
      );
      return client;
    }

    setUp(() async {
      tokenStore = TokenStore(InMemoryRefreshStorage());
      refreshCalls = 0;
      sessionExpiredCalls = 0;
      await tokenStore.saveSession(
          accessToken: 'token-old', refreshToken: 'refresh-old');
    });

    test('동시에 401을 받은 두 요청이 refresh를 한 번만 실행한다', () async {
      dio = buildDio(
        refreshSession: () async {
          refreshCalls++;
          // 실제 refresh HTTP 왕복을 흉내 내는 지연.
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tokenStore.saveSession(
              accessToken: 'token-new', refreshToken: 'refresh-new');
          return 'token-new';
        },
      );
      dio.httpClientAdapter = FakeHttpAdapter((options) async {
        final auth = options.headers['Authorization'] as String?;
        if (auth == 'Bearer token-old') {
          return _jsonBody(
            '{"code": "AUTH_TOKEN_EXPIRED", "message": "만료", '
            '"details": {}, "request_id": "r1"}',
            401,
          );
        }
        if (auth == 'Bearer token-new') {
          return _jsonBody('{"ok": true}', 200);
        }
        return _jsonBody('{"code": "AUTH_TOKEN_INVALID"}', 401);
      });

      final results = await Future.wait([
        dio.get<Map<String, dynamic>>('/plants/me'),
        dio.get<Map<String, dynamic>>('/moods/calendar'),
      ]);

      expect(refreshCalls, 1, reason: 'refresh는 single-flight로 1회만');
      expect(results[0].statusCode, 200);
      expect(results[1].statusCode, 200);
      expect(results[0].data?['ok'], true);
      expect(sessionExpiredCalls, 0);
      expect(tokenStore.accessToken, 'token-new');
    });

    test('refresh 실패 시 두 요청 모두 401로 끝나고 세션 만료를 알린다', () async {
      dio = buildDio(
        refreshSession: () async {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tokenStore.clear();
          return null;
        },
      );
      dio.httpClientAdapter = FakeHttpAdapter((options) async {
        return _jsonBody(
          '{"code": "AUTH_TOKEN_EXPIRED", "message": "만료", '
          '"details": {}, "request_id": "r2"}',
          401,
        );
      });

      final results = await Future.wait([
        dio
            .get<Map<String, dynamic>>('/plants/me')
            .then<Object>((r) => r, onError: (Object e) => e),
        dio
            .get<Map<String, dynamic>>('/moods/calendar')
            .then<Object>((r) => r, onError: (Object e) => e),
      ]);

      expect(refreshCalls, 1);
      expect(sessionExpiredCalls, greaterThanOrEqualTo(1));
      for (final result in results) {
        expect(result, isA<DioException>());
        expect((result as DioException).response?.statusCode, 401);
      }
      expect(tokenStore.accessToken, isNull);
    });

    test('auth 경로의 401(자격 증명 오류)은 refresh를 타지 않는다', () async {
      dio = buildDio(
        refreshSession: () async {
          refreshCalls++;
          return 'token-new';
        },
      );
      dio.httpClientAdapter = FakeHttpAdapter((options) async {
        return _jsonBody(
          '{"code": "AUTH_INVALID_CREDENTIALS", "message": "이메일 또는 비밀번호가 달라요.", '
          '"details": {}, "request_id": "r3"}',
          401,
        );
      });

      await expectLater(
        dio.post<Map<String, dynamic>>('/auth/login',
            data: {'email': 'a@b.c', 'password': 'x'}),
        throwsA(isA<DioException>()),
      );
      expect(refreshCalls, 0);
    });

    test('refresh 성공 후에도 401이면 재차 refresh하지 않고 세션을 정리한다', () async {
      dio = buildDio(
        refreshSession: () async {
          refreshCalls++;
          await tokenStore.saveSession(
              accessToken: 'token-new', refreshToken: 'refresh-new');
          return 'token-new';
        },
      );
      // 어떤 토큰이든 401: 회전 직후에도 서버가 거부하는 상황.
      dio.httpClientAdapter = FakeHttpAdapter((options) async {
        return _jsonBody('{"code": "AUTH_TOKEN_INVALID"}', 401);
      });

      await expectLater(
        dio.get<Map<String, dynamic>>('/plants/me'),
        throwsA(isA<DioException>()),
      );
      expect(refreshCalls, 1);
      expect(sessionExpiredCalls, 1);
      expect(tokenStore.accessToken, isNull);
    });
  });
}
