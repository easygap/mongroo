import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// refresh token 보관소 추상화. 실제 앱은 OS secure storage, 테스트는 메모리 fake.
abstract class RefreshTokenStorage {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureRefreshTokenStorage implements RefreshTokenStorage {
  SecureRefreshTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'mongroo.refresh_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// access token은 메모리에만, refresh token은 secure storage에만 둔다.
/// 토큰 값은 로그·URL 어디에도 남기지 않는다.
class TokenStore extends ChangeNotifier {
  TokenStore(this._refreshStorage);

  final RefreshTokenStorage _refreshStorage;
  String? _accessToken;

  String? get accessToken => _accessToken;
  bool get hasAccessToken => _accessToken != null;

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _refreshStorage.write(refreshToken);
    _accessToken = accessToken;
    notifyListeners();
  }

  Future<String?> readRefreshToken() => _refreshStorage.read();

  Future<void> clear() async {
    _accessToken = null;
    try {
      await _refreshStorage.clear();
    } finally {
      // 보안 저장소가 실패해도 메모리 토큰 제거와 세션 경계 알림은 보장한다.
      notifyListeners();
    }
  }
}
