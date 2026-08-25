import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 번들에 실제로 들어 있는 자산 목록.
///
/// 없는 파일을 그냥 요청하면 웹에서 콘솔에 404가 남는다. 품종별 원화처럼
/// **있으면 쓰고 없으면 떨어지는** 자산이 늘면서 그 404가 정상 동작 중에도
/// 매번 찍히기 시작했다. 먼저 매니페스트를 보고 있는 것만 요청한다.
class BundledAssets {
  const BundledAssets._();

  static Set<String>? _assets;
  static Future<Set<String>>? _loading;

  /// 매니페스트를 아직 못 읽었으면 `null`. 이때는 걸러 내지 않고 그대로
  /// 시도한다 — 첫 프레임에 그림이 사라지는 것보다 404 한 번이 낫다.
  static Set<String>? get assetsOrNull => _assets;

  static Future<void> ensureLoaded() {
    final pending = _loading;
    if (pending != null) return pending;
    return _loading = AssetManifest.loadFromAssetBundle(rootBundle)
        .then((manifest) => _assets = manifest.listAssets().toSet())
        // 매니페스트를 못 읽는 환경(일부 위젯 테스트)에서는 거르지 않는다.
        .onError<Object>((_, __) => _assets = <String>{});
  }

  /// 번들에 있는 경로만 남긴다. 매니페스트를 못 읽었으면 원본 그대로.
  static List<String> filter(List<String> paths) {
    final assets = _assets;
    if (assets == null || assets.isEmpty) return paths;
    final kept = paths.where(assets.contains).toList(growable: false);
    return kept.isEmpty ? const <String>[] : kept;
  }

  @visibleForTesting
  static void overrideAssetsForTest(Set<String>? assets) {
    _assets = assets;
    _loading = assets == null ? null : Future<Set<String>>.value(assets);
  }
}
