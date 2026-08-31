import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/expedition/domain/expedition_combat_models.dart';
import 'package:mongroo/features/expedition/presentation/expedition_battle_dock.dart';
import 'package:mongroo/features/expedition/presentation/expedition_signature_audio.dart';

({int width, int height}) _webpCanvasSize(ByteData data) {
  int read24(int offset) =>
      data.getUint8(offset) |
      (data.getUint8(offset + 1) << 8) |
      (data.getUint8(offset + 2) << 16);
  final chunk = String.fromCharCodes(
    List.generate(4, (index) => data.getUint8(12 + index)),
  );
  return switch (chunk) {
    'VP8X' => (width: read24(24) + 1, height: read24(27) + 1),
    'VP8 ' => (
        width: data.getUint16(26, Endian.little) & 0x3fff,
        height: data.getUint16(28, Endian.little) & 0x3fff,
      ),
    'VP8L' => (
        width: (data.getUint32(21, Endian.little) & 0x3fff) + 1,
        height: ((data.getUint32(21, Endian.little) >> 14) & 0x3fff) + 1,
      ),
    _ => (width: 0, height: 0),
  };
}

/// 여섯 성장결 스킬. 서버 `FORM_COMBAT_SKILLS`와 같은 코드여야 한다.
const _kelSkills = <String>[
  'sunny_radiant_heart',
  'rainy_frozen_tide',
  'ember_rage_breaker',
  'moonlit_lonesome_tempest',
  'sparkling_shock_wonder',
  'mosaic_steel_equilibrium',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('행동 코드가 없거나 낯설면 전용 소리를 지어내지 않는다', () {
    expect(expeditionSkillSignatureAsset(null), isNull);
    expect(expeditionSkillSignatureAsset('아직_없는_스킬'), isNull);
    expect(expeditionEnemySignatureAsset(null), isNull);
    expect(expeditionEnemySignatureAsset('아직_없는_공격'), isNull);
    expect(
      expeditionSkillSignatureAsset('sprout_cheer'),
      'adventure/sfx/skill-baby-pot-sprout-cheer.wav',
    );
    expect(
      expeditionEnemySignatureAsset('paper_flurry'),
      'adventure/sfx/enemy-tangled-ledger-paper-flurry.wav',
    );
  });

  test('우리 스킬과 적 공격이 같은 코드를 쓰지 않는다', () {
    final overlap = expeditionSkillSignatureAssets.keys
        .toSet()
        .intersection(expeditionEnemySignatureAssets.keys.toSet());
    expect(overlap, isEmpty);
    final paths = [
      ...expeditionSkillSignatureAssets.values,
      ...expeditionEnemySignatureAssets.values,
    ];
    expect(paths.toSet().length, paths.length, reason: '한 파일을 두 행동이 공유');
  });

  test('여섯 성장결과 안내자 스킬이 모두 자기 소리를 갖는다', () {
    for (final code in [..._kelSkills, 'archive_lantern', 'archive_seal']) {
      expect(
        expeditionSkillSignatureAsset(code),
        isNotNull,
        reason: '$code에 전용 소리가 없어 tier 대체음으로 떨어진다',
      );
    }
  });

  testWidgets('signature 음원 전부를 번들에서 실제로 읽는다', (tester) async {
    final assets = <String>[
      ...expeditionSkillSignatureAssets.values,
      ...expeditionEnemySignatureAssets.values,
    ];
    expect(assets.length, greaterThanOrEqualTo(76));
    for (final asset in assets) {
      final data = await rootBundle.load('assets/$asset');
      expect(data.lengthInBytes, greaterThan(2000), reason: asset);
      expect(data.getUint32(0, Endian.big), 0x52494646, reason: '$asset RIFF');
      expect(data.getUint32(8, Endian.big), 0x57415645, reason: '$asset WAVE');
    }
  });

  testWidgets('여섯 성장결과 안내자의 스킬 아이콘을 번들에서 읽는다', (tester) async {
    const assets = <String>[
      'assets/adventure/skill-icons/emotion/sunny-radiant-heart-v1.webp',
      'assets/adventure/skill-icons/emotion/rainy-frozen-tide-v1.webp',
      'assets/adventure/skill-icons/emotion/ember-rage-breaker-v1.webp',
      'assets/adventure/skill-icons/emotion/moonlit-lonesome-tempest-v1.webp',
      'assets/adventure/skill-icons/emotion/sparkling-shock-wonder-v1.webp',
      'assets/adventure/skill-icons/emotion/mosaic-steel-equilibrium-v1.webp',
      'assets/adventure/skill-icons/archive-guide/archive-lantern-v1.webp',
      'assets/adventure/skill-icons/archive-guide/archive-seal-v1.webp',
    ];

    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(5000), reason: asset);
      expect(_webpCanvasSize(data), (width: 256, height: 256), reason: asset);
    }
  });

  test('아이콘 지도가 여섯 성장결과 안내자 스킬을 덮는다', () {
    for (final code in [..._kelSkills, 'archive_lantern', 'archive_seal']) {
      expect(
        expeditionDockSkillIconAsset(code),
        isNotNull,
        reason: '$code가 효과 시트 조각으로 대체된다',
      );
    }
  });

  test('서버가 준 행동 코드를 전투 이벤트가 그대로 들고 온다', () {
    final party = ExpeditionBattleEvent.fromJson(const {
      'sequence': 1,
      'type': 'party_action',
      'action': 'selected_1',
      'skill_code': 'sunny_radiant_heart',
      'action_name': '찬란한 하트',
      'caption': '빛의 하트가 날아갔어요.',
    });
    expect(party.skillCode, 'sunny_radiant_heart');
    expect(party.action, 'selected_1', reason: '슬롯과 코드는 다른 값이다');

    final enemy = ExpeditionBattleEvent.fromJson(const {
      'sequence': 2,
      'type': 'enemy_action',
      'skill_code': 'paper_flurry',
      'action_name': '종잇장 회오리',
      'caption': '낱장들이 몰려와요.',
    });
    expect(enemy.skillCode, 'paper_flurry');

    // 구버전 응답에는 코드가 없다. 없으면 없는 대로 흘러야 한다.
    final legacy = ExpeditionBattleEvent.fromJson(const {
      'sequence': 3,
      'type': 'party_action',
      'action': 'unique_1',
      'action_name': '새싹 응원',
      'caption': '덩굴이 뻗었어요.',
    });
    expect(legacy.skillCode, isNull);
  });
}
