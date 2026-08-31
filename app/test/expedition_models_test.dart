import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/expedition/data/expedition_settings_store.dart';
import 'package:mongroo/features/expedition/domain/expedition_models.dart';
import 'package:mongroo/features/expedition/presentation/expedition_controller.dart';
import 'package:mongroo/features/expedition/presentation/expedition_action_cue.dart';
import 'package:mongroo/features/expedition/presentation/expedition_battle_dock.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_audio.dart';
import 'package:mongroo/features/expedition/presentation/expedition_walk_path.dart';
import 'package:mongroo/features/expedition/presentation/expedition_walk_area.dart';
import 'package:mongroo/features/expedition/presentation/expedition_walk_masks.dart';
import 'package:mongroo/features/expedition/presentation/expedition_free_walk.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_overlay.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_effect_catalog.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_hud.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_effects.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_sprites.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_timeline.dart';
import 'package:mongroo/features/expedition/presentation/expedition_scene.dart';
import 'package:mongroo/features/expedition/presentation/moss_archive_scene.dart';
import 'package:mongroo/features/expedition/presentation/expedition_screen.dart';

String? _assetNameOf(ImageProvider<Object> provider) {
  if (provider is AssetImage) return provider.assetName;
  if (provider is ResizeImage && provider.imageProvider is AssetImage) {
    return (provider.imageProvider as AssetImage).assetName;
  }
  return null;
}

({int width, int height}) _webpCanvasSize(ByteData data) {
  int read24(int offset) =>
      data.getUint8(offset) |
      (data.getUint8(offset + 1) << 8) |
      (data.getUint8(offset + 2) << 16);
  final chunk = String.fromCharCodes(
    List.generate(4, (index) => data.getUint8(12 + index)),
  );
  return switch (chunk) {
    'VP8X' => (
        width: read24(24) + 1,
        height: read24(27) + 1,
      ),
    'VP8 ' => (
        width: data.getUint16(26, Endian.little) & 0x3fff,
        height: data.getUint16(28, Endian.little) & 0x3fff,
      ),
    'VP8L' => (
        width: (data.getUint32(21, Endian.little) & 0x3fff) + 1,
        height: ((data.getUint32(21, Endian.little) >> 14) & 0x3fff) + 1,
      ),
    _ => throw FormatException('지원하지 않는 WebP 청크: $chunk'),
  };
}

Map<String, dynamic> _snapshotJson() => {
      'run': {
        'id': 7,
        'mode': 'heart_resonance',
        'status': 'active',
        'phase': 'awaiting_event',
        'revision': 1,
        'current_node_code': 'wet_labels',
        'trail_light': 9,
        'resolve': 6,
        'objective_secured': false,
        'reward_eligible': true,
      },
      'region': {
        'code': 'moss_archive',
        'name': '이끼 기억서고',
        'description': '첫 탐험지',
        'recommended_stage': 2,
        'reward': {'exp': 6, 'seeds': 2},
      },
      'party': [
        {
          'id': 11,
          'name': '새싹몬',
          'species': {'code': 'baby-pot', 'name': '새싹몬'},
          'stage': 2,
          'form': 'sunny',
          'outfit_key': 'city-night',
          'stats': {'care': 7, 'focus': 6, 'courage': 6, 'insight': 5},
          'is_guide': false,
          'skills': {
            'signature': {
              'code': 'baby-pot.sprout-cheer',
              'name': '새싹 응원',
              'description': '이번 우회의 결의 손실을 한 번 막아요.',
              'phases': ['awaiting_event'],
              'modes': [
                {'code': 'guard', 'label': '결의 지키기'},
              ],
              'used': false,
              'available': true,
            },
            'form': {
              'code': 'sunny.share-warmth',
              'name': '온기 나누기',
              'description': '돌봄 판정에 +3을 더하거나 결의 1을 회복해요.',
              'phases': ['exploring', 'awaiting_event'],
              'modes': [
                {'code': 'care_bonus', 'label': '돌봄 +3'},
                {'code': 'restore_resolve', 'label': '결의 1 회복'},
              ],
              'used': false,
              'available': true,
            },
          },
        },
      ],
      'map': {
        'nodes': [
          {
            'code': 'entrance',
            'name': '기억 던전 입구',
            'type': 'entrance',
            'status': 'visited',
            'x': .08,
            'y': .5,
            'cost': 0,
            'scene_key': 'dungeon_gate',
            'scene_label': '폐허 던전',
            'scene_description': '온실 아래 던전으로 내려가는 입구예요.',
            'depth_label': '지하 1층 · 관문',
            'threat_level': 1,
          },
          {
            'code': 'wet_labels',
            'name': '침수 표찰 동굴',
            'type': 'event',
            'status': 'visited',
            'x': .28,
            'y': .27,
            'cost': 1,
            'scene_key': 'flooded_cave',
            'scene_label': '침수 동굴',
            'scene_description': '수정빛 물길 위로 젖은 표찰이 흘러가요.',
            'depth_label': '지하 2층 · 수몰 구역',
            'threat_level': 2,
          },
          {
            'code': 'ledger_keeper',
            'status': 'hidden',
            'type': 'unknown',
          },
        ],
        'edges': [
          ['entrance', 'wet_labels'],
          ['wet_labels', 'ledger_keeper'],
        ],
      },
      'current_event': {
        'code': 'wet_label_order',
        'title': '번진 이름들',
        'text': '젖은 표찰의 글자를 어떤 방식으로 되살릴까요?',
        'spotlight_member_id': 11,
        'encounter': {
          'kind': 'guardian',
          'enemy_name': '돌비늘 장부지기',
          'enemy_max_guard': 100,
          'attack_name': '기록 파동',
          'telegraph': '앞발의 문양이 차오르면 파동이 밀려와요.',
          'damage_target': '결의',
        },
        'choices': [
          {
            'code': 'trace_ink',
            'label': '번진 잉크의 결을 따라간다',
            'effect_key': 'insight_arc',
            'guard_damage': 68,
            'previews': [
              {
                'member_id': 11,
                'label': '관찰 5 · 기준 8',
                'forecast': '도전',
              },
            ],
          },
        ],
      },
      'last_resolution': null,
      'available_actions': [
        {'type': 'choice'},
        {'type': 'skill'},
      ],
      'run_thread': {
        'title': '숨을 쉬는 장부',
        'stage': 'seed',
        'current_text': '서고 전체가 천천히 숨 쉬어요.',
      },
      'memory': {
        'discoveries': [],
        'outcomes': [],
        'relationship_cue': {
          'title': '출발 전의 약속',
          'caption': '새싹몬과 기록 안내자가 같은 속도로 첫 길을 걸어요.',
        },
      },
      'loot': [],
      'summary': null,
    };

Map<String, dynamic> _battleSnapshotJson() {
  final raw = _snapshotJson();
  final run = raw['run'] as Map<String, dynamic>;
  run['current_node_code'] = 'ledger_keeper';
  final nodes = (raw['map'] as Map<String, dynamic>)['nodes'] as List;
  nodes[2] = {
    'code': 'ledger_keeper',
    'name': '장부지기 소굴',
    'type': 'guardian',
    'status': 'visited',
    'x': .72,
    'y': .48,
    'cost': 2,
    'scene_key': 'monster_den',
    'scene_label': '수호자 소굴',
    'scene_description': '돌비늘 장부지기가 출구를 막고 있어요.',
    'depth_label': '지하 4층 · 수호 구역',
    'threat_level': 3,
  };
  final party = raw['party'] as List;
  party.add({
    'id': 12,
    'name': '해답이',
    'species': {'code': 'student-pot', 'name': '학생화분'},
    'stage': 3,
    'form': 'moonlit',
    'stats': {'care': 4, 'focus': 7, 'courage': 5, 'insight': 8},
    'is_guide': false,
    'skills': {
      'signature': {
        'code': 'student-pot.calculated-answer',
        'name': '계산된 해답',
        'description': '다음 행동을 준비해요.',
        'phases': ['awaiting_event'],
        'modes': <Map<String, dynamic>>[],
        'used': false,
        'available': true,
      },
      'form': {
        'code': 'moonlit.read-path',
        'name': '냉정한 관찰',
        'description': '길을 읽어요.',
        'phases': ['awaiting_event'],
        'modes': <Map<String, dynamic>>[],
        'used': false,
        'available': true,
      },
    },
  });
  Map<String, dynamic> kit({
    required String affinity,
    required String affinityLabel,
    required String skillName,
    required String effect,
  }) {
    final isBabyPot = affinity == 'care' && skillName == '새싹 응원';
    Map<String, dynamic> skill({
      required String slot,
      required String code,
      required String name,
      required String source,
      required String skillEffect,
      int power = 20,
      int focusCost = 2,
      String? element,
      String? elementLabel,
      int cooldownTurns = 1,
      int cooldownRemaining = 0,
    }) =>
        {
          'slot': slot,
          'code': code,
          'name': name,
          'description': slot == 'unique_1'
              ? '캐릭터의 개성을 살린 고유 행동이에요.'
              : '$name의 전투 효과를 발휘해요.',
          'power': power,
          'raw_power': power,
          'power_scale_bp': source == 'signature' ? 11600 : 10000,
          'tier_power_bp': 12200,
          'power_neutral': power,
          'matchup':
              (element ?? (affinity == 'care' ? 'nature' : 'ink')) == 'ink'
                  ? 'resist'
                  : 'weak',
          'matchup_bp':
              (element ?? (affinity == 'care' ? 'nature' : 'ink')) == 'ink'
                  ? 6000
                  : 15000,
          'effect_power_bp': 10000,
          'focus_cost': focusCost,
          'affinity': affinity,
          'affinity_label': affinityLabel,
          'effect_key': affinity == 'care' ? 'care_vines' : 'insight_arc',
          'effect': skillEffect,
          'source': source,
          'available': true,
          'unlock_level': source == 'skillbook' ? 23 : 3,
          'tier': 3,
          'tier_label': source == 'signature' ? '마음 만개' : '완전 공명',
          'level': 25,
          'rarity': 1,
          'element': element ?? (affinity == 'care' ? 'nature' : 'ink'),
          'element_label': elementLabel ?? (affinity == 'care' ? '생명' : '먹빛'),
          'elements': [element ?? (affinity == 'care' ? 'nature' : 'ink')],
          'kel': (element ?? (affinity == 'care' ? 'nature' : 'ink')) == 'ink'
              ? 'mosaic'
              : 'sunny',
          'kel_label':
              (element ?? (affinity == 'care' ? 'nature' : 'ink')) == 'ink'
                  ? '모아결'
                  : '햇살결',
          'kels': [
            (element ?? (affinity == 'care' ? 'nature' : 'ink')) == 'ink'
                ? 'mosaic'
                : 'sunny',
          ],
          'kel_labels': [
            (element ?? (affinity == 'care' ? 'nature' : 'ink')) == 'ink'
                ? '모아결'
                : '햇살결',
          ],
          'damage_type': 'projectile',
          'damage_type_label': '투사체',
          'motion_profile': '$code.motion',
          'vfx_family': '$code.vfx',
          if (source == 'signature') 'fusion_variant': '$code.sunny.$slot.t3',
          if (source == 'signature')
            'fusion_vfx_family': 'emotion-fusion.sunny-radiance',
          'cooldown_turns': cooldownTurns,
          'cooldown_remaining': cooldownRemaining,
          'ready_round': cooldownRemaining > 0 ? 3 : 0,
        };

    final unique1 = skill(
      slot: 'unique_1',
      code: isBabyPot ? 'sprout_cheer' : effect,
      name: skillName,
      source: 'signature',
      skillEffect: effect,
    );
    return {
      'version': 6,
      'kel_map_version': 1,
      'level': 25,
      'rarity': 1,
      'signature_tier': 3,
      'signature_scale_bp': 11600,
      'basic_scale_bp': 10800,
      'emotion_discipline': affinity == 'care' ? '햇살 심광' : '달그늘 폭풍',
      'primary_element': affinity == 'care' ? 'light' : 'wind',
      'primary_element_label': affinity == 'care' ? '빛' : '바람',
      'secondary_element': affinity == 'care' ? 'heart' : 'moon',
      'secondary_element_label': affinity == 'care' ? '하트' : '달',
      'affinity': affinity,
      'affinity_label': affinityLabel,
      'basic': {
        'code': 'attack',
        'name': '공명 공격',
        'description': '집중력 1을 얻고 장벽을 공격해요.',
        'power': 13,
        'raw_power': 12,
        'power_scale_bp': 10800,
        'tier_power_bp': 12200,
        'power_neutral': 13,
        'matchup': affinity == 'care' ? 'weak' : 'neutral',
        'matchup_bp': affinity == 'care' ? 15000 : 10000,
        'effect_power_bp': 10000,
        'focus_delta': 1,
        'affinity': affinity,
        'affinity_label': affinityLabel,
        'effect_key': affinity == 'care' ? 'care_vines' : 'insight_arc',
        'element': affinity == 'care' ? 'light' : 'wind',
        'element_label': affinity == 'care' ? '빛' : '바람',
        'elements': [affinity == 'care' ? 'light' : 'wind'],
        'kel': affinity == 'care' ? 'sunny' : 'moonlit',
        'kel_label': affinity == 'care' ? '햇살결' : '달빛결',
        'kels': [affinity == 'care' ? 'sunny' : 'moonlit'],
        'kel_labels': [affinity == 'care' ? '햇살결' : '달빛결'],
        'damage_type': 'projectile',
        'damage_type_label': '투사체',
        'motion_profile': 'emotion.basic',
        'vfx_family': 'emotion.basic.vfx',
      },
      'skill': unique1,
      'unique_skills': [
        unique1,
        skill(
          slot: 'unique_2',
          code: isBabyPot ? 'root_embrace' : '${effect}_second',
          name: '$skillName II',
          source: 'signature',
          skillEffect: 'heal_lowest',
          power: 17,
          cooldownTurns: 3,
          cooldownRemaining: 2,
        ),
      ],
      'selected_skills': [
        skill(
          slot: 'selected_1',
          code: isBabyPot ? 'sunny_warmth_share' : '${affinity}_emotion',
          name: '$affinityLabel 성장결',
          source: 'emotion',
          skillEffect: 'focus_refund',
          power: 15,
          element: affinity == 'care' ? 'light' : 'wind',
          elementLabel: affinity == 'care' ? '빛' : '바람',
          cooldownTurns: 2,
        ),
        skill(
          slot: 'selected_2',
          code: 'field_note_echo',
          name: '현장 기록: 되울림',
          source: 'skillbook',
          skillEffect: 'study_refund',
          power: 13,
          element: 'ink',
          elementLabel: '먹빛',
          cooldownTurns: 3,
        ),
      ],
      'guard': {
        'code': 'guard',
        'name': '마음 지키기',
        'description': '피해를 두 칸 막고 집중력을 얻어요.',
        'guard': 2,
        'focus_delta': 1,
      },
    };
  }

  raw['current_event'] = {
    'code': 'ledger_keeper_guardian',
    'title': '돌비늘 장부지기',
    'text': '장부지기의 약점을 읽고 행동을 지휘하세요.',
    'spotlight_member_id': 11,
    'encounter': {
      'kind': 'guardian',
      'enemy_name': '돌비늘 장부지기',
      'enemy_max_guard': 100,
      'attack_name': '장부 발톱',
      'telegraph': '맨 앞 대원을 노려요.',
      'damage_target': '탐험대',
    },
    'battle': {
      'version': 2,
      'kel_map_version': 1,
      'status': 'active',
      'round': 1,
      'max_rounds': 6,
      'focus': 1,
      'max_focus': 5,
      'enemy': {
        'name': '돌비늘 장부지기',
        'guard': 100,
        'max_guard': 100,
        'weakness': 'care',
        'weakness_label': '돌봄',
        'weak_element': 'light',
        'weak_element_label': '빛',
        'resist_element': 'steel',
        'resist_element_label': '강철',
        'weak_kel': 'sunny',
        'weak_kel_label': '햇살결',
        'resist_kel': 'mosaic',
        'resist_kel_label': '모아결',
        'intent': {
          'code': 'ledger_claw',
          'name': '장부 발톱',
          'telegraph': '맨 앞 대원을 노려요.',
          'target': 'front',
          'power': 1,
        },
      },
      'party': [
        {
          'member_id': 11,
          'name': '새싹몬',
          'position': 0,
          'is_guide': false,
          'species_code': 'baby-pot',
          'form': 'sunny',
          'hp': 3,
          'max_hp': 3,
          'guard': 0,
          'kit': kit(
            affinity: 'care',
            affinityLabel: '돌봄',
            skillName: '새싹 응원',
            effect: 'shield_all',
          ),
        },
        {
          'member_id': 12,
          'name': '해답이',
          'position': 1,
          'is_guide': false,
          'species_code': 'student-pot',
          'form': 'moonlit',
          'hp': 2,
          'max_hp': 3,
          'guard': 0,
          'kit': kit(
            affinity: 'insight',
            affinityLabel: '관찰',
            skillName: '계산된 해답',
            effect: 'study_refund',
          ),
        },
      ],
      'last_exchange': <Map<String, dynamic>>[],
      'battle_log': ['장부지기가 길을 막았어요.'],
    },
    'choices': <Map<String, dynamic>>[],
  };
  raw['last_combat_exchange'] = [
    {
      'sequence': 0,
      'type': 'party_action',
      'kel_map_version': 1,
      'member_id': 11,
      'actor_name': '새싹몬',
      'action': 'skill',
      'action_name': '새싹 응원',
      'effect_key': 'care_vines',
      'motion_profile': 'baby-pot.vine-cast',
      'vfx_family': 'baby-pot.care-vines',
      'kel_fallback_family': 'kel.sunny',
      'motion': {
        'profile': 'baby-pot.vine-cast',
        'archetype': 'channel',
        'facing': 'right',
        'travel_ratio': .08,
        'impact_shake_px': 2.5,
        'total_ms': 760,
        'phases': [
          {'name': 'anticipation', 'ms': 170},
          {'name': 'release', 'ms': 100},
          {'name': 'travel', 'ms': 130},
          {'name': 'contact', 'ms': 80},
          {'name': 'reaction', 'ms': 120},
          {'name': 'recovery', 'ms': 160},
        ],
      },
      'fusion_variant': 'baby-pot.sunny.unique_1.t3',
      'fusion_vfx_family': 'emotion-fusion.sunny-radiance',
      'weakness_hit': true,
      'damage': 100,
      'enemy_guard_before': 100,
      'enemy_guard_after': 0,
      'focus_after': 0,
      'caption': '수호 장벽을 깨뜨렸어요.',
    },
  ];
  raw['available_actions'] = [
    {'type': 'combat_turn'},
    {'type': 'retreat'},
  ];
  return raw;
}

