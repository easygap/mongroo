import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 전투 표준 장비 설정을 기기에 남긴다.
///
/// 소리를 끈 사용자가 앱을 다시 열 때마다 다시 꺼야 한다면 그건 설정이 아니라
/// 매번 치러야 하는 비용이다. 접근성 설정은 한 번 켜면 계속 유지되는 것이
/// 실제 사용 양상이므로(자막을 켠 사용자의 95% 이상이 영구 유지한다),
/// 음악·효과음 단계는 반드시 기기에 남는다.
///
/// 계정 동기화는 서버 설정과 함께 붙일 때까지 미룬다. 그때까지도 기기 안에서는
/// 선택이 지켜진다.
abstract interface class ExpeditionSettingsStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureExpeditionSettingsStorage implements ExpeditionSettingsStorage {
  SecureExpeditionSettingsStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'mongroo.battle_settings.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// 저장 실패가 전투를 막지 않게 감싸는 얇은 층.
///
/// 브라우저 저장소가 막혀 있거나 이전 스키마가 남아 있어도 기본 설정으로
/// 조용히 계속 진행한다. 설정은 편의이지 진행 조건이 아니다.
class ExpeditionSettingsStore {
  const ExpeditionSettingsStore(this._storage);

  final ExpeditionSettingsStorage _storage;

  Future<String?> load() async {
    try {
      final encoded = await _storage.read();
      if (encoded == null || encoded.isEmpty) return null;
      return encoded;
    } catch (_) {
      return null;
    }
  }

  Future<bool> save(String encoded) async {
    try {
      await _storage.write(encoded);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> clear() async {
    try {
      await _storage.clear();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final expeditionSettingsStorageProvider = Provider<ExpeditionSettingsStorage>(
  (ref) => SecureExpeditionSettingsStorage(),
);

final expeditionSettingsStoreProvider = Provider<ExpeditionSettingsStore>(
  (ref) => ExpeditionSettingsStore(ref.watch(expeditionSettingsStorageProvider)),
);
