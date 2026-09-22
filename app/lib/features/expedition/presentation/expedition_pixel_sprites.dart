import 'dart:ui' show Size;

import 'expedition_pixel_assets.g.dart';
import 'expedition_scene.dart';

/// 도트 스프라이트의 번들 경로를 고르는 규칙.
///
/// 무대와 명령 독이 같은 그림을 써야 하므로 한 파일에 둔다. 경로를 위젯마다
/// 문자열로 묻어 두면 품종이 늘 때 한 군데만 고쳐지고 나머지는 폴백을 탄다.
const expeditionGuardianCodes = <String>{
  'ledger_keeper',
  'echo_keeper',
  'seed_keeper',
  'record_keeper',
};

const expeditionGuardianForRegion = <String, String>{
  'moss_archive': 'ledger_keeper',
  'echo_well': 'echo_keeper',
  'starlight_seed_vault': 'seed_keeper',
  'heartwood_observatory': 'record_keeper',
};

/// 적의 도트 원화 경로.
///
/// 엉킴은 웨이브 코드로, 수호짐승은 코드 또는 지역으로 고른다. 모르는 코드는
/// 첫 지역 것으로 떨어져 빈 무대가 되지 않는다.
String expeditionPixelEnemyAsset({
  required String enemyKind,
  required String enemyCode,
  String? guardianCode,
  String? regionCode,
}) {
  if (enemyKind == 'tangle' && expeditionTangleCodes.contains(enemyCode)) {
    return 'assets/adventure/pixel/tangles/$enemyCode.png';
  }
  final keeper = expeditionGuardianCodes.contains(guardianCode)
      ? guardianCode!
      : expeditionGuardianForRegion[regionCode] ?? 'ledger_keeper';
  return 'assets/adventure/pixel/keepers/$keeper.png';
}

/// 전투에서는 작은 지도용 도트 대신 이미 제작된 상태별 원화를 사용한다.
/// 아직 상태 원화가 없는 보스는 자신의 도트를 그대로 유지한다.
String expeditionEnemyPoseAsset(String mapAsset, String pose) {
  if (mapAsset.contains('/pixel/tangles/')) {
    final code = mapAsset.split('/').last.replaceFirst('.png', '');
    return expeditionTangleAssetPath(code, pose);
  }
  if (mapAsset.endsWith('/keepers/ledger_keeper.png')) {
    return switch (pose) {
      'attack' => expeditionLedgerKeeperAttackAsset,
      'hit' => expeditionLedgerKeeperHitAsset,
      'defeated' || 'release' => expeditionLedgerKeeperDefeatedAsset,
      _ => expeditionLedgerKeeperIdleAsset,
    };
  }
  return mapAsset;
}

/// 아군 전투 도트 경로. 없으면 `null`이고 호출부가 걷기 시트로 떨어진다.
String? expeditionPixelActorAsset(String? speciesCode) {
  final slug = (speciesCode ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) return null;
  final asset = 'assets/adventure/pixel/actors/$slug.png';
  return expeditionPixelAssetSizes.containsKey(asset) ? asset : null;
}

Size expeditionPixelSpriteSize(
  String asset, {
  Size fallback = const Size(48, 44),
}) =>
    expeditionPixelAssetSizes[asset] ?? fallback;
