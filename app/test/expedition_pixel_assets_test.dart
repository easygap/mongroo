import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/expedition/presentation/expedition_pixel_assets.g.dart';
import 'package:mongroo/features/expedition/presentation/expedition_pixel_backdrop.dart';
import 'package:mongroo/features/expedition/presentation/expedition_pixel_sprites.dart';
import 'package:mongroo/features/expedition/presentation/expedition_scene.dart';

/// 도트 전투 자산 계약.
///
/// 구운 도트는 `build_pixel_battle_assets.py`가 만들고 크기를 `expedition_pixel_assets.g.dart`에
/// 적는다. 무대는 그 크기에 정수 배율을 곱해 그리므로, 파일이 없거나 크기가
/// 다르면 캐릭터가 엉뚱한 자리에 서거나 아예 안 보인다. 여기서 셋을 대조한다 —
/// 표에 적힌 것이 번들에 있고, PNG이며, 실제 화소 크기가 표와 같은가.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const walkerSpecies = <String>[
    'aloof-pot',
    'baby-pot',
    'cactus',
    'gal-pot',
    'gumiho-pot',
    'handsome-pot',
    'maestro-pot',
    'magical-pot',
    'marten-pot',
    'ninja-pot',
    'nurse-pot',
    'pretty-pot',
    'restorer-pot',
    'student-pot',
    'sunflower',
    'tsundere-pot',
    'zombie-pot',
  ];

  test('도트 자산 표는 배경 8·엉킴 12·수호짐승 4·아군 17을 전부 짚는다', () {
    for (final asset in ExpeditionPixelBackdrops.all) {
      expect(expeditionPixelAssetSizes, contains(asset), reason: asset);
    }
    expect(ExpeditionPixelBackdrops.all, hasLength(8));
    for (final code in expeditionTangleCodes) {
      final asset = expeditionPixelEnemyAsset(enemyKind: 'tangle', enemyCode: code);
      expect(asset, 'assets/adventure/pixel/tangles/$code.png');
      expect(expeditionPixelAssetSizes, contains(asset), reason: asset);
    }
    for (final code in expeditionGuardianCodes) {
      final asset = expeditionPixelEnemyAsset(
        enemyKind: 'guardian',
        enemyCode: '',
        guardianCode: code,
      );
      expect(asset, 'assets/adventure/pixel/keepers/$code.png');
      expect(expeditionPixelAssetSizes, contains(asset), reason: asset);
    }
    for (final species in walkerSpecies) {
      final asset = expeditionPixelActorAsset(species);
      expect(asset, 'assets/adventure/pixel/actors/$species.png');
    }
    // 품종 코드는 밑줄로도 온다. 슬러그로 맞춰 같은 그림을 찾는다.
    expect(
      expeditionPixelActorAsset('baby_pot'),
      'assets/adventure/pixel/actors/baby-pot.png',
    );
    // 안내자처럼 전투 도트가 없는 품종은 `null`이라 걷기 시트로 떨어진다.
    expect(expeditionPixelActorAsset('archive_guide'), isNull);
    expect(expeditionPixelActorAsset(null), isNull);
  });

  test('지역을 모르는 수호전은 첫 지역 짐승으로, 지역이 있으면 그 지역 짐승으로', () {
    expect(
      expeditionPixelEnemyAsset(enemyKind: 'guardian', enemyCode: ''),
      'assets/adventure/pixel/keepers/ledger_keeper.png',
    );
    expect(
      expeditionPixelEnemyAsset(
        enemyKind: 'guardian',
        enemyCode: '',
        regionCode: 'starlight_seed_vault',
      ),
      'assets/adventure/pixel/keepers/seed_keeper.png',
    );
    // 모르는 엉킴 코드는 빈 무대가 아니라 첫 지역 짐승으로 떨어진다.
    expect(
      expeditionPixelEnemyAsset(enemyKind: 'tangle', enemyCode: 'unknown'),
      'assets/adventure/pixel/keepers/ledger_keeper.png',
    );
  });

  test('표에 적힌 도트는 전부 번들에 있고 PNG 헤더의 크기가 표와 같다', () async {
    expect(expeditionPixelAssetSizes, isNotEmpty);
    for (final entry in expeditionPixelAssetSizes.entries) {
      final data = await rootBundle.load(entry.key);
      expect(data.lengthInBytes, greaterThan(200), reason: entry.key);
      // PNG signature
      expect(data.getUint32(0, Endian.big), 0x89504E47, reason: entry.key);
      expect(data.getUint32(4, Endian.big), 0x0D0A1A0A, reason: entry.key);
      // IHDR width/height
      final width = data.getUint32(16, Endian.big);
      final height = data.getUint32(20, Endian.big);
      expect(width.toDouble(), entry.value.width, reason: entry.key);
      expect(height.toDouble(), entry.value.height, reason: entry.key);
    }
  });

  test('아군·엉킴·수호짐승의 키는 무대 급에 맞게 층이 진다', () {
    double heightOf(String asset) => expeditionPixelAssetSizes[asset]!.height;
    for (final species in walkerSpecies) {
      final height = heightOf(expeditionPixelActorAsset(species)!);
      expect(height, inInclusiveRange(52, 66), reason: species);
    }
    for (final code in expeditionTangleCodes) {
      final height = heightOf(
        expeditionPixelEnemyAsset(enemyKind: 'tangle', enemyCode: code),
      );
      expect(height, inInclusiveRange(40, 84), reason: code);
    }
    for (final code in expeditionGuardianCodes) {
      final height = heightOf(
        expeditionPixelEnemyAsset(
          enemyKind: 'guardian',
          enemyCode: '',
          guardianCode: code,
        ),
      );
      expect(height, inInclusiveRange(66, 92), reason: code);
    }
    for (final asset in ExpeditionPixelBackdrops.all) {
      final size = expeditionPixelAssetSizes[asset]!;
      expect(
        asset.endsWith('-portrait.png') ? size.height > size.width : size.width > size.height,
        isTrue,
        reason: asset,
      );
    }
  });
}
