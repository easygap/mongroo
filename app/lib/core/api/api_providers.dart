import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_client.dart';
import 'sse_client.dart';
import 'token_store.dart';

final refreshTokenStorageProvider = Provider<RefreshTokenStorage>(
  (ref) => SecureRefreshTokenStorage(),
);

final tokenStoreProvider = Provider<TokenStore>((ref) {
  final store = TokenStore(ref.watch(refreshTokenStorageProvider));
  ref.onDispose(store.dispose);
  return store;
});

final dioProvider = Provider<Dio>((ref) {
  final tokenStore = ref.watch(tokenStoreProvider);
  // refresh 실패 시 TokenStore가 비워지고, AuthController가 이를 감지해
  // 로그아웃 상태로 전환하면 라우터 redirect가 로그인 화면으로 보낸다.
  return DioClient.build(tokenStore: tokenStore);
});

final sseClientProvider = Provider<SseClient>(
  (ref) => SseClient(ref.watch(dioProvider)),
);