class _FakeExpeditionController extends ExpeditionController {
  _FakeExpeditionController(this.initial);

  final ExpeditionUiState initial;
  int combatRequests = 0;
  List<ExpeditionCombatCommand> lastCombatCommands = const [];
  int combatActionRequests = 0;
  List<ExpeditionCombatCommand> combatActionLog = const [];

  @override
  ExpeditionUiState build() => initial;

  void replace(ExpeditionUiState next) => state = next;

  @override
  Future<bool> resolveCombatTurn(List<ExpeditionCombatCommand> commands) async {
    combatRequests += 1;
    lastCombatCommands = List.unmodifiable(commands);
    return true;
  }

  @override
  Future<bool> resolveCombatAction(ExpeditionCombatCommand command) async {
    combatActionRequests += 1;
    combatActionLog = List.unmodifiable([...combatActionLog, command]);
    return true;
  }
}

void main() {
  _freeWalkTests();
  _walkAreaTests();
  _walkRouteTests();
  _regionSceneTests();
  _deepSurveyTests();
  _combatChoiceContractTests();
  testWidgets('모든 탐험 장면 에셋을 앱 번들에서 읽는다', (tester) async {
    expect(expeditionSceneKeys, hasLength(7));
    expect(expeditionEnvironmentAssets, hasLength(8));
    for (final asset in expeditionEnvironmentAssets) {
      expect(asset, endsWith('.webp'));
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(100000), reason: asset);
    }
    expect(expeditionCombatAssets, hasLength(4));
    for (final asset in expeditionCombatAssets) {
      expect(asset, endsWith('.webp'));
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(50000), reason: asset);
      expect(data.getUint32(0, Endian.big), 0x52494646, reason: asset);
      expect(data.getUint32(8, Endian.big), 0x57454250, reason: asset);
      expect(data.getUint32(12, Endian.big), 0x56503858, reason: asset);
      expect(data.getUint8(20) & 0x10, 0x10, reason: '$asset 알파 채널');
    }
    expect(expeditionTangleCombatAssets, hasLength(48));
    for (final asset in expeditionTangleCombatAssets) {
      expect(asset, endsWith('.webp'));
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(40000), reason: asset);
      expect(data.getUint32(0, Endian.big), 0x52494646, reason: asset);
      expect(data.getUint32(8, Endian.big), 0x57454250, reason: asset);
      expect(data.getUint32(12, Endian.big), 0x56503858, reason: asset);
      expect(data.getUint8(20) & 0x10, 0x10, reason: '$asset 알파 채널');
    }
    expect(mossArchiveMapAsset, endsWith('terrain-v3.webp'));
    final terrain = await rootBundle.load(mossArchiveMapAsset);
    expect(terrain.lengthInBytes, greaterThan(300000));
    for (final asset in {
      ...expeditionEnvironmentAssets,
      ...expeditionCombatAssets,
      ...expeditionTangleCombatAssets,
      mossArchiveMapAsset,
    }) {
      final mobileAsset = expeditionMobileAssetPath(asset);
      final data = await rootBundle.load(mobileAsset);
      expect(data.lengthInBytes, greaterThan(10000), reason: mobileAsset);
      final size = _webpCanvasSize(data);
      expect(
        size.width,
        expeditionTangleCombatAssets.contains(asset)
            ? expeditionMobileTangleWidth
            : expeditionCombatAssets.contains(asset)
                ? expeditionMobileGuardianWidth
                : expeditionMobileSceneWidth,
        reason: mobileAsset,
      );
      if (expeditionCombatAssets.contains(asset) ||
          expeditionTangleCombatAssets.contains(asset)) {
        expect(
          data.getUint8(20) & 0x10,
          0x10,
          reason: '$mobileAsset 알파 채널',
        );
      }
    }
  });

  testWidgets('수동 전투 효과음을 앱 번들에서 읽는다', (tester) async {
    const assets = <String>[
      'assets/adventure/sfx/combat-command.wav',
      'assets/adventure/sfx/combat-hit.wav',
      'assets/adventure/sfx/combat-weakness.wav',
      'assets/adventure/sfx/combat-enemy.wav',
      'assets/adventure/sfx/combat-guard.wav',
      'assets/adventure/sfx/combat-victory.wav',
      'assets/adventure/sfx/combat-defeat.wav',
      'assets/adventure/sfx/skill-tier-light.wav',
      'assets/adventure/sfx/skill-tier-full.wav',
      'assets/adventure/sfx/skill-tier-signature.wav',
      'assets/adventure/sfx/boss-phase-break.wav',
      'assets/adventure/sfx/contact-leaf.wav',
      'assets/adventure/sfx/contact-paper.wav',
      'assets/adventure/sfx/contact-water.wav',
      'assets/adventure/sfx/contact-wood.wav',
      'assets/adventure/sfx/contact-stone.wav',
      'assets/adventure/sfx/contact-guard.wav',
      'assets/adventure/sfx/telegraph-leaf.wav',
      'assets/adventure/sfx/telegraph-paper.wav',
      'assets/adventure/sfx/telegraph-water.wav',
      'assets/adventure/sfx/telegraph-wood.wav',
      'assets/adventure/sfx/telegraph-stone.wav',
      'assets/adventure/sfx/release-moss-archive.wav',
      'assets/adventure/sfx/release-echo-well.wav',
      'assets/adventure/sfx/release-starlight-seed-vault.wav',
      'assets/adventure/sfx/release-heartwood-observatory.wav',
    ];

    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(7000), reason: asset);
      expect(data.getUint32(0, Endian.big), 0x52494646, reason: '$asset RIFF');
      expect(data.getUint32(8, Endian.big), 0x57415645, reason: '$asset WAVE');
    }
  });

  test('전투 재질·예고·지역 해방음을 서버 코드에 맞춰 고른다', () {
    expect(expeditionContactSound('paper'), ExpeditionCombatSound.contactPaper);
    expect(expeditionContactSound('guard'), ExpeditionCombatSound.contactGuard);
    expect(expeditionContactSound('unknown'), isNull);
    expect(
      expeditionTelegraphSound('water'),
      ExpeditionCombatSound.telegraphWater,
    );
    expect(expeditionTelegraphSound('guard'), isNull);
    expect(
      expeditionReleaseSound('heartwood_observatory'),
      ExpeditionCombatSound.releaseHeartwoodObservatory,
    );
  });

  testWidgets('구미호와 닌자의 비식물 고유 스킬 아이콘을 번들에서 읽는다', (tester) async {
    const assets = <String>[
      'assets/adventure/skill-icons/gumiho-pot/heart-moon-charm-v1.webp',
      'assets/adventure/skill-icons/gumiho-pot/nine-tail-eclipse-v1.webp',
      'assets/adventure/skill-icons/ninja-pot/venom-seam-v1.webp',
      'assets/adventure/skill-icons/ninja-pot/shadow-execution-v1.webp',
    ];

    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(1800), reason: asset);
      final size = _webpCanvasSize(data);
      expect(size.width, size.height, reason: '$asset 정사각형');
      expect(size.width, greaterThanOrEqualTo(128), reason: '$asset 2배수');
    }
  });

  testWidgets('간호사와 지휘자의 프리미엄 고유 스킬 아이콘을 번들에서 읽는다', (tester) async {
    const assets = <String>[
      'assets/adventure/skill-icons/nurse-pot/triage-bloom-v1.webp',
      'assets/adventure/skill-icons/nurse-pot/white-garden-oath-v1.webp',
      'assets/adventure/skill-icons/maestro-pot/golden-downbeat-v1.webp',
      'assets/adventure/skill-icons/maestro-pot/silent-coda-v1.webp',
    ];

    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(8000), reason: asset);
      expect(_webpCanvasSize(data), (width: 256, height: 256), reason: asset);
    }
  });

  testWidgets('신규 캐릭터 3종의 고유 스킬 아이콘을 번들에서 읽는다', (tester) async {
    const assets = <String>[
      'assets/adventure/skill-icons/restorer-pot/patina-parry-v1.webp',
      'assets/adventure/skill-icons/restorer-pot/golden-seam-v1.webp',
      'assets/adventure/skill-icons/marten-pot/softpaw-rush-v1.webp',
      'assets/adventure/skill-icons/marten-pot/den-guardian-roar-v1.webp',
      'assets/adventure/skill-icons/gal-pot/patchwork-relay-v1.webp',
      'assets/adventure/skill-icons/gal-pot/runway-reversal-v1.webp',
    ];

    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(5000), reason: asset);
      expect(_webpCanvasSize(data), (width: 256, height: 256), reason: asset);
    }
  });

  testWidgets('플레이어와 몬스터 공격을 효과별 투명 스프라이트로 읽는다', (tester) async {
    const effectKeys = [
      'care_vines',
      'ledger_claw',
      'safe_guard',
      'ember_arc',
      'prism_burst',
      'mist_dash',
      'venom_seam',
      'insight_arc',
      'echo_wave',
      'enemy_wave',
      'paper_flurry',
      'ink_mist',
      'petal_gust',
      'petal_dart',
      'shelf_sweep',
      'catalogue_rain',
      'record_wave',
      'seal_crush',
      'root_lockdown',
      'final_redaction',
    ];

    for (final effectKey in effectKeys) {
      final assets = expeditionCombatEffectAssets(effectKey);
      expect(
        assets,
        hasLength(expeditionCombatEffectFrameCountFor(effectKey)),
      );
      for (final asset in assets) {
        final data = await rootBundle.load(asset);
        final size = _webpCanvasSize(data);
        expect(size, (width: 576, height: 288), reason: asset);
        expect(data.getUint8(20) & 0x10, 0x10, reason: '$asset 알파 채널');
      }
    }

    expect(expeditionCombatEffectFrameForProgress('care_vines', .5), 5);
    expect(expeditionCombatEffectFrameForProgress('ledger_claw', .5), 5);
    expect(expeditionCombatEffectFrameForProgress('ledger_claw', 1), 9);
    expect(expeditionCombatEffectFrameCountFor('venom_seam'), 7);
    expect(expeditionCombatEffectFrameForProgress('venom_seam', .5), 4);
    expect(expeditionCombatEffectFrameForProgress('enemy_wave', .5), 4);
    expect(expeditionCombatEffectFrameForProgress('paper_flurry', .5), 4);
    expect(expeditionCombatEffectFrameCountFor('ink_mist'), 7);
    expect(expeditionCombatEffectFrameForProgress('ink_mist', .6), 4);
    expect(expeditionCombatEffectFrameCountFor('petal_dart'), 7);
    expect(expeditionCombatEffectFrameForProgress('petal_dart', .6), 4);
    for (final effectKey in const [
      'petal_gust',
      'shelf_sweep',
      'catalogue_rain',
      'record_wave',
      'seal_crush',
      'root_lockdown',
      'final_redaction',
    ]) {
      expect(expeditionCombatEffectFrameCountFor(effectKey), 8);
      expect(expeditionCombatEffectFrameForProgress(effectKey, .5), 3);
    }
  });

  test('서버가 지정한 여섯 motion archetype은 서로 다른 동선을 만든다', () {
    const phases = [
      ExpeditionCombatMotionPhase(name: 'anticipation', ms: 130),
      ExpeditionCombatMotionPhase(name: 'release', ms: 100),
      ExpeditionCombatMotionPhase(name: 'travel', ms: 220),
      ExpeditionCombatMotionPhase(name: 'contact', ms: 80),
      ExpeditionCombatMotionPhase(name: 'reaction', ms: 110),
      ExpeditionCombatMotionPhase(name: 'recovery', ms: 160),
    ];
    ExpeditionActionCue cue(String archetype) => ExpeditionActionCue(
          id: archetype.hashCode,
          kind: ExpeditionActionCueKind.combatParty,
          actorName: '그림싹',
          actorId: 11,
          speciesCode: 'ninja-pot',
          speciesName: '그림싹',
          stage: 5,
          form: 'rainy',
          title: archetype,
          effectKey: 'venom_seam',
          outcome: null,
          combat: null,
          motionProfile: 'test.$archetype',
          motion: ExpeditionCombatMotion(
            profile: 'test.$archetype',
            archetype: archetype,
            facing: 'right',
            travelRatio: archetype == 'brace' ? 0 : .7,
            impactShakePx: 2.5,
            phases: phases,
            totalMs: 800,
          ),
        );

    final offsets = {
      for (final archetype in const [
        'dash',
        'draw',
        'cast',
        'brace',
        'channel',
        'leap',
      ])
        archetype: ExpeditionCombatTimeline.actorOffset(.38, cue(archetype)),
    };
    expect(offsets.values.toSet(), hasLength(6));
    expect(offsets['dash']!.dx, greaterThan(offsets['draw']!.dx));
    expect(offsets['leap']!.dy, lessThan(offsets['cast']!.dy));
    expect(offsets['brace']!.dx.abs(), lessThan(offsets['dash']!.dx.abs()));
  });

  test('VFX resolver는 exact, 결, legacy, 공용 순서로 대체한다', () {
    expect(
      resolveExpeditionCombatEffect(
        vfxFamily: 'tangled-ledger.paper-flurry',
        kelFallbackFamily: 'kel.moonlit',
        legacyEffectKey: 'insight_arc',
      ).directory,
      'paper-flurry-v1',
    );
    expect(
      resolveExpeditionCombatEffect(
        vfxFamily: 'tangled-ledger.ink-mist',
        kelFallbackFamily: 'kel.mosaic',
        legacyEffectKey: 'ink_mist',
      ).directory,
      'ink-mist-v1',
    );
    expect(
      resolveExpeditionCombatEffect(
        vfxFamily: 'drifting-pressings.petal-dart',
        kelFallbackFamily: 'kel.ember',
        legacyEffectKey: 'petal_dart',
      ).directory,
      'petal-dart-v1',
    );
    expect(
      resolveExpeditionCombatEffect(
        vfxFamily: 'nurse-pot.triage-bloom',
        kelFallbackFamily: 'kel.sunny',
      ).directory,
      'triage-bloom-v1',
    );
    expect(
      resolveExpeditionCombatEffect(
        vfxFamily: 'nurse-pot.white-garden-oath',
        kelFallbackFamily: 'kel.sunny',
      ).totalDurationMs,
      760,
    );
    expect(
      resolveExpeditionCombatEffect(
        vfxFamily: 'maestro-pot.golden-downbeat',
        kelFallbackFamily: 'kel.sparkling',
      ).directory,
      'golden-downbeat-v1',
    );
    expect(
      resolveExpeditionCombatEffect(
        vfxFamily: 'maestro-pot.silent-coda',
        kelFallbackFamily: 'kel.sparkling',
      ).totalDurationMs,
      760,
    );
    expect(
      resolveExpeditionCombatEffect(
        vfxFamily: 'restorer-pot.patina-parry',
      ).directory,
      'patina-parry-v1',
    );
    expect(
      resolveExpeditionCombatEffect(
        vfxFamily: 'marten-pot.den-guardian-roar',
      ).directory,
      'den-guardian-roar-v1',
    );
    expect(
      resolveExpeditionCombatEffect(
        vfxFamily: 'gal-pot.runway-reversal',
      ).directory,
      'runway-reversal-v1',
    );
    expect(
      resolveExpeditionCombatEffect(
        vfxFamily: 'not-yet-produced',
        kelFallbackFamily: 'kel.rainy',
        legacyEffectKey: 'ember_arc',
      ).directory,
      'mist-dash',
    );
    expect(
      resolveExpeditionCombatEffect(
        vfxFamily: 'not-yet-produced',
        legacyEffectKey: 'ember_arc',
      ).directory,
      'ember-arc',
    );
    expect(
      resolveExpeditionCombatEffect(vfxFamily: 'not-yet-produced').family,
      'fallback.echo-wave',
    );
  });

  test('앞열·전체·최저 체력 예고는 색 없이도 서로 다른 형태를 쓴다', () {
    final icons = {
      expeditionIntentTargetIcon('front'),
      expeditionIntentTargetIcon('all'),
      expeditionIntentTargetIcon('lowest'),
    };
    expect(icons, hasLength(3));

    const front = ExpeditionGuardianIntentPainter(
      phase: .5,
      reduceMotion: true,
      target: 'front',
    );
    const lowest = ExpeditionGuardianIntentPainter(
      phase: .5,
      reduceMotion: true,
      target: 'lowest',
    );
    expect(lowest.shouldRepaint(front), isTrue);
  });

  test('장부 발톱 적 이벤트는 전용 contact sprite와 같은 판정 시점을 쓴다', () {
    const cue = ExpeditionActionCue(
      id: 31,
      kind: ExpeditionActionCueKind.combatEnemy,
      actorName: '돌비늘 장부지기',
      actorId: 11,
      speciesCode: 'baby-pot',
      speciesName: '새싹몬',
      stage: 2,
      form: 'sunny',
      title: '장부 발톱',
      effectKey: 'ledger_claw',
      outcome: '오른발이 내려왔어요.',
      combat: ExpeditionCombatFeedback(
        kind: 'guardian',
        enemyName: '돌비늘 장부지기',
        enemyMaxGuard: 100,
        enemyGuardBefore: 100,
        enemyGuardAfter: 100,
        guardDamage: 0,
        attackName: '장부 발톱',
        telegraph: '오른발이 들렸어요.',
        damageTarget: '새싹몬',
        counterDamage: 1,
        counterResult: 'hit',
        effectKey: 'ledger_claw',
      ),
    );

    final contactProgress = ExpeditionCombatTimeline.enemyContactProgress(cue);
    final effectProgress = ExpeditionCombatTimeline.segment(
      contactProgress,
      ExpeditionCombatTimeline.enemyEffectStart(cue),
      ExpeditionCombatTimeline.enemyEffectEnd(cue),
    );

    expect(cue.enemyEffectKey, 'ledger_claw');
    expect(
      expeditionCombatEffectFrameForProgress(
          cue.enemyEffectKey, effectProgress),
      5,
    );
  });

  testWidgets('작은 물리 화면에서 모바일 탐험 원화를 선택한다', (tester) async {
    ImageProvider<Object>? provider;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            devicePixelRatio: 1,
          ),
          child: Builder(
            builder: (context) {
              provider = expeditionSceneImageProvider(
                context,
                expeditionMoonTowerAsset,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(
      _assetNameOf(provider!),
      expeditionMobileAssetPath(expeditionMoonTowerAsset),
    );
  });

  test('탐험대와 발자국이 통합 지형의 같은 경로 좌표를 사용한다', () {
    final area = expeditionWalkAreaFor('moss_archive');
    final from = expeditionStandPoint(area, const Offset(.08, .50));
    final to = expeditionStandPoint(area, const Offset(.28, .27));
    final route = expeditionWalkPath(area, from, to);

    expect(route.length, greaterThan(2));
    expect(route.first, from);
    expect(route.last, to);
    expect(expeditionPathPosition(route, 0), route.first);
    expect(expeditionPathPosition(route, 1), route.last);
    // 발자국 그리기도 같은 함수를 부른다. 두 번 물어 같은 답이 나와야 한 길을
    // 밟는다 — 다르면 캐릭터와 발자국이 갈라진다.
    expect(expeditionWalkPath(area, from, to), route);
  });

  test('탐험 편성 목록에서 현재 성장 캐릭터를 구분한다', () {
    final item = ExpeditionRosterItem.fromJson({
      'plant_id': 12,
      'name': '하루',
      'status': 'active',
      'species': {'code': 'student-pot', 'name': '학생화분'},
      'stage': 2,
      'form': 'sunny',
      'stats': {'care': 6, 'focus': 7, 'courage': 5, 'insight': 6},
      'eligible': true,
    });

    expect(item.isActive, isTrue);
    expect(item.eligible, isTrue);
  });

  test('탐험 응답에서 숨은 노드와 행동 가능 상태를 보존한다', () {
    final snapshot = ExpeditionSnapshot.fromJson(_snapshotJson());

    expect(snapshot.run.revision, 1);
    expect(snapshot.currentEvent?.spotlightMemberId, 11);
    expect(snapshot.nodes.last.isPositioned, isFalse);
    expect(snapshot.currentEvent?.choices.first.previewFor(11)?.forecast, '도전');
    expect(snapshot.canExtract, isFalse);
    expect(snapshot.party.first.signatureSkill.name, '새싹 응원');
    expect(snapshot.party.first.formSkill.modes, hasLength(2));
    expect(snapshot.nodes[1].sceneKey, 'flooded_cave');
    expect(snapshot.nodes[1].threatLevel, 2);
    expect(snapshot.party.first.speciesCode, 'baby-pot');
    expect(snapshot.party.first.outfitKey, 'city-night');
    expect(snapshot.currentEvent?.encounter?.enemyName, '돌비늘 장부지기');
    expect(snapshot.currentEvent?.choices.first.guardDamage, 68);
    expect(
      expeditionSceneTheme(snapshot.nodes[1].sceneKey).assetPath,
      expeditionFloodedCaveAsset,
    );
  });

  test('수호전 응답에서 속성 상성·성장 계수·쿨타임·제로 장벽을 보존한다', () {
    final snapshot = ExpeditionSnapshot.fromJson(_battleSnapshotJson());
    final battle = snapshot.currentEvent!.battle!;

    expect(battle.round, 1);
    expect(battle.version, 2);
    expect(battle.kelMapVersion, 1);
    expect(battle.enemy.intent.target, 'front');
    expect(battle.enemy.weaknessLabel, '돌봄');
    expect(battle.enemy.weakElementLabel, '빛');
    expect(battle.enemy.resistElementLabel, '강철');
    expect(battle.enemy.weakKelLabel, '햇살결');
    expect(battle.enemy.resistKelLabel, '모아결');
    expect(battle.party.first.kit.level, 25);
    expect(battle.party.first.kit.kelMapVersion, 1);
    expect(battle.party.first.kit.signatureTier, 3);
    expect(battle.party.first.kit.skill.effect, 'shield_all');
    expect(battle.party.first.kit.skill.elementLabel, '생명');
    expect(battle.party.first.kit.skill.powerScaleBp, 11600);
    expect(battle.party.first.kit.skill.tierPowerBp, 12200);
    expect(battle.party.first.kit.skill.matchupBp, 15000);
    expect(battle.party.first.kit.skill.kelLabel, '햇살결');
    expect(battle.party.first.kit.skill.kelLabels, ['햇살결']);
    expect(
      battle.party.first.kit.skill.fusionVariant,
      'sprout_cheer.sunny.unique_1.t3',
    );
    expect(
      battle.party.first.kit.skill.fusionVfxFamily,
      'emotion-fusion.sunny-radiance',
    );
    expect(battle.party.first.kit.uniqueSkills.last.cooldownRemaining, 2);
    expect(battle.party.last.kit.skill.effect, 'study_refund');
    expect(snapshot.lastCombatExchange.single.enemyGuardAfter, 0);
    expect(snapshot.lastCombatExchange.single.weaknessHit, isTrue);
    expect(snapshot.lastCombatExchange.single.kelMapVersion, 1);
    expect(
      snapshot.lastCombatExchange.single.motionProfile,
      'baby-pot.vine-cast',
    );
    expect(
      snapshot.lastCombatExchange.single.vfxFamily,
      'baby-pot.care-vines',
    );
    expect(snapshot.lastCombatExchange.single.kelFallbackFamily, 'kel.sunny');
    expect(snapshot.lastCombatExchange.single.motion?.archetype, 'channel');
    expect(snapshot.lastCombatExchange.single.motion?.totalMs, 760);
    expect(
      snapshot.lastCombatExchange.single.fusionVariant,
      'baby-pot.sunny.unique_1.t3',
    );
    expect(snapshot.availableActions.map((action) => action['type']), [
      'combat_turn',
      'retreat',
    ]);
  });

  test('v7 역할 스탯·감정 연출·보스 페이즈 계약을 파싱한다', () {
    final raw = _battleSnapshotJson();
    final event = raw['current_event'] as Map<String, dynamic>;
    final battleJson = event['battle'] as Map<String, dynamic>;
    battleJson['version'] = 3;
    battleJson['boss_phase'] = {
      'index': 3,
      'count': 3,
      'code': 'final_erasure',
      'name': '최종 말소',
      'tone': 'ember',
      'intent_power_bonus': 2,
      'rule_name': '최종 교정',
      'rule_summary': '약점을 맞혀 말소 위력 상승을 끊어요.',
      'phase_gate': 'resolve_intent',
      'phase_gate_ready': false,
      'next_threshold_guard': null,
    };
    final party = battleJson['party'] as List<dynamic>;
    final member = party.first as Map<String, dynamic>;
    final kit = member['kit'] as Map<String, dynamic>;
    kit['version'] = 7;
    kit['role'] = 'premium_healer';
    kit['role_label'] = '프리미엄 힐러';
    kit['combat_stats'] = {
      'offense': 16,
      'vitality': 24,
      'support': 35,
      'control': 18,
    };
    kit['combat_stat_labels'] = {
      'offense': '공격',
      'vitality': '생존',
      'support': '지원',
      'control': '제어',
    };
    kit['emotion_vfx_palette'] = {
      'primary': '#F4C56A',
      'secondary': '#FFF0B8',
    };
    final uniqueSkills = kit['unique_skills'] as List<dynamic>;
    final unique = uniqueSkills.first as Map<String, dynamic>;
    unique['effect_values'] = {'heal_lowest': 3, 'target_guard': 2};
    unique['mechanic_summary'] = '최저 체력 회복 3 · 대상 보호 2';
    unique['presentation_tier'] = 3;
    unique['vfx_intensity'] = 1.12;
    unique['audio_layer'] = 'signature';
    unique['camera_profile'] = 'signature-close';
    unique['emotion_vfx_primary'] = '#F4C56A';
    unique['emotion_vfx_secondary'] = '#FFF0B8';
    final exchange = raw['last_combat_exchange'] as List<dynamic>;
    final action = exchange.first as Map<String, dynamic>;
    action['effect_values'] = {'heal_lowest': 3, 'target_guard': 2};
    action['mechanic_summary'] = '최저 체력 회복 3 · 대상 보호 2';
    action['presentation_tier'] = 3;
    action['vfx_intensity'] = 1.12;
    action['audio_layer'] = 'signature';
    action['camera_profile'] = 'signature-close';
    action['emotion_vfx_primary'] = '#F4C56A';
    action['emotion_vfx_secondary'] = '#FFF0B8';

    final snapshot = ExpeditionSnapshot.fromJson(raw);
    final battle = snapshot.currentEvent!.battle!;
    final parsedKit = battle.party.first.kit;
    final parsedSkill = parsedKit.uniqueSkills.first;
    final parsedEvent = snapshot.lastCombatExchange.first;

    expect(battle.version, 3);
    expect(battle.bossPhase?.index, 3);
    expect(battle.bossPhase?.name, '최종 말소');
    expect(battle.bossPhase?.isFinal, isTrue);
    expect(battle.bossPhase?.ruleName, '최종 교정');
    expect(battle.bossPhase?.phaseGate, 'resolve_intent');
    expect(battle.bossPhase?.phaseGateReady, isFalse);
    expect(parsedKit.version, 7);
    expect(parsedKit.role, 'premium_healer');
    expect(parsedKit.combatStats['support'], 35);
    expect(parsedKit.combatStatLabels['control'], '제어');
    expect(parsedKit.emotionVfxPalette['primary'], '#F4C56A');
    expect(parsedSkill.effectValues['heal_lowest'], 3);
    expect(parsedSkill.mechanicSummary, contains('대상 보호 2'));
    expect(parsedSkill.presentationTier, 3);
    expect(parsedSkill.audioLayer, 'signature');
    expect(parsedEvent.vfxIntensity, 1.12);
    expect(parsedEvent.cameraProfile, 'signature-close');
    expect(parsedEvent.emotionVfxPrimary, '#F4C56A');
  });

  testWidgets('전투 무대는 현재 장벽과 다음 공격을 표시한다', (tester) async {
    final raw = _battleSnapshotJson();
    final event = raw['current_event'] as Map<String, dynamic>;
    final battleJson = event['battle'] as Map<String, dynamic>;
    final enemy = battleJson['enemy'] as Map<String, dynamic>;
    enemy['guard'] = 74;
    enemy['intent'] = {
      'code': 'record_wave',
      'name': '기록 파동',
      'telegraph': '탐험대 전체를 덮쳐요.',
      'target': 'all',
      'power': 1,
    };
    final snapshot = ExpeditionSnapshot.fromJson(raw);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 220,
            child: Stack(
              children: [
                ExpeditionEncounterStage(
                  encounter: snapshot.currentEvent?.encounter,
                  battle: snapshot.currentEvent?.battle,
                  actor: null,
                  party: snapshot.party,
                  cue: null,
                  onCueCompleted: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('74/100'), findsOneWidget);
    expect(find.textContaining('기록 파동 예고'), findsOneWidget);
    expect(find.textContaining('탐험대 전체를 덮쳐요.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('expedition-combat-party-lineup')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('수호전은 순차 명령이 기본이고 카드 독이 집중력·약점을 읽어 준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final raw = _battleSnapshotJson();
    final eventJson = raw['current_event'] as Map<String, dynamic>;
    final battleJson = eventJson['battle'] as Map<String, dynamic>;
    final memberJson =
        (battleJson['party'] as List).first as Map<String, dynamic>;
    final kitJson = memberJson['kit'] as Map<String, dynamic>;
    final uniqueSkill =
        (kitJson['unique_skills'] as List).first as Map<String, dynamic>;
    // 약점·내성을 함께 가진 T3 기술도 서버의 약점 우선 판정만 표시해야 한다.
    uniqueSkill['kels'] = ['sunny', 'mosaic'];
    uniqueSkill['kel_labels'] = ['햇살결', '모아결'];
    uniqueSkill['matchup_bp'] = 13000;
    final snapshot = ExpeditionSnapshot.fromJson(raw);
    late _FakeExpeditionController controller;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () {
              controller = _FakeExpeditionController(
                ExpeditionUiState(
                  loading: false,
                  expedition: snapshot,
                  selectedMemberId: 11,
                  tutorialCoachStep: 7,
                ),
              );
              return controller;
            },
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    // 한 카메라 전장 위 가장자리 HUD와 여섯 행동 아이콘 벨트.
    expect(find.byKey(const ValueKey('seq-command-dock')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('immersive-combat-stage')), findsOneWidget);
    expect(find.text('R 1/6'), findsOneWidget);
    expect(find.textContaining('장부 발톱'), findsWidgets);
    expect(find.text('↑ 햇살결  ↓ 모아결'), findsOneWidget);
    expect(find.byKey(const ValueKey('seq-dock-action-row')), findsOneWidget);
    for (final action in expeditionCombatActionOrder) {
      final slot = find.byKey(ValueKey('seq-dock-card-$action'));
      expect(slot, findsOneWidget);
      expect(tester.getSize(slot).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(slot).height, greaterThanOrEqualTo(48));
    }
    final actionIconAssets = tester
        .widgetList<Image>(
          find.descendant(
            of: find.byKey(const ValueKey('seq-dock-action-row')),
            matching: find.byType(Image),
          ),
        )
        .map((image) => _assetNameOf(image.image))
        .whereType<String>()
        .toSet();
    expect(
      actionIconAssets,
      containsAll(<String>{
        'assets/adventure/skill-icons/baby-pot/sprout-cheer-v1.webp',
        'assets/adventure/skill-icons/baby-pot/root-embrace-v1.webp',
        'assets/adventure/skill-icons/baby-pot/sunny-warmth-share-v1.webp',
        'assets/adventure/skill-icons/baby-pot/field-note-echo-v1.webp',
      }),
    );
    // 이름·효과 전문은 평상시 화면에 두지 않고 상세 시트에서만 연다.
    expect(find.text('새싹 응원'), findsNothing);
    expect(find.text('캐릭터의 개성을 살린 고유 행동이에요.'), findsNothing);
    // 첫 대기 대원의 이름으로 프롬프트가 열린다.
    expect(find.text('새싹몬은 무엇을 할까요?'), findsOneWidget);
    final auto = tester.widget<FilterChip>(
      find.byKey(const ValueKey('seq-dock-auto')),
    );
    expect(auto.selected, isFalse);

    // 집중력 1로는 스킬(집중 2)을 쓸 수 없다 — 카드가 사유와 함께 잠긴다.
    final skillCard = find.byKey(const ValueKey('seq-dock-card-unique_1'));
    await tester.ensureVisible(skillCard);
    await tester.pump();
    expect(find.text('집중 부족'), findsWidgets);
    expect(find.text('재사용 2'), findsWidgets);
    await tester.tap(skillCard, warnIfMissed: false);
    await tester.pump();
    expect(controller.combatActionRequests, 0);

    // 349ms에는 열리지 않고 350ms 경계를 넘겨야 상세가 열린다.
    // 잠긴 카드도 상세를 읽을 수 있지만 hold가 행동 제출로 이어지면 안 된다.
    final detailGesture = await tester.startGesture(
      tester.getCenter(skillCard),
    );
    await tester.pump(const Duration(milliseconds: 349));
    expect(find.text('캐릭터의 개성을 살린 고유 행동이에요.'), findsNothing);
    expect(controller.combatActionRequests, 0);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(find.text('캐릭터의 개성을 살린 고유 행동이에요.'), findsOneWidget);
    expect(find.text('T3 · 마음 만개'), findsOneWidget);
    expect(find.text('↑ 햇살결 · 모아결 · 약점 ×1.30'), findsOneWidget);
    expect(find.textContaining('내성 ×'), findsNothing);
    // 판정식 중간값은 화면에 두지 않는다. 셋을 곱한 결과는 머리의 `위력`이고
    // 약점 배수는 결 태그가 이미 말한다.
    expect(find.textContaining('계수 '), findsNothing);
    expect(find.textContaining('상성 1'), findsNothing);
    expect(find.textContaining('위력 '), findsWidgets);
    expect(find.text('T3 감정 융합'), findsOneWidget);
    expect(
      find.text('연출 · 고유 움직임 위에 지금 성장결의 빛이 겹쳐요'),
      findsOneWidget,
    );
    expect(find.textContaining('VFX'), findsNothing);
    await detailGesture.up();
    await tester.pump();
    expect(controller.combatActionRequests, 0);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump(const Duration(milliseconds: 300));

    // 좁은 폭에서도 **누구를 얼마나**는 잘리지 않는다. 넷을 다 넣으면
    // 390px에서 `장부 발톱 · 행동 순서 맨…`으로 끊겨 대상이 사라졌다.
    // 공격 이름은 무대 위 예고판이 이미 말한다.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('seq-dock-intent')),
        matching: find.text('행동 순서 맨 앞 대원 · 위력 1'),
      ),
      findsOneWidget,
    );

    // 의도 줄을 누르면 발견 정보 시트가 열린다.
    final intentLine = find.byKey(const ValueKey('seq-dock-intent'));
    await tester.tap(intentLine);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('상세 생태 기록'), findsOneWidget);
    expect(find.text('확인한 내성'), findsOneWidget);
    expect(find.text('??? · 전투 후 도감에서 공개'), findsOneWidget);
    expect(find.text('??? · 실제 발견 후 공개'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump(const Duration(milliseconds: 300));

    // 공격 카드 탭 한 번이 곧 행동 제출이다.
    final attackCard = find.byKey(const ValueKey('seq-dock-card-attack'));
    await tester.tap(attackCard);
    await tester.pump();
    expect(controller.combatActionRequests, 1);
    expect(controller.combatActionLog.single.memberId, 11);
    expect(controller.combatActionLog.single.action, 'attack');

    // 서버가 첫 행동을 판정한 뒤 — 다음 대기 대원에게 차례가 넘어간다.
    final nextRaw = _battleSnapshotJson();
    (nextRaw['run'] as Map<String, dynamic>)['revision'] = 2;
    final nextEvent = nextRaw['current_event'] as Map<String, dynamic>;
    final nextBattle = nextEvent['battle'] as Map<String, dynamic>;
    nextBattle['focus'] = 2;
    (nextBattle['enemy'] as Map<String, dynamic>)['guard'] = 80;
    nextBattle['pending_round'] = {
      'acted': [11],
      'awaiting': [12],
    };
    final nextSnapshot = ExpeditionSnapshot.fromJson(nextRaw);
    controller.replace(
      ExpeditionUiState(
        loading: false,
        expedition: nextSnapshot,
        selectedMemberId: 11,
        tutorialCoachStep: 7,
      ),
    );
    await tester.pump();

    expect(find.text('해답이는 무엇을 할까요?'), findsOneWidget);
    // 집중력이 모였으니 이번 대원의 스킬 카드는 열려 있다.
    expect(find.text('집중 부족'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('seq-dock-card-unique_1')));
    await tester.pump();
    expect(controller.combatActionRequests, 2);
    expect(controller.combatActionLog.last.memberId, 12);
    expect(controller.combatActionLog.last.action, 'unique_1');

    // AUTO는 끔 → 보조 → 연속 순서로 돈다.
    final autoToggle = find.byKey(const ValueKey('seq-dock-auto'));
    await tester.ensureVisible(autoToggle);
    await tester.pump();
    await tester.tap(autoToggle);
    await tester.pump();
    expect(tester.widget<FilterChip>(autoToggle).selected, isTrue);
    expect(find.text('AUTO·보조'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('기록서가 건 잠금은 눌러 보기 전에 카드에서 읽힌다', (tester) async {
    // 이 화면의 다른 잠금은 다 미리 말한다 - `집중 부족`, `Lv.N 해금`.
    // 기록서가 건 잠금만 눌러야 알 수 있었다.
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final raw = _battleSnapshotJson();
    final battleJson = (raw['current_event'] as Map<String, dynamic>)['battle']
        as Map<String, dynamic>;
    // 집중력을 넉넉히 줘 `집중 부족`이 대신 뜨지 않게 한다.
    battleJson['focus'] = 5;
    final kitJson = ((battleJson['party'] as List).first
        as Map<String, dynamic>)['kit'] as Map<String, dynamic>;
    final unique = (kitJson['unique_skills'] as List).first
        as Map<String, dynamic>;
    unique
      ..['available'] = false
      ..['lock_reason'] = '태엽 감는 중';
    (kitJson['guard'] as Map<String, dynamic>)
      ..['available'] = false
      ..['lock_reason'] = '고리수 세는 중';
    final snapshot = ExpeditionSnapshot.fromJson(raw);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    // 레벨 문구로 바꿔 말하지 않는다 - 서버가 준 사유를 그대로 쓴다.
    expect(find.text('태엽 감는 중'), findsWidgets);
    expect(find.text('고리수 세는 중'), findsWidgets);
    expect(find.textContaining('해금'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('잔향 읽기를 쓴 전투에서만 다음 라운드 예고가 보인다', (tester) async {
    // 이 책이 파는 것은 이 한 줄뿐이다. 늘 보이면 40씨앗짜리 책이 파는 게
    // 없어지고, 안 보이면 산 사람이 아무것도 못 받는다.
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pumpWith(Map<String, dynamic>? nextIntent) async {
      final raw = _battleSnapshotJson();
      final battleJson = (raw['current_event'] as Map<String, dynamic>)['battle']
          as Map<String, dynamic>;
      final enemy = battleJson['enemy'] as Map<String, dynamic>;
      if (nextIntent != null) enemy['next_intent'] = nextIntent;
      final snapshot = ExpeditionSnapshot.fromJson(raw);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expeditionControllerProvider.overrideWith(
              () => _FakeExpeditionController(
                ExpeditionUiState(
                  loading: false,
                  expedition: snapshot,
                  selectedMemberId: 11,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ExpeditionScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    // 책을 안 썼으면 서버가 아예 안 내려 준다.
    await pumpWith(null);
    expect(find.byKey(const ValueKey('seq-dock-intent')), findsOneWidget);
    expect(find.byKey(const ValueKey('seq-dock-next-intent')), findsNothing);

    // 앞 트리를 완전히 내리고 다시 세운다. 같은 자리에 덮어쓰면 provider
    // 재정의가 그대로 살아 새 응답이 안 들어온다.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpWith(const {
      'code': 'record_wave',
      'name': '기록 파동',
      'telegraph': '모두를 노려요.',
      'target': 'all',
      'power': 2,
    });
    expect(find.byKey(const ValueKey('seq-dock-intent')), findsOneWidget,
        reason: '의도 줄 자체가 안 그려졌다');
    final line = find.byKey(const ValueKey('seq-dock-next-intent'));
    expect(line, findsOneWidget);
    expect(
      find.descendant(
        of: line,
        matching: find.text('다음 라운드 · 기록 파동 · 탐험대 전체 · 위력 2'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('고를 것이 있는 기록서는 먼저 묻고 고른 값을 실어 보낸다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final raw = _battleSnapshotJson();
    final battleJson = (raw['current_event'] as Map<String, dynamic>)['battle']
        as Map<String, dynamic>;
    final kitJson = ((battleJson['party'] as List).first
        as Map<String, dynamic>)['kit'] as Map<String, dynamic>;
    final slotJson =
        (kitJson['selected_skills'] as List).first as Map<String, dynamic>;
    // 서버가 명령형 기록서를 내려보낸 상태. 후보와 현재값까지 함께 온다.
    slotJson
      ..['code'] = 'resonance_tuner'
      ..['name'] = '마음결 조율기'
      ..['focus_cost'] = 1
      ..['cooldown_remaining'] = 0
      ..['mechanic_summary'] = '다음 공격 성장결을 바꿔요'
      ..['choice_kind'] = 'kel'
      ..['choice_current'] = 'sunny'
      ..['choice_options'] = [
        {'value': 'sunny', 'label': '햇살결'},
        {'value': 'ember', 'label': '잉걸결'},
      ];
    final snapshot = ExpeditionSnapshot.fromJson(raw);
    late _FakeExpeditionController controller;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(() {
            controller = _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            );
            return controller;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    final card = find.byKey(const ValueKey('seq-dock-card-selected_1'));
    await tester.ensureVisible(card);
    await tester.pump();
    await tester.tap(card, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 누르자마자 보내지 않는다. 무엇으로 바꿀지 먼저 묻는다.
    expect(controller.combatActionRequests, 0);
    expect(find.text('잉걸결'), findsOneWidget);
    // 지금과 같은 결도 목록에 남지만 고를 수는 없다.
    expect(find.text('지금 이 결'), findsOneWidget);
    await tester.tap(find.text('햇살결'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.combatActionRequests, 0);

    await tester.tap(find.text('잉걸결'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(controller.combatActionRequests, 1);
    final sent = controller.combatActionLog.single;
    expect(sent.action, 'selected_1');
    expect(sent.choice, 'ember');
    expect(sent.toJson()['choice'], 'ember');
  });

  testWidgets('엉킴 웨이브 전투는 몇 번째 엉킴인지와 전용 상태 원화를 보여 준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final raw = _battleSnapshotJson();
    final event = raw['current_event'] as Map<String, dynamic>;
    final battleJson = event['battle'] as Map<String, dynamic>;
    battleJson['enemy_kind'] = 'tangle';
    battleJson['wave'] = {
      'index': 1,
      'count': 2,
      'code': 'tangled_ledger',
      'name': '엉킨 장부 뭉치',
    };
    final enemyJson = battleJson['enemy'] as Map<String, dynamic>;
    enemyJson['name'] = '엉킨 장부 뭉치';
    enemyJson['elite'] = false;
    final snapshot = ExpeditionSnapshot.fromJson(raw);

    final battle = snapshot.currentEvent!.battle!;
    expect(battle.isTangle, isTrue);
    expect(battle.wave!.index, 1);
    expect(battle.wave!.count, 2);
    expect(battle.wave!.code, 'tangled_ledger');
    expect(battle.enemy.name, '엉킨 장부 뭉치');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('seq-dock-wave')), findsOneWidget);
    expect(find.text('엉킴 1/2'), findsOneWidget);
    expect(find.textContaining('웨이브'), findsNothing);
    // 엉킴은 코드에 맞는 알파 원화를 쓰고 수호짐승 원화는 쓰지 않는다.
    expect(find.byKey(const ValueKey('tangle-body-idle')), findsOneWidget);
    expect(find.byKey(const ValueKey('ledger-keeper-idle')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('전투 무대와 명령 덱을 같은 화면에 고정한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = ExpeditionSnapshot.fromJson(_battleSnapshotJson());
    late _FakeExpeditionController controller;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(() {
            controller = _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            );
            return controller;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    final attackCard = find.byKey(const ValueKey('seq-dock-card-attack'));
    await tester.ensureVisible(attackCard);
    await tester.pump();
    final stage = find.byType(ExpeditionEncounterStage);
    expect(
      tester.getSize(stage).height,
      greaterThanOrEqualTo(844 * .72),
    );
    final stageTopBefore = tester.getTopLeft(stage).dy;
    final commandDockTop =
        tester.getTopLeft(find.byKey(const ValueKey('seq-command-dock'))).dy;
    expect(
      commandDockTop - stageTopBefore,
      greaterThanOrEqualTo(844 * .72),
      reason: '불투명 명령 덱 위로 화면 높이의 72% 이상 전장이 보여야 해요.',
    );
    expect(stageTopBefore, greaterThanOrEqualTo(0));
    expect(stageTopBefore, lessThan(260));

    // 대원 탭 → 카드 탭. 카드 한 번으로 행동 하나가 즉시 제출된다.
    await tester.tap(attackCard);
    await tester.pump();
    expect(controller.combatActionRequests, 1);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final stageTop = tester.getTopLeft(stage).dy;
    expect(stageTop, greaterThanOrEqualTo(0));
    expect(stageTop, lessThan(260));
    expect(stageTop, stageTopBefore);
    expect(controller.combatActionRequests, 1);
    expect(controller.combatActionLog.single.action, 'attack');
    expect(tester.takeException(), isNull);
  });

  testWidgets('좁은 화면에서도 전투 조작 넷에 스크롤 없이 닿는다', (tester) async {
    // 예전에는 AUTO·배속·짧은 연출·소리가 상단 바의 가로 스크롤 안에 있었다.
    // 390px에서 그 스크롤이 받는 폭이 70px 남짓이라 마지막 칩 하나만 보였고,
    // `reverse: true` 탓에 제일 자주 쓰는 AUTO가 제일 깊이 숨었다.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final raw = _battleSnapshotJson();
    final battleJson =
        (raw['current_event'] as Map<String, dynamic>)['battle']
            as Map<String, dynamic>;
    // 상태 태그가 제일 긴 경우 - 보스 페이즈까지 붙은 상태로 잰다.
    battleJson['boss_phase'] = {
      'index': 1,
      'count': 3,
      'code': 'index_guard',
      'name': '색인 수호',
      'tone': 'moonlit',
    };
    final snapshot = ExpeditionSnapshot.fromJson(raw);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    // 전장에 남는 조작은 화면 안에 온전히 들어와 있어야 한다.
    for (final key in const ['seq-dock-auto', 'seq-dock-settings',
      'seq-dock-retreat']) {
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.left, greaterThanOrEqualTo(0), reason: key);
      expect(rect.right, lessThanOrEqualTo(390), reason: key);
      expect(rect.width, greaterThan(0), reason: key);
    }
    expect(find.byKey(const ValueKey('seq-dock-boss-phase')), findsOneWidget);

    // 조작이 아랫줄로 내려간 만큼 장벽 HUD도 같이 내려와야 겹치지 않는다.
    final barBottom =
        tester.getRect(find.byKey(const ValueKey('seq-dock-retreat'))).bottom;
    final guardTop = tester.getRect(find.byType(ExpeditionEnemyGuardHud)).top;
    expect(
      guardTop,
      greaterThanOrEqualTo(barBottom - 6),
      reason: '장벽 HUD가 상단 바 아래로 내려와야 해요. '
          '바 $barBottom / HUD $guardTop',
    );

    // 나머지 셋은 설정 시트 안에 있고, 열기 전에는 전장에 없다.
    expect(find.byKey(const ValueKey('seq-dock-pace')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('seq-dock-settings')));
    await tester.pump();
    // 전장은 대기 모션이 계속 돌아 pumpAndSettle이 끝나지 않는다.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('전투 설정'), findsOneWidget);
    for (final key in const ['seq-dock-pace', 'seq-dock-short',
      'seq-dock-audio']) {
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.left, greaterThanOrEqualTo(0), reason: key);
      expect(rect.right, lessThanOrEqualTo(390), reason: key);
    }
    expect(find.text('1배'), findsOneWidget);
    expect(find.text('음악·효과음'), findsOneWidget);

    // 시트 안에서 누르면 그 자리에서 값이 바뀐다.
    await tester.tap(find.byKey(const ValueKey('seq-dock-pace')));
    await tester.pump();
    expect(find.text('2배'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('seq-dock-audio')));
    await tester.pump();
    expect(find.text('효과음만'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('넓은 화면에서는 상단 바가 한 줄을 유지한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = ExpeditionSnapshot.fromJson(_battleSnapshotJson());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    final auto = tester.getRect(find.byKey(const ValueKey('seq-dock-auto')));
    final settings =
        tester.getRect(find.byKey(const ValueKey('seq-dock-settings')));
    final retreat =
        tester.getRect(find.byKey(const ValueKey('seq-dock-retreat')));
    expect(auto.center.dy, closeTo(settings.center.dy, 1));
    expect(auto.center.dy, closeTo(retreat.center.dy, 1));
    // 조작은 오른쪽 끝에 모이고 상태 태그가 왼쪽을 쓴다.
    expect(auto.left, greaterThan(400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('320px과 200% 글자에서도 전장을 유지하고 명령을 스크롤한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = ExpeditionSnapshot.fromJson(_battleSnapshotJson());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('immersive-combat-stage')),
      findsOneWidget,
    );
    final commandScroll =
        find.byKey(const ValueKey('immersive-combat-command-scroll'));
    expect(commandScroll, findsOneWidget);
    expect(find.byKey(const ValueKey('seq-dock-action-grid')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(commandScroll, const Offset(0, -520));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('seq-dock-card-attack')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('사건 화면에 담당 캐릭터, 스킬, 판정 미리보기를 함께 표시한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = ExpeditionSnapshot.fromJson(_snapshotJson());
    final state = ExpeditionUiState(
      loading: false,
      expedition: snapshot,
      selectedMemberId: 11,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(state),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('번진 이름들'), findsOneWidget);
    expect(find.text('새싹몬'), findsOneWidget);
    expect(find.text('새싹 응원'), findsOneWidget);
    expect(find.text('온기 나누기'), findsOneWidget);
    expect(find.textContaining('관찰 5 · 기준 8'), findsOneWidget);
    final landmark = find.byTooltip('침수 표찰 동굴');
    expect(landmark, findsOneWidget);
    expect(tester.getSize(landmark).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(landmark).height, greaterThanOrEqualTo(48));
    expect(find.byType(MossArchiveScene), findsOneWidget);
    expect(find.byType(ExpeditionSceneBackdrop), findsOneWidget);
    expect(find.textContaining('침수 동굴'), findsWidgets);
    expect(find.text('지하 2층 · 수몰 구역'), findsOneWidget);
    expect(find.text('돌비늘 장부지기'), findsOneWidget);
    expect(find.textContaining('기록 파동 예고'), findsOneWidget);
    expect(find.textContaining('쓰러뜨리는 전투가 아니에요'), findsOneWidget);
    expect(find.text('장벽 -68'), findsOneWidget);
    expect(find.text('현재 · 침수 표찰 동굴'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('야영지 짝 대화는 320px·200% 글자에서도 네 줄을 보존한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final raw = _snapshotJson();
    final memory = raw['memory'] as Map<String, dynamic>;
    memory['duet_story'] = {
      'code': 'story.duet.baby-pot__handsome-pot.core',
      'pair_code': 'baby-pot__handsome-pot',
      'variant': 'core',
      'title': '불빛 곁의 깊은 이야기',
      'narration': '야영지의 불빛이 낮아지자 두 대원이 미뤄 둔 질문을 꺼내요.',
      'lines': [
        {'speaker_name': '새싹몬', 'text': '나도 누군가를 지켜 주는 쪽이 될 수 있을까?'},
        {'speaker_name': '로제온', 'text': '네가 고른 길이라면 내가 뒤를 정리하지.'},
        {'speaker_name': '로제온', 'text': '점검표에 없는 일이 생기면 내 판단을 믿어도 될까?'},
        {'speaker_name': '새싹몬', 'text': '아직 몰라도 같이 해 보면 돼!'},
      ],
    };
    final snapshot = ExpeditionSnapshot.fromJson(raw);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('불빛 곁의 깊은 이야기'), findsOneWidget);
    expect(find.textContaining('누군가를 지켜 주는 쪽'), findsOneWidget);
    expect(find.textContaining('내 판단을 믿어도 될까'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('수호자 소굴은 빈 전투 무대와 분리된 수호자 레이어를 사용한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final raw = _snapshotJson();
    final run = raw['run'] as Map<String, dynamic>;
    run['current_node_code'] = 'ledger_keeper';
    final map = raw['map'] as Map<String, dynamic>;
    final nodes = map['nodes'] as List<dynamic>;
    nodes[2] = {
      'code': 'ledger_keeper',
      'name': '장부지기 소굴',
      'type': 'guardian',
      'status': 'visited',
      'x': .69,
      'y': .50,
      'cost': 1,
      'scene_key': 'monster_den',
      'scene_label': '몬스터 소굴',
      'scene_description': '돌비늘 장부지기가 길을 막고 있어요.',
      'depth_label': '지하 4층 · 수호 구역',
      'threat_level': 3,
    };
    final snapshot = ExpeditionSnapshot.fromJson(raw);
    final state = ExpeditionUiState(
      loading: false,
      expedition: snapshot,
      selectedMemberId: 11,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(state),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            {
              expeditionMonsterDenBattleAsset,
              expeditionMobileAssetPath(expeditionMonsterDenBattleAsset),
            }.contains(_assetNameOf(widget.image)),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger-keeper-idle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('expedition-combat-actor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('expedition-combat-actor-artwork')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('수호전 해결 응답에서 피해와 반격 결과를 파싱한다', () {
    final raw = _snapshotJson();
    raw['last_resolution'] = {
      'event_code': 'ledger_keeper',
      'title': '돌비늘 장부지기',
      'choice': '문양의 빈틈을 읽는다',
      'outcome': '멋지게 해결',
      'score': 13,
      'actor_name': '새싹몬',
      'skill_code': 'baby-pot.sprout-cheer',
      'combat_feedback': {
        'kind': 'guardian',
        'enemy_name': '돌비늘 장부지기',
        'enemy_max_guard': 100,
        'enemy_guard_before': 100,
        'enemy_guard_after': 14,
        'guard_damage': 86,
        'attack_name': '기록 파동',
        'telegraph': '앞발의 문양이 차오른다.',
        'damage_target': '결의',
        'counter_damage': 0,
        'counter_result': 'guarded',
        'effect_key': 'insight_arc',
      },
    };

    final resolution = ExpeditionSnapshot.fromJson(raw).lastResolution!;

    expect(resolution.actorName, '새싹몬');
    expect(resolution.combat?.guardDamage, 86);
    expect(resolution.combat?.enemyGuardAfter, 14);
    expect(resolution.combat?.counterResult, 'guarded');
  });

  test('전투 연출이 끝난 뒤 확정된 탐험 결과를 화면에 반영한다', () async {
    final current = ExpeditionSnapshot.fromJson(_snapshotJson());
    final pendingRaw = _snapshotJson();
    final pendingRun = pendingRaw['run'] as Map<String, dynamic>;
    pendingRun['phase'] = 'exploring';
    pendingRun['revision'] = 2;
    pendingRaw['current_event'] = null;
    final pending = ExpeditionSnapshot.fromJson(pendingRaw);
    const cue = ExpeditionActionCue(
      id: 9,
      kind: ExpeditionActionCueKind.resolution,
      actorName: '새싹몬',
      actorId: 11,
      speciesCode: 'baby-pot',
      speciesName: '새싹몬',
      stage: 2,
      form: 'sunny',
      title: '마음의 길을 연다',
      effectKey: 'care_vines',
      outcome: '길이 열렸어요.',
      combat: null,
    );
    final container = ProviderContainer(
      overrides: [
        expeditionControllerProvider.overrideWith(
          () => _FakeExpeditionController(
            ExpeditionUiState(
              loading: false,
              expedition: current,
              actionCue: cue,
              pendingExpedition: pending,
              selectedMemberId: 11,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(expeditionControllerProvider).expedition, current);
    container.read(expeditionControllerProvider.notifier).clearActionCue();
    final completed = container.read(expeditionControllerProvider);

    expect(completed.expedition, pending);
    expect(completed.actionCue, isNull);
    expect(completed.pendingExpedition, isNull);
    expect(completed.settlingResult, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      container.read(expeditionControllerProvider).settlingResult,
      isFalse,
    );
  });

  testWidgets('수호전은 스킬 피해와 몬스터 반격을 한 타임라인에서 보여 준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var completed = false;
    const encounter = ExpeditionEncounter(
      kind: 'guardian',
      enemyName: '돌비늘 장부지기',
      enemyMaxGuard: 100,
      attackName: '기록 파동',
      telegraph: '앞발의 문양이 차오른다.',
      damageTarget: '결의',
    );
    const cue = ExpeditionActionCue(
      id: 1,
      kind: ExpeditionActionCueKind.resolution,
      actorName: '새싹몬',
      actorId: 11,
      speciesCode: 'baby-pot',
      speciesName: '새싹몬',
      stage: 3,
      form: 'sunny',
      title: '문양의 빈틈을 읽는다',
      effectKey: 'insight_arc',
      outcome: '멋지게 해결',
      combat: ExpeditionCombatFeedback(
        kind: 'guardian',
        enemyName: '돌비늘 장부지기',
        enemyMaxGuard: 100,
        enemyGuardBefore: 100,
        enemyGuardAfter: 14,
        guardDamage: 86,
        attackName: '기록 파동',
        telegraph: '앞발의 문양이 차오른다.',
        damageTarget: '결의',
        counterDamage: 0,
        counterResult: 'guarded',
        effectKey: 'insight_arc',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 220,
              child: Stack(
                children: [
                  ExpeditionEncounterStage(
                    encounter: encounter,
                    actor: null,
                    cue: cue,
                    onCueCompleted: () => completed = true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('-86'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('combat-effect-kel.moonlit-frame-5')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger-keeper-hit')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 650));
    expect(find.text('기록 파동'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ledger-keeper-attack')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('combat-enemy-effect-sequence')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 420));
    expect(find.text('방어'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 650));
    expect(completed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('수호전 승패 문구를 다음 화면 전에 충분히 유지한다', (tester) async {
    final semantics = tester.ensureSemantics();
    var completed = false;
    const cue = ExpeditionActionCue(
      id: 12,
      kind: ExpeditionActionCueKind.combatParty,
      actorName: '새싹몬',
      actorId: 11,
      speciesCode: 'baby-pot',
      speciesName: '새싹몬',
      stage: 2,
      form: 'sunny',
      title: '공명 공격',
      effectKey: 'care_vines',
      outcome: '수호 장벽이 부서지고 길이 열렸어요!',
      combatResult: 'victory',
      combat: ExpeditionCombatFeedback(
        kind: 'guardian',
        enemyName: '돌비늘 장부지기',
        enemyMaxGuard: 100,
        enemyGuardBefore: 9,
        enemyGuardAfter: 0,
        guardDamage: 9,
        attackName: '공명 공격',
        telegraph: '마지막 일격이에요.',
        damageTarget: '돌비늘 장부지기',
        counterDamage: 0,
        counterResult: 'none',
        effectKey: 'care_vines',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Stack(
            children: [
              ExpeditionEncounterStage(
                encounter: null,
                actor: null,
                cue: cue,
                onCueCompleted: () => completed = true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('ledger-keeper-hit')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('수호 장벽이 부서지고 길이 열렸어요!'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ledger-keeper-defeated')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('수호 장벽이 부서지고 길이 열렸어요!')),
      findsOneWidget,
    );
    expect(completed, isFalse);

    // 테스트 클럭도 실제 vsync처럼 나눠 전진시켜 완료 콜백과
    // hold 타이머가 서로 다른 프레임에서 등록되는 조건을 그대로 검증한다.
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(completed, isFalse);
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(completed, isTrue);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('움직임 줄이기에서는 수호전 최종 판정을 즉시 보여 준다', (tester) async {
    var completed = false;
    const cue = ExpeditionActionCue(
      id: 2,
      kind: ExpeditionActionCueKind.resolution,
      actorName: '새싹몬',
      actorId: 11,
      speciesCode: 'baby-pot',
      speciesName: '새싹몬',
      stage: 3,
      form: 'sunny',
      title: '안전한 길을 연다',
      effectKey: 'safe_guard',
      outcome: '장부지기가 길을 비켜 주었어요.',
      combat: ExpeditionCombatFeedback(
        kind: 'guardian',
        enemyName: '돌비늘 장부지기',
        enemyMaxGuard: 100,
        enemyGuardBefore: 100,
        enemyGuardAfter: 100,
        guardDamage: 0,
        attackName: '기록 파동',
        telegraph: '앞발의 문양이 차오른다.',
        damageTarget: '결의',
        counterDamage: 0,
        counterResult: 'calmed',
        effectKey: 'safe_guard',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Stack(
              children: [
                ExpeditionEncounterStage(
                  encounter: null,
                  actor: null,
                  cue: cue,
                  onCueCompleted: () => completed = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2));

    expect(find.text('장부지기가 길을 비켜 주었어요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('ledger-keeper-attack')), findsNothing);
    expect(completed, isFalse);

    await tester.pump(const Duration(milliseconds: 701));
    expect(completed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('이동 가능한 구역을 실제 장면 미리보기로 고른다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final raw = _snapshotJson();
    final run = raw['run'] as Map<String, dynamic>;
    run['phase'] = 'exploring';
    run['current_node_code'] = 'entrance';
    raw['current_event'] = null;
    raw['available_actions'] = [
      {'type': 'move', 'node_code': 'wet_labels', 'cost': 1},
    ];
    final snapshot = ExpeditionSnapshot.fromJson(raw);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
                actionCue: const ExpeditionActionCue(
                  id: 3,
                  kind: ExpeditionActionCueKind.skill,
                  actorName: '새싹몬',
                  actorId: 11,
                  speciesCode: 'baby-pot',
                  speciesName: '새싹몬',
                  stage: 2,
                  form: 'sunny',
                  title: '다음 길을 살핀다',
                  effectKey: 'care_vines',
                  outcome: null,
                  combat: null,
                ),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('다음 구역 선택'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final backdrop = tester.widget<ExpeditionSceneBackdrop>(
      find.byType(ExpeditionSceneBackdrop),
    );
    expect(
      backdrop.preloadScenes.map((scene) => scene.assetPath),
      [expeditionFloodedCaveAsset],
    );
    expect(backdrop.preloadDelay, const Duration(milliseconds: 650));
    expect(find.text('다음 구역 선택'), findsOneWidget);
    expect(find.text('침수 동굴 · 지하 2층 · 수몰 구역'), findsOneWidget);
    expect(find.text('길빛 -1'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is ResizeImage,
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px과 200% 글자에서도 사건 선택을 읽을 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = ExpeditionSnapshot.fromJson(_snapshotJson());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('번진 이름들'), findsOneWidget);
    expect(find.textContaining('관찰 5 · 기준 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px과 200% 글자에서도 장면 이동 카드가 넘치지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final raw = _snapshotJson();
    final run = raw['run'] as Map<String, dynamic>;
    run['phase'] = 'exploring';
    run['current_node_code'] = 'entrance';
    raw['current_event'] = null;
    raw['available_actions'] = [
      {'type': 'move', 'node_code': 'wet_labels', 'cost': 1},
    ];
    final snapshot = ExpeditionSnapshot.fromJson(raw);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('다음 구역 선택'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('침수 동굴 · 지하 2층 · 수몰 구역'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('선택형 스킬은 효과를 고른 뒤 사용한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = ExpeditionSnapshot.fromJson(_snapshotJson());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('온기 나누기'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('온기 나누기'));
    // 탐험 배경의 잔잔한 환경 모션은 계속 재생되므로 바텀시트 전환
    // 시간만 진행하고 무한 애니메이션의 settle을 기다리지 않는다.
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('돌봄 +3'), findsOneWidget);
    expect(find.text('결의 1 회복'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('튜토리얼은 한 번에 현재 단계 안내만 보여 준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final raw = _snapshotJson();
    (raw['run'] as Map<String, dynamic>)['mode'] = 'tutorial';
    final snapshot = ExpeditionSnapshot.fromJson(raw);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
                tutorialCoachStep: 3,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('사건에 맞는 캐릭터를 골라요'), findsOneWidget);
    expect(find.text('다음: 스킬 보기'), findsOneWidget);
    expect(find.byTooltip('현재 조작 도움말 다시 보기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('접촉·예고는 모노, 풀려남 cadence는 스테레오로 납품된다', (tester) async {
    // 접촉과 예고는 화면 위치를 따라 좌우로 흔들리면 안 되는 판정 소리라
    // 모노 16bit로 고정한다.
    const monoAssets = <String>[
      'assets/adventure/sfx/contact-leaf.wav',
      'assets/adventure/sfx/contact-paper.wav',
      'assets/adventure/sfx/contact-water.wav',
      'assets/adventure/sfx/contact-wood.wav',
      'assets/adventure/sfx/contact-stone.wav',
      'assets/adventure/sfx/contact-guard.wav',
      'assets/adventure/sfx/telegraph-leaf.wav',
      'assets/adventure/sfx/telegraph-paper.wav',
      'assets/adventure/sfx/telegraph-water.wav',
      'assets/adventure/sfx/telegraph-wood.wav',
      'assets/adventure/sfx/telegraph-stone.wav',
    ];
    for (final asset in monoAssets) {
      final data = await rootBundle.load(asset);
      expect(data.getUint16(22, Endian.little), 1, reason: '$asset 모노');
      expect(data.getUint16(34, Endian.little), 16, reason: '$asset 16bit');
    }

    // 풀려남 cadence는 두 음이 좌우로 벌어져 정리되므로 스테레오다.
    const releaseAssets = <String>[
      'assets/adventure/sfx/release-moss-archive.wav',
      'assets/adventure/sfx/release-echo-well.wav',
      'assets/adventure/sfx/release-starlight-seed-vault.wav',
      'assets/adventure/sfx/release-heartwood-observatory.wav',
    ];
    for (final asset in releaseAssets) {
      final data = await rootBundle.load(asset);
      expect(data.getUint16(22, Endian.little), 2, reason: '$asset 스테레오');
    }
  });

  test('서버 재질 값이 여섯 접촉음으로 정확히 갈린다', () {
    const materials = ['leaf', 'paper', 'water', 'wood', 'stone', 'guard'];
    final sounds = materials.map(expeditionContactSound).toList();
    expect(sounds.contains(null), isFalse);
    expect(sounds.toSet().length, 6, reason: '한 소리를 두 재질이 나눠 쓰면 안 된다');
    // 모르는 값과 구버전 응답은 재질을 지어내지 않고 공용 타격음으로 떨어진다.
    expect(expeditionContactSound(null), isNull);
    expect(expeditionContactSound('metal'), isNull);
    // 예고는 적이 만드는 소리라 방어 재질에는 예고가 없다.
    expect(expeditionTelegraphSound('guard'), isNull);
    expect(
      materials.take(5).map(expeditionTelegraphSound).toSet().length,
      5,
    );
  });

  test('풀려남 cadence는 지역마다 다르고 모르는 지역은 첫 지역으로 떨어진다', () {
    const regions = [
      'moss_archive',
      'echo_well',
      'starlight_seed_vault',
      'heartwood_observatory',
    ];
    expect(regions.map(expeditionReleaseSound).toSet().length, 4);
    expect(
      expeditionReleaseSound(null),
      ExpeditionCombatSound.releaseMossArchive,
    );
    expect(
      expeditionReleaseSound('unknown_region'),
      ExpeditionCombatSound.releaseMossArchive,
    );
  });

  test('전투 이벤트가 접촉 재질과 풀려남 지역을 그대로 읽는다', () {
    final party = ExpeditionBattleEvent.fromJson(const {
      'type': 'party_action',
      'caption': '장벽 4 피해.',
      'contact_material': 'paper',
    });
    expect(party.contactMaterial, 'paper');
    expect(party.isWaveCleared, isFalse);

    final cleared = ExpeditionBattleEvent.fromJson(const {
      'type': 'wave_cleared',
      'caption': '엉킨 장부가 스르르 풀렸어요.',
      'region_code': 'echo_well',
    });
    expect(cleared.isWaveCleared, isTrue);
    expect(cleared.regionCode, 'echo_well');

    // 구버전 응답에는 두 값이 없다. 파싱이 깨지지 않아야 한다.
    final legacy = ExpeditionBattleEvent.fromJson(const {
      'type': 'enemy_action',
      'caption': '공격이 밀려왔어요.',
    });
    expect(legacy.contactMaterial, isNull);
    expect(legacy.regionCode, isNull);
  });

  test('소리 설정은 음악·효과음 → 효과음만 → 꺼짐 순으로 돈다', () {
    const all = ExpeditionBattleSettings();
    expect(all.audioMode, ExpeditionAudioMode.all);
    expect(all.musicEnabled, isTrue);
    expect(all.sfxEnabled, isTrue);

    final sfxOnly = all.copyWith(audioMode: ExpeditionAudioMode.sfxOnly);
    expect(sfxOnly.musicEnabled, isFalse);
    expect(sfxOnly.sfxEnabled, isTrue);
    expect(sfxOnly.audioEnabled, isTrue);

    final muted = all.copyWith(audioMode: ExpeditionAudioMode.muted);
    expect(muted.musicEnabled, isFalse);
    expect(muted.sfxEnabled, isFalse);
    expect(muted.audioEnabled, isFalse);

    expect(
      {all.audioLabel, sfxOnly.audioLabel, muted.audioLabel}.length,
      3,
      reason: '세 단계가 각각 다른 문구로 읽혀야 한다',
    );
  });

  test('막아 낸 적 공격은 날아온 재질이 아니라 방어 소리로 들린다', () {
    ExpeditionActionCue enemyCue({required int counterDamage}) =>
        ExpeditionActionCue(
          id: 41,
          kind: ExpeditionActionCueKind.combatEnemy,
          actorName: '엉킨 장부 뭉치',
          actorId: 11,
          speciesCode: 'baby-pot',
          speciesName: '새싹몬',
          stage: 2,
          form: 'sunny',
          title: '종잇장 회오리',
          effectKey: 'paper_flurry',
          outcome: '낱장들이 몰려왔어요.',
          contactMaterial: 'paper',
          combat: ExpeditionCombatFeedback(
            kind: 'guardian',
            enemyName: '엉킨 장부 뭉치',
            enemyMaxGuard: 34,
            enemyGuardBefore: 34,
            enemyGuardAfter: 34,
            guardDamage: 0,
            attackName: '종잇장 회오리',
            telegraph: '낱장들이 몰려가요.',
            damageTarget: '새싹몬',
            counterDamage: counterDamage,
            counterResult: counterDamage > 0 ? 'hit' : 'guarded',
            effectKey: 'paper_flurry',
          ),
        );

    expect(enemyCue(counterDamage: 2).enemyContactMaterial, 'paper');
    expect(enemyCue(counterDamage: 0).enemyContactMaterial, 'guard');
    expect(
      expeditionContactSound(enemyCue(counterDamage: 0).enemyContactMaterial),
      ExpeditionCombatSound.contactGuard,
    );
  });

  testWidgets('발걸음 4·발견 3 현장음을 앱 번들에서 읽는다', (tester) async {
    const names = <String>[
      'step-leaf',
      'step-pot',
      'step-wood',
      'step-stone',
      'discover-normal',
      'discover-story',
      'discover-target',
    ];
    for (final name in names) {
      final asset = 'assets/adventure/sfx/$name.wav';
      final data = await rootBundle.load(asset);
      // RIFF 헤더가 없으면 파일이 깨진 것이다.
      expect(data.getUint32(0, Endian.big), 0x52494646, reason: '$asset RIFF');
      expect(data.lengthInBytes, greaterThan(2000), reason: asset);
    }
  });

  testWidgets('16품종 × 2의 고유 스킬 signature를 앱 번들에서 읽는다', (tester) async {
    // 서버 스킬 코드와 같은 이름이어야 앱이 찾을 수 있다. 하나라도 빠지면
    // 그 캐릭터만 소리가 없어지는데, 눈으로는 안 보인다.
    const skills = <String, List<String>>{
      'baby-pot': ['sprout-cheer', 'root-embrace'],
      'handsome-pot': ['command-blade', 'command-crescendo'],
      'pretty-pot': ['heart-spotlight', 'ribbon-encore'],
      'tsundere-pot': ['blazing-counter', 'iron-uppercut'],
      'zombie-pot': ['grave-gravity', 'undying-chain'],
      'gumiho-pot': ['heart-moon-charm', 'nine-tail-eclipse'],
      'ninja-pot': ['venom-seam', 'shadow-execution'],
      'magical-pot': ['prism-meteor', 'timefold-comet'],
      'aloof-pot': ['absolute-zero-read', 'steel-verdict'],
      'student-pot': ['ink-formula-burst', 'seal-rewrite'],
      'nurse-pot': ['triage-bloom', 'white-garden-oath'],
      'maestro-pot': ['golden-downbeat', 'silent-coda'],
      'restorer-pot': ['patina-parry', 'golden-seam'],
      'marten-pot': ['softpaw-rush', 'den-guardian-roar'],
      'gal-pot': ['patchwork-relay', 'runway-reversal'],
      'archive_guide': ['archive-lantern', 'archive-seal'],
    };
    var count = 0;
    for (final entry in skills.entries) {
      for (final skill in entry.value) {
        final asset = 'assets/adventure/sfx/skill-${entry.key}-$skill.wav';
        final data = await rootBundle.load(asset);
        expect(data.getUint32(0, Endian.big), 0x52494646, reason: asset);
        count++;
      }
    }
    expect(count, 32);
  });

  testWidgets('엉킴 24·수호자 14의 공격 signature를 앱 번들에서 읽는다', (tester) async {
    const enemies = <String, List<String>>{
      'tangled-ledger': ['paper-flurry', 'ink-mist'],
      'drifting-pressings': ['petal-gust', 'petal-dart'],
      'shelf-snarl': ['shelf-sweep', 'catalogue-rain'],
      'knotted-echo': ['echo-ring', 'sharp-note'],
      'splashing-droplets': ['splash-wave', 'water-pop'],
      'bell-knot-swirl': ['bell-spin', 'deep-toll'],
      'snarled-stardust': ['dust-flare', 'dust-lash'],
      'rolling-seedbox': ['box-roll', 'seed-scatter'],
      'backwound-clockspring': ['spring-snap', 'gear-grind'],
      'ring-shard-tangle': ['ring-spin', 'shard-scatter'],
      'scattered-records': ['page-storm', 'paper-cut'],
      'matted-observatory': ['lens-glare', 'tape-whip'],
    };
    var count = 0;
    for (final entry in enemies.entries) {
      for (final attack in entry.value) {
        final asset = 'assets/adventure/sfx/enemy-${entry.key}-$attack.wav';
        final data = await rootBundle.load(asset);
        expect(data.getUint32(0, Endian.big), 0x52494646, reason: asset);
        count++;
      }
    }
    expect(count, 24);

    // 네 지역의 수호자 전부. 지역을 실었는데 수호자만 소리가 없으면
    // 눈으로는 안 보인다.
    const guardians = <String, List<String>>{
      'ledger-keeper': [
        'ledger-claw',
        'record-wave',
        'seal-crush',
        'root-lockdown',
        'final-redaction',
      ],
      'bell-ringer': ['toll-sweep', 'drown-peal', 'undertow'],
      'germination-clock': [
        'mainspring-lash',
        'escapement-grind',
        'frost-bite',
      ],
      'ring-watcher': ['ringread-turn', 'record-gale', 'lens-focus'],
    };
    var guardianCount = 0;
    for (final entry in guardians.entries) {
      for (final attack in entry.value) {
        final asset = 'assets/adventure/sfx/guardian-${entry.key}-$attack.wav';
        final data = await rootBundle.load(asset);
        expect(data.getUint32(0, Endian.big), 0x52494646, reason: asset);
        guardianCount++;
      }
    }
    expect(guardianCount, 14);
  });

  testWidgets('네 지역의 8개 ambience를 앱 번들에서 읽는다', (tester) async {
    const slugs = <String>[
      'moss-archive',
      'echo-well',
      'starlight-seed-vault',
      'heartwood-observatory',
    ];
    for (final slug in slugs) {
      for (final layer in const ['a', 'b']) {
        final asset = 'assets/adventure/ambience/$slug-$layer.m4a';
        final data = await rootBundle.load(asset);
        expect(data.lengthInBytes, greaterThan(100000), reason: asset);
        expect(data.getUint32(4, Endian.big), 0x66747970,
            reason: '$asset ftyp');
      }
    }
  });

  test('ambience 경로는 지역을 따르고 모르는 지역은 첫 지역으로 떨어진다', () {
    expect(
      ExpeditionCombatAudio.ambiencePath('echo_well', 'a'),
      'adventure/ambience/echo-well-a.m4a',
    );
    expect(
      ExpeditionCombatAudio.ambiencePath('heartwood_observatory', 'b'),
      'adventure/ambience/heartwood-observatory-b.m4a',
    );
    // 모르는 지역이 무음이 되지 않는다.
    expect(
      ExpeditionCombatAudio.ambiencePath('알 수 없음', 'a'),
      'adventure/ambience/moss-archive-a.m4a',
    );
    expect(
      ExpeditionCombatAudio.ambiencePath(null, 'b'),
      'adventure/ambience/moss-archive-b.m4a',
    );
  });

  testWidgets('네 지역의 12개 BGM을 앱 번들에서 읽는다', (tester) async {
    const slugs = <String>[
      'moss-archive',
      'echo-well',
      'starlight-seed-vault',
      'heartwood-observatory',
    ];
    for (final slug in slugs) {
      for (final state in const ['base', 'combat', 'guardian']) {
        final asset = 'assets/adventure/music/$slug-$state.m4a';
        final data = await rootBundle.load(asset);
        expect(data.lengthInBytes, greaterThan(100000), reason: asset);
        // ISO base media file — 4바이트 크기 뒤에 'ftyp' 상자가 온다.
        expect(data.getUint32(4, Endian.big), 0x66747970,
            reason: '$asset ftyp');
      }
    }
  });

  test('지역마다 다른 BGM 경로를 고르고 모르는 지역은 첫 지역으로 떨어진다', () {
    expect(
      ExpeditionCombatAudio.musicPath('echo_well', ExpeditionMusicState.base),
      'adventure/music/echo-well-base.m4a',
    );
    expect(
      ExpeditionCombatAudio.musicPath(
        'heartwood_observatory',
        ExpeditionMusicState.guardian,
      ),
      'adventure/music/heartwood-observatory-guardian.m4a',
    );

    const regions = [
      'moss_archive',
      'echo_well',
      'starlight_seed_vault',
      'heartwood_observatory',
    ];
    final paths = <String>{
      for (final region in regions)
        for (final state in ExpeditionMusicState.values)
          ExpeditionCombatAudio.musicPath(region, state),
    };
    expect(paths.length, 12, reason: '지역 4 × 상태 3이 모두 다른 파일이어야 한다');

    // 지역을 모르는 구버전 응답도 무음이 되지 않는다.
    expect(
      ExpeditionCombatAudio.musicPath(null, ExpeditionMusicState.combat),
      'adventure/music/moss-archive-combat.m4a',
    );
    expect(
      ExpeditionCombatAudio.musicPath('unknown', ExpeditionMusicState.base),
      'adventure/music/moss-archive-base.m4a',
    );
  });

  test('전투 응답의 지역 코드를 읽어 BGM 선택에 넘긴다', () {
    final battle = ExpeditionBattle.fromJson(const {
      'status': 'active',
      'enemy_kind': 'tangle',
      'region_code': 'starlight_seed_vault',
      'enemy': {'name': '뒤엉킨 별가루'},
      'party': <Map<String, dynamic>>[],
      'last_exchange': <Map<String, dynamic>>[],
      'battle_log': <String>[],
    });
    expect(battle.regionCode, 'starlight_seed_vault');
    expect(
      ExpeditionCombatAudio.musicPath(
        battle.regionCode,
        ExpeditionMusicState.combat,
      ),
      'adventure/music/starlight-seed-vault-combat.m4a',
    );

    // 웨이브가 없는 구버전 수호전 응답에는 지역이 없다.
    final legacy = ExpeditionBattle.fromJson(const {
      'status': 'active',
      'enemy': {'name': '돌비늘 장부지기'},
      'party': <Map<String, dynamic>>[],
      'last_exchange': <Map<String, dynamic>>[],
      'battle_log': <String>[],
    });
    expect(legacy.regionCode, isNull);
  });

  test('소리·배속·짧은 연출은 저장되고 AUTO는 저장되지 않는다', () {
    const tuned = ExpeditionBattleSettings(
      autoMode: ExpeditionAutoMode.continuous,
      pace: 2,
      shortEffects: true,
      audioMode: ExpeditionAudioMode.sfxOnly,
    );
    final restored = ExpeditionBattleSettings.decode(tuned.encode());

    expect(restored.audioMode, ExpeditionAudioMode.sfxOnly);
    expect(restored.pace, 2);
    expect(restored.shortEffects, isTrue);
    // 품질 기준의 `자동 지휘는 초기 OFF`. 지난 전투에서 켰다는 이유로 이번
    // 전투를 앱이 대신 지휘하기 시작하면 안 된다.
    expect(restored.autoMode, ExpeditionAutoMode.off);
    expect(tuned.encode().contains('auto'), isFalse);
  });

  test('손상되거나 이전 스키마인 설정은 기본값으로 떨어진다', () {
    expect(
      () => ExpeditionBattleSettings.decode('{"schema_version":0}'),
      throwsFormatException,
    );
    expect(
      () => ExpeditionBattleSettings.decode('not json'),
      throwsA(isA<FormatException>()),
    );
    // 스키마는 맞지만 값이 깨진 경우에는 판정이 바뀌지 않게 좁힌다.
    final broken = ExpeditionBattleSettings.decode(
      '{"schema_version":1,"audio_mode":"loud","pace":99,"short_effects":"y"}',
    );
    expect(broken.audioMode, ExpeditionAudioMode.all);
    expect(broken.pace, 1);
    expect(broken.shortEffects, isFalse);
  });

  test('저장된 설정을 앱 시작 때 되살리고 바꾸면 다시 저장한다', () async {
    final storage = _FakeExpeditionSettingsStorage(
      const ExpeditionBattleSettings(
        audioMode: ExpeditionAudioMode.muted,
        pace: 2,
      ).encode(),
    );
    final container = ProviderContainer(
      overrides: [
        expeditionSettingsStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    // 첫 build는 기본값이고, 저장소를 읽은 뒤 지난 선택으로 바뀐다.
    expect(
      container.read(expeditionBattleSettingsProvider).audioMode,
      ExpeditionAudioMode.all,
    );
    await container.read(expeditionSettingsStoreProvider).load();
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(expeditionBattleSettingsProvider).audioMode,
      ExpeditionAudioMode.muted,
    );
    expect(container.read(expeditionBattleSettingsProvider).pace, 2);

    container.read(expeditionBattleSettingsProvider.notifier).cycleAudioMode();
    await Future<void>.delayed(Duration.zero);
    expect(
      ExpeditionBattleSettings.decode(storage.value!).audioMode,
      ExpeditionAudioMode.all,
    );
  });

  test('저장소가 막혀 있어도 설정 변경과 전투는 계속된다', () async {
    final container = ProviderContainer(
      overrides: [
        expeditionSettingsStorageProvider
            .overrideWithValue(_BrokenExpeditionSettingsStorage()),
      ],
    );
    addTearDown(container.dispose);

    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(expeditionBattleSettingsProvider.notifier);
    notifier.cycleAudioMode();
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(expeditionBattleSettingsProvider).audioMode,
      ExpeditionAudioMode.sfxOnly,
    );
  });

  testWidgets('모험 확정음 4종을 앱 번들에서 읽는다', (tester) async {
    // 문서가 순간마다 정한 길이 상한. 44.1kHz 16bit 모노라 헤더에서
    // 재생 시간을 바로 계산할 수 있다.
    const limits = <String, int>{
      'patrol-depart': 300,
      'patrol-return': 450,
      'dungeon-clear': 400,
      'research-complete': 350,
    };
    for (final entry in limits.entries) {
      final asset = 'assets/adventure/sfx/cue-${entry.key}.wav';
      final data = await rootBundle.load(asset);
      expect(data.getUint32(8, Endian.big), 0x57415645, reason: '$asset WAVE');
      expect(data.getUint16(22, Endian.little), 1, reason: '$asset 모노');

      final sampleRate = data.getUint32(24, Endian.little);
      final byteRate = data.getUint32(28, Endian.little);
      final durationMs = (data.lengthInBytes - 44) / byteRate * 1000;
      expect(sampleRate, 44100, reason: asset);
      expect(
        durationMs,
        lessThanOrEqualTo(entry.value.toDouble()),
        reason: '$asset 은 ${entry.value}ms 안이어야 한다',
      );
    }
  });
}

class _FakeExpeditionSettingsStorage implements ExpeditionSettingsStorage {
  _FakeExpeditionSettingsStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> clear() async => value = null;
}

class _BrokenExpeditionSettingsStorage implements ExpeditionSettingsStorage {
  @override
  Future<String?> read() async => throw StateError('저장소를 쓸 수 없습니다');

  @override
  Future<void> write(String value) async => throw StateError('저장소를 쓸 수 없습니다');

  @override
  Future<void> clear() async => throw StateError('저장소를 쓸 수 없습니다');
}

void _combatChoiceContractTests() {
  test('선택이 필요한 행동은 후보와 현재값을 서버에서 그대로 받는다', () {
    final action = ExpeditionBattleAction.fromJson(const {
      'slot': 'selected_1',
      'code': 'resonance_tuner',
      'name': '마음결 조율기',
      'available': true,
      'choice_kind': 'kel',
      'choice_current': 'sunny',
      'choice_options': [
        {'value': 'sunny', 'label': '햇살결'},
        {'value': 'ember', 'label': '잉걸결'},
      ],
    });

    expect(action.needsChoice, isTrue);
    expect(action.choiceCurrent, 'sunny');
    expect(
      action.choiceOptions.map((option) => option.label),
      ['햇살결', '잉걸결'],
    );
  });

  test('고를 것이 없는 행동은 선택 단계를 거치지 않는다', () {
    final plain = ExpeditionBattleAction.fromJson(const {
      'slot': 'selected_1',
      'code': 'short_cheer',
      'available': true,
    });

    expect(plain.needsChoice, isFalse);
    expect(plain.choiceKind, isNull);
    expect(plain.choiceOptions, isEmpty);

    // 무엇을 고르는지는 말했지만 후보가 비어 있으면 띄울 화면이 없다.
    // 선택지 없는 시트를 여느니 그냥 보내고 서버 판정을 받는다.
    final empty = ExpeditionBattleAction.fromJson(const {
      'slot': 'selected_1',
      'available': true,
      'choice_kind': 'kel',
      'choice_options': <Map<String, dynamic>>[],
    });
    expect(empty.needsChoice, isFalse);
  });

  test('대원·기록서 선택도 같은 계약으로 읽는다', () {
    final handoff = ExpeditionBattleAction.fromJson(const {
      'slot': 'selected_2',
      'code': 'nine_tail_afterimage',
      'available': true,
      'choice_kind': 'member',
      'choice_current': '1',
      'choice_options': [
        {'value': '2', 'label': '볕이'},
      ],
    });
    expect(handoff.needsChoice, isTrue);
    expect(handoff.choiceKind, 'member');
    expect(handoff.choiceOptions.single.label, '볕이');

    final swap = ExpeditionBattleAction.fromJson(const {
      'slot': 'selected_2',
      'code': 'heart_encyclopedia',
      'available': true,
      'choice_kind': 'book',
      'choice_current': 'clear_aim',
      'choice_options': [
        {'value': 'leaf_greave', 'label': '잎사귀 각반'},
      ],
    });
    expect(swap.needsChoice, isTrue);
    expect(swap.choiceCurrent, 'clear_aim');
  });

  test('잠긴 사유는 서버 문장을 그대로 쓰고 없을 때만 레벨로 떨어진다', () {
    final noTarget = ExpeditionBattleAction.fromJson(const {
      'slot': 'selected_2',
      'available': false,
      'unlock_level': 23,
      'lock_reason': '넘길 다른 대원이 없어요.',
    });
    expect(noTarget.lockReason, '넘길 다른 대원이 없어요.');

    final levelLocked = ExpeditionBattleAction.fromJson(const {
      'slot': 'selected_2',
      'available': false,
      'unlock_level': 23,
    });
    expect(levelLocked.lockReason, isNull);
  });

  test('고르지 않은 명령은 choice 키 자체를 보내지 않는다', () {
    const plain = ExpeditionCombatCommand(memberId: 1, action: 'attack');
    expect(plain.toJson().containsKey('choice'), isFalse);

    const chosen = ExpeditionCombatCommand(
      memberId: 1,
      action: 'selected_1',
      choice: 'ember',
    );
    expect(chosen.toJson()['choice'], 'ember');
  });
}

void _deepSurveyTests() {
  test('깊은 조사 잠금 상태를 서버 문장 그대로 읽는다', () {
    final locked = ExpeditionCatalog.fromJson(const {
      'content_version': 'v1',
      'entry': {
        'diary_ready': true,
        'heart_resonance_available': true,
        'free_explore_available': true,
        'deep_available': false,
        'deep_locked_reason': '지역의 8스테이지를 모두 마치면 열려요',
      },
      'regions': <Map<String, dynamic>>[],
    });

    expect(locked.deepAvailable, isFalse);
    // 조건을 앱이 다시 세지 않는다. 두 곳이 어긋나면 채운 줄 알았는데 안 열린다.
    expect(locked.deepLockedReason, '지역의 8스테이지를 모두 마치면 열려요');

    final open = ExpeditionCatalog.fromJson(const {
      'content_version': 'v1',
      'entry': {
        'diary_ready': true,
        'heart_resonance_available': true,
        'free_explore_available': true,
        'deep_available': true,
        'deep_locked_reason': null,
      },
      'regions': <Map<String, dynamic>>[],
    });
    expect(open.deepAvailable, isTrue);
    expect(open.deepLockedReason, isNull);
  });

  test('깊은 조사를 모르는 구버전 응답도 깨지지 않는다', () {
    // 필드가 없으면 잠긴 것으로 읽는다. 없는 모드를 열어 두는 것보다 안전하다.
    final legacy = ExpeditionCatalog.fromJson(const {
      'content_version': 'v1',
      'entry': {'diary_ready': true},
      'regions': <Map<String, dynamic>>[],
    });
    expect(legacy.deepAvailable, isFalse);
    expect(legacy.deepLockedReason, isNull);
  });
}

void _regionSceneTests() {
  test('같은 장면도 지역이 다르면 다르게 읽힌다', () {
    // 지역을 안 주면 지금까지와 똑같다 — 준비 화면처럼 지역이 아직 없는 자리가 있다.
    final shared = expeditionSceneTheme('flooded_cave');
    final archive =
        expeditionSceneTheme('flooded_cave', regionCode: 'moss_archive');
    expect(archive.assetPath, shared.assetPath);
    expect(archive.accent, shared.accent);

    // 뒤 지역은 강조색이 갈린다. 전용 원화가 오기 전까지의 최소 장치다.
    final well = expeditionSceneTheme('flooded_cave', regionCode: 'echo_well');
    final vault = expeditionSceneTheme(
      'flooded_cave',
      regionCode: 'starlight_seed_vault',
    );
    expect(well.accent, isNot(shared.accent));
    expect(vault.accent, isNot(well.accent));
    // 전용 원화가 아직 없으니 그림은 공용 그대로다.
    expect(well.assetPath, shared.assetPath);

    // 모르는 지역은 공용으로 떨어져 무음이 아니라 무화면이 되지 않는다.
    expect(
      expeditionSceneTheme('flooded_cave', regionCode: '없는지역').accent,
      shared.accent,
    );
  });

  test('지역 색 보정은 첫 지역에 걸리지 않고 뒤 지역만 갈라 준다', () {
    expect(expeditionRegionGrade('moss_archive').a, 0);
    expect(expeditionRegionGrade(null).a, 0);
    expect(expeditionRegionGrade('없는지역').a, 0);
    for (final code in const [
      'echo_well',
      'starlight_seed_vault',
      'heartwood_observatory',
    ]) {
      final grade = expeditionRegionGrade(code);
      expect(grade.a, greaterThan(0), reason: code);
      // 너무 진하면 원화가 안 보이고 글자 대비 계약도 흔들린다.
      expect(grade.a, lessThan(.20), reason: code);
    }
  });

  testWidgets('전용 원화 표에 적힌 8장이 실제로 번들에 있다', (tester) async {
    // 표에만 적고 파일이 없으면 그 장면만 검은 화면이 된다. 번들에서 실제로
    // 읽어 봐야 잡힌다 — 경로 문자열만 검사하면 오타를 놓친다.
    expect(expeditionRegionSceneAssets, hasLength(11));
    for (final entry in expeditionRegionSceneAssets.entries) {
      expect(entry.key.split('/'), hasLength(2), reason: entry.key);
      final data = await rootBundle.load(entry.value);
      // RIFF....WEBP
      expect(data.getUint32(0, Endian.big), 0x52494646, reason: entry.value);
      expect(data.getUint32(8, Endian.big), 0x57454250, reason: entry.value);
      expect(data.lengthInBytes, greaterThan(50000), reason: entry.value);

      // 모바일 판본도 함께 있어야 한다. 없으면 작은 화면에서 원본을 통째로
      // 디코드해 메모리가 튄다.
      final mobile = entry.value.replaceFirst('.webp', '-mobile.webp');
      final mobileData = await rootBundle.load(mobile);
      expect(mobileData.getUint32(0, Endian.big), 0x52494646, reason: mobile);
    }
  });

  testWidgets('지역 지형 지도 네 장이 번들에 있고 통행 마스크와 짝이 맞는다', (tester) async {
    // 지형은 걷는 내내 보는 화면이고, 통행 마스크는 그 그림에서 뽑은 것이다.
    // 그림이 없어지거나 마스크만 남으면 캐릭터가 검은 화면 위를 걷는다.
    final terrain = <String, String>{
      'moss_archive': mossArchiveMapAsset,
      ...expeditionRegionTerrain,
    };
    expect(terrain.keys, unorderedEquals(expeditionWalkMasks.keys));
    for (final entry in terrain.entries) {
      final data = await rootBundle.load(entry.value);
      // RIFF....WEBP
      expect(data.getUint32(0, Endian.big), 0x52494646, reason: entry.value);
      expect(data.getUint32(8, Endian.big), 0x57454250, reason: entry.value);
      expect(data.lengthInBytes, greaterThan(50000), reason: entry.value);

      final mobile = entry.value.replaceFirst('.webp', '-mobile.webp');
      final mobileData = await rootBundle.load(mobile);
      expect(mobileData.getUint32(0, Endian.big), 0x52494646, reason: mobile);
    }
    // 전용 지형이 없는 지역은 첫 지역 지도로 떨어진다.
    expect(expeditionTerrainAsset(null), mossArchiveMapAsset);
    expect(expeditionTerrainAsset('없는지역'), mossArchiveMapAsset);
  });

  test('전용 원화가 있는 장면에는 색 보정을 겹쳐 얹지 않는다', () {
    // 보정은 공용 원화를 지역별로 갈라 주려고 있는 것이다. 이미 그 지역 색으로
    // 그려진 그림에 또 얹으면 두 번 물든다.
    expect(
      expeditionRegionGrade('echo_well', sceneKey: 'monster_den').a,
      0,
    );
    expect(
      expeditionRegionGrade('starlight_seed_vault', sceneKey: 'treasure_vault')
          .a,
      0,
    );
    // 전용 원화가 없는 장면은 여전히 보정을 받는다.
    expect(
      expeditionRegionGrade('echo_well', sceneKey: 'flooded_cave').a,
      greaterThan(0),
    );
    // 장면을 모르면 지역 기준으로만 판단한다(기존 동작).
    expect(expeditionRegionGrade('echo_well').a, greaterThan(0));
  });

  test('전용 원화가 있으면 그 지역에서 실제로 그 그림을 고른다', () {
    final shared = expeditionSceneTheme('monster_den');
    final well = expeditionSceneTheme('monster_den', regionCode: 'echo_well');
    final vault = expeditionSceneTheme(
      'monster_den',
      regionCode: 'starlight_seed_vault',
    );
    expect(well.assetPath, isNot(shared.assetPath));
    expect(vault.assetPath, isNot(well.assetPath));
    expect(well.assetPath, contains('echo-well'));

    // 전용 원화가 없는 조합은 공용으로 떨어진다.
    expect(
      expeditionSceneTheme('flooded_cave', regionCode: 'echo_well').assetPath,
      expeditionSceneTheme('flooded_cave').assetPath,
    );
  });
}

void _walkRouteTests() {
  test('길은 그림에 그려진 길을 따라가고 물·수풀을 밟지 않는다', () {
    // 전에는 두 노드를 잇고 가운데를 해시로 부풀린 굽이를 썼다. 굽는 방향이
    // 그림과 아무 상관이 없어 개울을 가로질렀다. 이제는 통행 마스크 위에서
    // 찾으므로 길 밖으로 나갈 수 없다.
    for (final region in _regionsWithTerrain) {
      final area = expeditionWalkAreaFor(region);
      final nodes = _layoutFor(region);
      for (final edge in _edgesFor(region)) {
        final from = expeditionStandPoint(area, nodes[edge[0]]!);
        final to = expeditionStandPoint(area, nodes[edge[1]]!);
        final route = expeditionWalkPath(area, from, to);
        expect(
          route.length,
          greaterThan(1),
          reason: '$region의 ${edge[0]} → ${edge[1]} 길을 못 찾습니다',
        );
        expect(
          expeditionRouteStaysInside(area, route),
          isTrue,
          reason: '$region의 ${edge[0]} → ${edge[1]} 길이 걸을 수 없는 곳을 지납니다',
        );
      }
    }
  });

  test('길은 벽에 붙지 않아 토큰이 벽을 먹지 않는다', () {
    final area = expeditionWalkAreaFor('echo_well');
    final nodes = _layoutFor('echo_well');
    final route = expeditionWalkPath(
      area,
      expeditionStandPoint(area, nodes['entrance']!),
      expeditionStandPoint(area, nodes['guardian']!),
    );
    expect(expeditionPathKeepsClear(area, route), isTrue);
  });

  test('같은 두 자리를 물으면 언제나 같은 길이 나온다', () {
    // 캐릭터와 발자국이 따로 물어보므로, 답이 흔들리면 둘이 갈라진다.
    final area = expeditionWalkAreaFor('heartwood_observatory');
    final nodes = _layoutFor('heartwood_observatory');
    final from = expeditionStandPoint(area, nodes['entrance']!);
    final to = expeditionStandPoint(area, nodes['objective']!);
    expect(
        expeditionWalkPath(area, from, to), expeditionWalkPath(area, from, to));
  });

  test('걸음은 굽은 곳에서도 일정한 속도로 나아간다', () {
    final area = expeditionWalkAreaFor('echo_well');
    final nodes = _layoutFor('echo_well');
    final route = expeditionWalkPath(
      area,
      expeditionStandPoint(area, nodes['entrance']!),
      expeditionStandPoint(area, nodes['objective']!),
    );

    // 진행도를 고르게 나눴을 때 이동 거리도 고르게 나와야 한다. 조각 번호로
    // 나누면 굽은 구간에서 걸음이 빨라진다.
    const aspect = 16 / 9;
    double gap(Offset a, Offset b) {
      final dx = (a.dx - b.dx) * aspect;
      final dy = a.dy - b.dy;
      return math.sqrt(dx * dx + dy * dy);
    }

    final steps = <double>[];
    for (var i = 0; i < 10; i++) {
      steps.add(gap(
        expeditionPathPosition(route, i / 10),
        expeditionPathPosition(route, (i + 1) / 10),
      ));
    }
    final shortest = steps.reduce(math.min);
    final longest = steps.reduce(math.max);
    expect(longest / shortest, lessThan(1.25));

    expect(expeditionPathPosition(route, 0), route.first);
    expect(expeditionPathPosition(route, 1), route.last);
  });

  test('걷는 방향은 좌우로만 갈리고 수직 이동에서는 파닥이지 않는다', () {
    const rightward = [Offset(.1, .5), Offset(.5, .5), Offset(.9, .5)];
    expect(expeditionPathFacing(rightward, .5), 1);

    const leftward = [Offset(.9, .5), Offset(.5, .5), Offset(.1, .5)];
    expect(expeditionPathFacing(leftward, .5), -1);

    // 세로로만 걷는 구간에서 0을 돌려주면 캐릭터가 정면을 봤다 돌았다 한다.
    const upward = [Offset(.5, .9), Offset(.5, .5), Offset(.5, .1)];
    expect(expeditionPathFacing(upward, .5).abs(), 1);

    // 점 하나짜리 길에서는 기본 방향을 지킨다.
    expect(expeditionPathFacing(const [Offset(.5, .5)], .5), 1);
  });

  test('장면이 발소리 재질을 정하고 모르는 장면은 화분 소리로 떨어진다', () {
    // 젖은 곳에서 나무 소리가 나면 눈과 귀가 다른 말을 한다.
    expect(
      ExpeditionCombatAudio.stepSoundFor('flooded_cave'),
      ExpeditionCombatSound.stepStone,
    );
    expect(
      ExpeditionCombatAudio.stepSoundFor('root_tunnel'),
      ExpeditionCombatSound.stepLeaf,
    );
    expect(
      ExpeditionCombatAudio.stepSoundFor('moon_tower'),
      ExpeditionCombatSound.stepWood,
    );
    // 주인공은 화분이라 모르는 바닥에서도 자기 몸 소리가 난다 — 무음이 아니다.
    expect(
      ExpeditionCombatAudio.stepSoundFor('없는장면'),
      ExpeditionCombatSound.stepPot,
    );
    expect(
      ExpeditionCombatAudio.stepSoundFor(null),
      ExpeditionCombatSound.stepPot,
    );
  });
}

/// 생성기(`server/scripts/build_region_packs.py`)의 `NODE_LAYOUT`과 같은 자리.
///
/// 세 지역이 이 배치를 공유한다. 기억서고는 자기 배치를 쓴다(`_mossLayout`).
/// 여기 값이 서버와 어긋나면 벽 속에 박힌 노드를 `땅 안에 있다`고 통과시킨다.
///
/// 서버 쪽에도 같은 좌표가 박혀 있고(`test_node_layout_is_pinned_because_the_app_mirrors_it`),
/// 자리를 옮기려면 **두 표를 함께** 고쳐야 한다. 한쪽만 고치면 그 테스트가 잡는다.
const _nodeLayout = <String, Offset>{
  'entrance': Offset(.08, .50),
  'first_event': Offset(.27, .30),
  'second_event': Offset(.27, .70),
  'camp': Offset(.48, .50),
  'discovery': Offset(.50, .20),
  'guardian': Offset(.69, .50),
  'objective': Offset(.86, .32),
  'exit': Offset(.94, .62),
};

const _sharedEdges = <List<String>>[
  ['entrance', 'first_event'],
  ['entrance', 'second_event'],
  ['first_event', 'camp'],
  ['second_event', 'camp'],
  ['camp', 'discovery'],
  ['camp', 'guardian'],
  ['guardian', 'objective'],
  ['objective', 'exit'],
  // 갈래길·고리길 템플릿이 더 쓰는 간선.
  ['first_event', 'discovery'],
  ['second_event', 'discovery'],
  ['discovery', 'guardian'],
  ['first_event', 'second_event'],
];

/// 기억서고는 노드 이름도 자리도 다르다. 가운데 야영지 대신 위아래로 갈린
/// 마름모라, 공용 배치를 그대로 대면 아래쪽 노드가 벽에 박힌다.
const _mossLayout = <String, Offset>{
  'entrance': Offset(.08, .50),
  'wet_labels': Offset(.28, .27),
  'root_catalogue': Offset(.29, .72),
  'quiet_camp': Offset(.49, .19),
  'pressed_gallery': Offset(.50, .81),
  'ledger_keeper': Offset(.69, .50),
  'memory_drawer': Offset(.84, .34),
  'exit': Offset(.93, .67),
};

const _mossEdges = <List<String>>[
  ['entrance', 'wet_labels'],
  ['entrance', 'root_catalogue'],
  ['wet_labels', 'quiet_camp'],
  ['wet_labels', 'pressed_gallery'],
  ['root_catalogue', 'quiet_camp'],
  ['root_catalogue', 'pressed_gallery'],
  ['quiet_camp', 'pressed_gallery'],
  ['quiet_camp', 'ledger_keeper'],
  ['pressed_gallery', 'ledger_keeper'],
  ['ledger_keeper', 'memory_drawer'],
  ['memory_drawer', 'exit'],
];

/// 전용 지형 원화가 있는 지역. 통행 마스크도 이만큼 있다.
const _regionsWithTerrain = <String>[
  'moss_archive',
  'echo_well',
  'starlight_seed_vault',
  'heartwood_observatory',
];

Map<String, Offset> _layoutFor(String region) =>
    region == 'moss_archive' ? _mossLayout : _nodeLayout;

List<List<String>> _edgesFor(String region) =>
    region == 'moss_archive' ? _mossEdges : _sharedEdges;

void _walkAreaTests() {
  test('네 지역이 저마다 통행 마스크를 가진다', () {
    for (final region in _regionsWithTerrain) {
      final area = expeditionWalkAreaFor(region);
      expect(area.rows, isNotEmpty, reason: '$region의 마스크가 없습니다');
      expect(area.rows.length, expeditionWalkMaskRows);
      for (final row in area.rows) {
        expect(row.length, expeditionWalkMaskColumns);
      }
    }
    // 모르는 지역도 걸을 땅을 얻어 못 움직이는 일이 없다.
    expect(expeditionWalkAreaFor(null).rows, isNotEmpty);
    expect(expeditionWalkAreaFor('없는지역').rows, isNotEmpty);
  });

  test('걸을 수 있는 땅은 길만큼이지 지도 전체가 아니다', () {
    for (final region in _regionsWithTerrain) {
      final coverage =
          expeditionWalkAreaCoverage(expeditionWalkAreaFor(region));
      // 너무 좁으면 걸어 다닐 곳이 없다.
      expect(coverage, greaterThan(.10), reason: '$region이 너무 좁습니다');
      // 지도 전체를 덮으면 경계가 없는 것과 같다 — 개울 위를 걷던 시절로
      // 되돌아간다.
      expect(coverage, lessThan(.45), reason: '$region이 너무 넓습니다');
    }
  });

  test('노드마다 설 자리가 있고 표식에서 멀지 않다', () {
    // 설 자리가 없으면 그 노드는 **영원히 닿을 수 없는 자리**다. 반대로 너무
    // 멀면 표식과 캐릭터가 따로 논다.
    const aspect = 16 / 9;
    for (final region in _regionsWithTerrain) {
      final area = expeditionWalkAreaFor(region);
      _layoutFor(region).forEach((code, marker) {
        final stand = expeditionStandPoint(area, marker);
        expect(area.contains(stand), isTrue, reason: '$region의 $code');
        final dx = (stand.dx - marker.dx) * aspect;
        final dy = stand.dy - marker.dy;
        expect(
          math.sqrt(dx * dx + dy * dy),
          lessThan(.24),
          reason: '$region의 $code가 표식에서 너무 멉니다',
        );
        // 가장자리에 딱 붙으면 88px 토큰이 벽을 먹는다.
        expect(
          expeditionWalkAreaMargin(area, stand),
          greaterThan(.01),
          reason: '$region의 $code가 벽에 너무 가깝습니다',
        );
      });
    }
  });

  test('그림에 없는 자리는 걸을 수 없다', () {
    // 볼록 다각형 하나로 감쌌을 때 실제로 걸을 수 있던 자리들이다. 개울과
    // 유적 위를 걷던 그 시절로 되돌아가지 않았는지 못 박아 둔다.
    final echo = expeditionWalkAreaFor('echo_well');
    // 지도 네 귀퉁이는 밤 수풀이다.
    for (final corner in const [
      Offset(.02, .02),
      Offset(.98, .02),
      Offset(.02, .98),
      Offset(.98, .98),
    ]) {
      expect(echo.contains(corner), isFalse, reason: '$corner');
    }
    // 기억서고 개울.
    final moss = expeditionWalkAreaFor('moss_archive');
    expect(moss.contains(const Offset(.20, .13)), isFalse);
  });

  test('벽으로 걸어가면 멈추지 않고 벽을 따라 미끄러진다', () {
    final area = expeditionWalkAreaFor('echo_well');
    final inside = expeditionStandPoint(area, const Offset(.48, .50));
    expect(area.contains(inside), isTrue);

    // 어떤 방향으로 밀어도 땅을 벗어나지 않는다.
    for (final delta in const [
      Offset(.4, 0),
      Offset(-.4, 0),
      Offset(0, .4),
      Offset(0, -.4),
      Offset(.3, .3),
      Offset(-.3, -.3),
    ]) {
      final next = expeditionStepWithin(area, inside, delta);
      expect(area.contains(next), isTrue, reason: '$delta 로 벗어났습니다');
    }

    // 벽에 정면으로 부딪혀도 한 축은 살아 있어야 한다 — 완전히 멈추면 조작이
    // 걸린 것처럼 느껴진다. 벽을 찾아 실제로 밀어 본다.
    var wall = inside;
    for (var step = 0; step < 40; step++) {
      final next = expeditionStepWithin(area, wall, const Offset(0, -.01));
      if (next == wall) break;
      wall = next;
    }
    final slid = expeditionStepWithin(area, wall, const Offset(.03, -.03));
    expect(slid.dx, greaterThan(wall.dx));
    expect(area.contains(slid), isTrue);
  });
}

/// 사방이 가장 넓게 트인 자리. 걸음 테스트가 벽이 아니라 걸음을 재게 한다.
Offset _openGround(ExpeditionWalkArea area) {
  var best = const Offset(.5, .5);
  var bestMargin = -1.0;
  for (var row = 0; row < area.rows.length; row++) {
    for (var column = 0; column < area.columns; column++) {
      if (!area.cellAt(column, row)) continue;
      final point = Offset(
        (column + .5) / area.columns,
        (row + .5) / area.rows.length,
      );
      final margin = expeditionWalkAreaMargin(area, point);
      if (margin > bestMargin) {
        bestMargin = margin;
        best = point;
      }
    }
  }
  return best;
}

void _freeWalkTests() {
  test('스틱은 죽은 구역에서 움직이지 않고 바깥에서 0부터 세진다', () {
    const center = Offset(100, 100);

    // 손가락을 얹기만 해도 캐릭터가 흐르면 안 된다.
    expect(expeditionStickVector(center, center), Offset.zero);
    expect(
      expeditionStickVector(center, center + const Offset(5, 0)),
      Offset.zero,
    );

    // 죽은 구역 바로 바깥에서 갑자기 최고 속도가 되지 않는다.
    final justOutside = expeditionStickVector(
      center,
      center + const Offset(expeditionStickDeadZone + 1, 0),
    );
    expect(justOutside.distance, lessThan(.1));

    // 끝까지 밀면 1이다.
    final full = expeditionStickVector(
      center,
      center + const Offset(expeditionStickRadius * 2, 0),
    );
    expect(full.distance, closeTo(1, .001));
    expect(full.dx, greaterThan(0));
  });

  test('손잡이는 반지름 밖으로 나가지 않는다', () {
    const center = Offset(100, 100);
    final far = expeditionStickKnob(center, center + const Offset(300, 0));
    expect((far - center).distance, closeTo(expeditionStickRadius, .001));

    // 안쪽이면 손가락을 그대로 따라간다.
    const near = Offset(120, 100);
    expect(expeditionStickKnob(center, near), near);
  });

  test('가로세로 비율을 보정해 화면에서 같은 속도로 걷는다', () {
    // 통행 마스크는 그림에서 뽑은 길이라 `(.5,.5)`가 걸을 수 있는 자리라는
    // 보장이 없다. 사방이 트인 자리를 골라 쓴다 — 벽에 막히면 걸음이 줄어
    // 비율이 아니라 벽을 재게 된다.
    final area = expeditionWalkAreaFor('echo_well');
    final from = _openGround(area);
    final right = expeditionWalkStep(
      area: area,
      from: from,
      direction: const Offset(1, 0),
      seconds: .02,
      aspect: 2,
    );
    final down = expeditionWalkStep(
      area: area,
      from: from,
      direction: const Offset(0, 1),
      seconds: .02,
      aspect: 2,
    );
    // 가로가 세로의 두 배인 지도에서 세로로 걸으면, 정규화 좌표로는 두 배를
    // 움직여야 화면에서 같은 거리가 된다.
    expect((down.dy - from.dy) / (right.dx - from.dx), closeTo(2, .01));
  });

  test('걸음은 땅을 벗어나지 않고 멈춰 있으면 그대로다', () {
    final area = expeditionWalkAreaFor('echo_well');
    var position = _openGround(area);

    // 스틱을 놓으면 제자리다.
    expect(
      expeditionWalkStep(
        area: area,
        from: position,
        direction: Offset.zero,
        seconds: .1,
        aspect: 1.6,
      ),
      position,
    );

    // 위로 계속 밀어도 벽을 넘지 않는다.
    for (var i = 0; i < 40; i++) {
      position = expeditionWalkStep(
        area: area,
        from: position,
        direction: const Offset(0, -1),
        seconds: .05,
        aspect: 1.6,
      );
    }
    expect(area.contains(position), isTrue);
  });

  test('스틱만으로 옆 노드까지 실제로 걸어갈 수 있다', () {
    // 단위 함수만 보면 `한 걸음이 안전한가`만 알 수 있다. 실제 조작은 수백
    // 걸음이 이어지는 것이고, 벽에 미끄러지며 쌓인 오차나 좁은 목이 캐릭터를
    // 붙잡을 수 있다. 그래서 길을 따라 스틱을 밀어 **끝까지 닿는지** 본다.
    const aspect = 16 / 9;
    for (final region in _regionsWithTerrain) {
      final area = expeditionWalkAreaFor(region);
      final nodes = _layoutFor(region);
      for (final edge in _edgesFor(region)) {
        final from = expeditionStandPoint(area, nodes[edge[0]]!);
        final goal = expeditionStandPoint(area, nodes[edge[1]]!);
        final route = expeditionWalkPath(area, from, goal);

        var position = from;
        var mark = 1;
        var frames = 0;
        while (mark < route.length && frames < 4000) {
          frames++;
          final target = route[mark];
          final gap = target - position;
          // 한 프레임 걸음(.42/60 ≈ .007)보다 넉넉히 잡는다. 이보다 좁게 잡으면
          // 다음 점을 지나쳤다 되돌아오기를 되풀이해, 걷지 못하는 게 아닌데도
          // 걷지 못하는 것처럼 보인다.
          if (math.sqrt(
                math.pow(gap.dx * aspect, 2) + gap.dy * gap.dy,
              ) <
              .016) {
            mark++;
            continue;
          }
          // 화면 기준 방향으로 민다. 스틱이 주는 것과 같은 모양의 입력이다.
          final direction = Offset(gap.dx * aspect, gap.dy);
          position = expeditionWalkStep(
            area: area,
            from: position,
            direction: direction / direction.distance,
            seconds: 1 / 60,
            aspect: aspect,
          );
          expect(
            area.contains(position),
            isTrue,
            reason: '$region ${edge[0]}→${edge[1]}에서 길 밖으로 나갔습니다',
          );
        }
        expect(
          mark,
          route.length,
          reason: '$region ${edge[0]}→${edge[1]}에서 걷다 붙잡혔습니다',
        );
        final left = goal - position;
        expect(
          math.sqrt(math.pow(left.dx * aspect, 2) + left.dy * left.dy),
          lessThan(.03),
          reason: '$region ${edge[0]}→${edge[1]} 도착 자리가 어긋났습니다',
        );
      }
    }
  });

  test('프레임이 길게 끊겨도 벽을 뛰어넘지 않는다', () {
    // 걸음은 도착 자리만 보고 판정한다. 탭 전환이나 첫 로딩으로 프레임이 한 번
    // 길게 끊기면 한 번에 지도 절반을 옮기게 되고, 그러면 개울 건너편에
    // 착지한다. 실제로 0.5초짜리 프레임을 던져 본다.
    final area = expeditionWalkAreaFor('moss_archive');
    final from = expeditionStandPoint(area, const Offset(.08, .50));
    for (final direction in const [
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1),
      Offset(.7, .7),
      Offset(-.7, -.7),
    ]) {
      final next = expeditionWalkStep(
        area: area,
        from: from,
        direction: direction,
        seconds: .5,
        aspect: 16 / 9,
      );
      expect(area.contains(next), isTrue, reason: '$direction');

      // 긴 프레임 한 번이 짧은 프레임 여럿과 같은 자리에 닿아야 한다. 나눠
      // 걷지 않으면 긴 프레임만 벽 너머로 넘어가 둘이 갈라진다.
      var stepped = from;
      for (var i = 0; i < 30; i++) {
        stepped = expeditionWalkStep(
          area: area,
          from: stepped,
          direction: direction,
          seconds: .5 / 30,
          aspect: 16 / 9,
        );
      }
      expect(
        (next - stepped).distance,
        lessThan(.01),
        reason: '$direction 에서 긴 프레임이 벽을 뛰어넘었습니다',
      );
    }
  });

  test('가장 가까운 노드를 고르고 멀면 아무 데도 아니다', () {
    const nodes = <String, Offset>{
      'camp': Offset(.48, .50),
      'guardian': Offset(.69, .50),
    };

    expect(expeditionNodeAt(nodes, const Offset(.48, .50)), 'camp');
    // 둘 사이 한가운데는 어느 쪽에도 닿지 않는다.
    expect(expeditionNodeAt(nodes, const Offset(.585, .50)), isNull);
    // 살짝 치우치면 가까운 쪽이다 — 뒤쪽 노드가 뽑히면 보는 것과 다른 곳으로
    // 들어간다.
    expect(expeditionNodeAt(nodes, const Offset(.52, .50)), 'camp');
    expect(expeditionNodeAt(nodes, const Offset(.66, .50)), 'guardian');
  });

  test('아래에 있을수록 화면 앞이다', () {
    expect(
      expeditionDepthOf(const Offset(.2, .8)),
      greaterThan(expeditionDepthOf(const Offset(.9, .3))),
    );
  });

  test('그림자는 발이 뜬 만큼 줄고 멈추면 온전하다', () {
    expect(expeditionShadowScale(false, .5), 1);
    final scales = [
      for (var i = 0; i < 12; i++) expeditionShadowScale(true, i / 12),
    ];
    expect(scales.reduce(math.min), lessThan(.85));
    expect(scales.reduce(math.max), lessThanOrEqualTo(1));
  });

  test('다음 라운드 예고는 서버가 열어 줄 때만 실린다', () {
    final enemy = ExpeditionBattleEnemy.fromJson(const {
      'name': '돌비늘 장부지기',
      'guard': 80,
      'max_guard': 100,
      'intent': {'code': 'claw', 'name': '장부 발톱', 'target': 'front', 'power': 1},
      'next_intent': {
        'code': 'record_wave',
        'name': '기록 파동',
        'target': 'all',
        'power': 2,
      },
    });
    expect(enemy.nextIntent?.name, '기록 파동');
    expect(enemy.nextIntent?.targetLabel, '탐험대 전체');

    final plain = ExpeditionBattleEnemy.fromJson(const {
      'name': '돌비늘 장부지기',
      'intent': {'code': 'claw', 'name': '장부 발톱', 'target': 'front', 'power': 1},
    });
    expect(plain.nextIntent, isNull);
  });

  test('편성 화면의 목적지는 지도에서 보고 있는 지역이다', () {
    // 출발은 지도의 지역으로 간다. 목록의 첫 칸을 집으면 네 지역이 권장
    // 단계도 보상도 다 다른데 늘 이끼 기억서고를 안내하게 된다.
    final regions = [
      for (final entry in const [
        ('moss_archive', '이끼 기억서고', 2),
        ('echo_well', '메아리 우물정원', 3),
        ('starlight_seed_vault', '별빛 씨앗 보관고', 4),
      ])
        ExpeditionRegion.fromJson({
          'code': entry.$1,
          'name': entry.$2,
          'description': '',
          'recommended_stage': entry.$3,
          'reward': const {'exp': 6, 'seeds': 2},
        }),
    ];

    expect(
      expeditionDestinationRegion(regions, 'starlight_seed_vault')?.name,
      '별빛 씨앗 보관고',
    );
    expect(
      expeditionDestinationRegion(regions, 'starlight_seed_vault')
          ?.recommendedStage,
      4,
    );
    // 지도를 아직 못 받았거나 모르는 코드면 첫 지역으로 떨어진다.
    expect(expeditionDestinationRegion(regions, null)?.code, 'moss_archive');
    expect(expeditionDestinationRegion(regions, '없는지역')?.code,
        'moss_archive');
    expect(expeditionDestinationRegion(const [], 'echo_well'), isNull);
  });

  test('선택에 걸린 탐험 스킬이 남긴 문장을 사건이 들고 온다', () {
    final event = ExpeditionEvent.fromJson(const {
      'code': 'wet_labels',
      'title': '젖은 이름표',
      'text': '이름이 번진 이름표가 흩어져 있어요.',
      'skill_hint': '이 선택이 남길 기록 종류를 결과 전에 확인했어요.',
      'choices': [],
    });
    expect(event.skillHint, '이 선택이 남길 기록 종류를 결과 전에 확인했어요.');

    // 스킬을 안 썼으면 없다. 없는 문장을 지어내지 않는다.
    final plain = ExpeditionEvent.fromJson(const {
      'code': 'wet_labels',
      'title': '젖은 이름표',
      'text': '이름이 번진 이름표가 흩어져 있어요.',
      'choices': [],
    });
    expect(plain.skillHint, isNull);
  });
}
