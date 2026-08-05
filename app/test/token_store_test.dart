import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/api/token_store.dart';

class _ControlledStorage implements RefreshTokenStorage {
  bool failWrite = false;
  bool failClear = false;
  String? value;

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('clear failed');
    value = null;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async {
    if (failWrite) throw StateError('write failed');
    value = token;
  }
}

void main() {
  test('refresh token 저장이 실패하면 access token을 노출하지 않는다', () async {
    final storage = _ControlledStorage()..failWrite = true;
    final store = TokenStore(storage);

    await expectLater(
      store.saveSession(accessToken: 'access', refreshToken: 'refresh'),
      throwsStateError,
    );

    expect(store.hasAccessToken, isFalse);
  });

  test('보안 저장소 삭제가 실패해도 메모리 세션을 닫고 알린다', () async {
    final storage = _ControlledStorage();
    final store = TokenStore(storage);
    await store.saveSession(accessToken: 'access', refreshToken: 'refresh');
    var notifications = 0;
    store.addListener(() => notifications++);
    storage.failClear = true;

    await expectLater(store.clear(), throwsStateError);

    expect(store.hasAccessToken, isFalse);
    expect(notifications, 1);
  });
}
