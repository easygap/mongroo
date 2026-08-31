import 'package:audioplayers/audioplayers.dart';

part 'expedition_signature_audio.g.dart';

/// 이 스킬만의 소리가 있으면 그 경로를, 없으면 `null`.
///
/// 없을 때 억지로 비슷한 파일을 고르지 않는다. 호출부가 tier 대체음으로
/// 떨어져야 "소리가 있는 스킬"과 "아직 없는 스킬"이 섞이지 않는다.
String? expeditionSkillSignatureAsset(String? code) =>
    code == null ? null : expeditionSkillSignatureAssets[code];

/// 이 엉킴·수호짐승 공격만의 소리.
String? expeditionEnemySignatureAsset(String? code) =>
    code == null ? null : expeditionEnemySignatureAssets[code];

/// 필요할 때만 올리는 signature 음원 창고.
///
/// 전투 공용음 31개는 전투가 열릴 때 미리 pool에 올린다. signature는 그렇게 못
/// 한다 — 70개를 다 올리면 한 판에서 실제로 쓰는 것은 대여섯인데 나머지를 위해
/// 디코드와 메모리를 치른다. 그래서 **처음 울린 소리만** pool을 만들고, 그
/// pool을 [maxPools]개까지 들고 있는다. 한 전투의 등장인물 수가 그 정도라
/// 두 번째 사용부터는 다시 로드하지 않는다.
///
/// 가장 오래 안 쓴 것부터 버린다. 지금 싸우는 상대의 소리가 살아남고, 지난
/// 지역에서 한 번 들은 소리가 먼저 나간다.
class ExpeditionSignatureAudioCache {
  ExpeditionSignatureAudioCache({
    this.maxPools = 12,
    AudioContext? audioContext,
  }) : _audioContext = audioContext;

  final int maxPools;
  final AudioContext? _audioContext;

  /// 삽입 순서를 그대로 쓰는 LRU. Dart의 `Map`은 삽입 순서를 지키므로
  /// 다시 쓸 때 지웠다 넣으면 맨 뒤로 간다.
  final Map<String, AudioPool> _pools = {};
  final Map<String, Future<AudioPool?>> _loading = {};
  bool _disposed = false;

  /// 지금 pool로 들고 있는 음원 경로. 테스트가 LRU 동작을 확인한다.
  Iterable<String> get residentAssets => _pools.keys;

  Future<void> play(String asset, {double volume = .6}) async {
    if (_disposed) return;
    final pool = await _pool(asset);
    if (pool == null || _disposed) return;
    try {
      await pool.start(volume: volume);
    } on Object {
      // 소리는 거들 뿐이다. 판정과 연출은 이미 지나갔다.
    }
  }

  Future<AudioPool?> _pool(String asset) {
    final resident = _pools.remove(asset);
    if (resident != null) {
      _pools[asset] = resident;
      return Future.value(resident);
    }
    return _loading[asset] ??= _load(asset);
  }

  Future<AudioPool?> _load(String asset) async {
    try {
      final pool = await AudioPool.create(
        source: AssetSource(asset),
        minPlayers: 1,
        maxPlayers: 2,
        audioContext: _audioContext,
      );
      if (_disposed) {
        await pool.dispose();
        return null;
      }
      _pools[asset] = pool;
      await _evictOverflow();
      return pool;
    } on Object {
      // 파일이 없거나 브라우저가 디코드를 막았다. 다음에 다시 시도하지 않게
      // 실패도 기억해 두면 좋겠지만, 자동 재생 차단은 사용자가 화면을 한 번
      // 만지면 풀리므로 다음 기회를 남긴다.
      return null;
    } finally {
      _loading.remove(asset);
    }
  }

  Future<void> _evictOverflow() async {
    while (_pools.length > maxPools) {
      final oldest = _pools.keys.first;
      final pool = _pools.remove(oldest);
      try {
        await pool?.dispose();
      } on Object {
        // 이미 정리된 pool이면 할 일이 없다.
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final pools = _pools.values.toList();
    _pools.clear();
    for (final pool in pools) {
      try {
        await pool.dispose();
      } on Object {
        // 정리 실패가 화면 종료를 막지 않는다.
      }
    }
  }
}
