import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/trial_progress.dart';

abstract interface class TrialProgressStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureTrialProgressStorage implements TrialProgressStorage {
  SecureTrialProgressStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'mongroo.local_trial.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class TrialProgressStore {
  const TrialProgressStore(this._storage);

  final TrialProgressStorage _storage;

  Future<TrialProgress> load() async {
    try {
      final encoded = await _storage.read();
      if (encoded == null || encoded.isEmpty) return const TrialProgress();
      return TrialProgress.decode(encoded);
    } catch (_) {
      // 브라우저 저장소가 지워졌거나 이전 스키마가 남았어도 체험 진입을
      // 막지 않는다. 새 체험은 메모리 상태로 계속 진행할 수 있다.
      return const TrialProgress();
    }
  }

  Future<bool> save(TrialProgress progress) async {
    try {
      await _storage.write(progress.encode());
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

final trialProgressStorageProvider = Provider<TrialProgressStorage>(
  (ref) => SecureTrialProgressStorage(),
);

final trialProgressStoreProvider = Provider<TrialProgressStore>(
  (ref) => TrialProgressStore(ref.watch(trialProgressStorageProvider)),
);
