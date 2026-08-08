import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/expedition/domain/expedition_models.dart';
import 'package:mongroo/features/expedition/presentation/expedition_controller.dart';
import 'package:mongroo/features/expedition/presentation/expedition_action_cue.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_overlay.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_sprites.dart';
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
      'run_thread': {'current_text': '서고 전체가 천천히 숨 쉬어요.'},
      'memory': {'discoveries': [], 'outcomes': []},
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
  }) =>
      {
        'affinity': affinity,
        'affinity_label': affinityLabel,
        'basic': {
          'code': 'attack',
          'name': '공명 공격',
          'description': '집중력 1을 얻고 장벽을 공격해요.',
          'power': 13,
          'focus_delta': 1,
          'affinity': affinity,
          'affinity_label': affinityLabel,
          'effect_key': affinity == 'care' ? 'care_vines' : 'insight_arc',
        },
        'skill': {
          'code': effect,
          'name': skillName,
          'description': '캐릭터의 개성을 살린 고유 행동이에요.',
          'power': 20,
          'focus_cost': 2,
          'affinity': affinity,
          'affinity_label': affinityLabel,
          'effect_key': affinity == 'care' ? 'care_vines' : 'insight_arc',
          'effect': effect,
        },
        'guard': {
          'code': 'guard',
          'name': '마음 지키기',
          'description': '피해를 두 칸 막고 집중력을 얻어요.',
          'guard': 2,
          'focus_delta': 1,
        },
      };
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
      'member_id': 11,
      'actor_name': '새싹몬',
      'action': 'skill',
      'action_name': '새싹 응원',
      'effect_key': 'care_vines',
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
    expect(mossArchiveMapAsset, endsWith('terrain-v3.webp'));
    final terrain = await rootBundle.load(mossArchiveMapAsset);
    expect(terrain.lengthInBytes, greaterThan(300000));
    for (final asset in {
      ...expeditionEnvironmentAssets,
      ...expeditionCombatAssets,
      mossArchiveMapAsset,
    }) {
      final mobileAsset = expeditionMobileAssetPath(asset);
      final data = await rootBundle.load(mobileAsset);
      expect(data.lengthInBytes, greaterThan(10000), reason: mobileAsset);
      final size = _webpCanvasSize(data);
      expect(
        size.width,
        expeditionCombatAssets.contains(asset)
            ? expeditionMobileGuardianWidth
            : expeditionMobileSceneWidth,
        reason: mobileAsset,
      );
      if (expeditionCombatAssets.contains(asset)) {
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
    ];

    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(7000), reason: asset);
      expect(data.getUint32(0, Endian.big), 0x52494646, reason: '$asset RIFF');
      expect(data.getUint32(8, Endian.big), 0x57415645, reason: '$asset WAVE');
    }
  });

  testWidgets('플레이어와 몬스터 공격을 8프레임 투명 스프라이트로 읽는다', (tester) async {
    const effectKeys = [
      'care_vines',
      'safe_guard',
      'ember_arc',
      'prism_burst',
      'mist_dash',
      'insight_arc',
      'echo_wave',
      'enemy_wave',
    ];

    for (final effectKey in effectKeys) {
      final assets = expeditionCombatEffectAssets(effectKey);
      expect(assets, hasLength(expeditionCombatEffectFrameCount));
      for (final asset in assets) {
        final data = await rootBundle.load(asset);
        final size = _webpCanvasSize(data);
        expect(size, (width: 576, height: 288), reason: asset);
        expect(data.getUint8(20) & 0x10, 0x10, reason: '$asset 알파 채널');
      }
    }
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
    final route = mossArchiveRouteBetween(
      'entrance',
      'wet_labels',
      fallbackFrom: const Offset(.08, .50),
      fallbackTo: const Offset(.28, .27),
    );
    final reverse = mossArchiveRouteBetween(
      'wet_labels',
      'entrance',
      fallbackFrom: const Offset(.28, .27),
      fallbackTo: const Offset(.08, .50),
    );

    expect(route.length, greaterThan(2));
    expect(route.first, const Offset(.08, .50));
    expect(route.last, const Offset(.28, .27));
    expect(reverse, route.reversed.toList());
    expect(mossArchiveRoutePosition(route, 0), route.first);
    expect(mossArchiveRoutePosition(route, 1), route.last);
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

  test('수호전 응답에서 의도·약점·고유 스킬·제로 장벽을 보존한다', () {
    final snapshot = ExpeditionSnapshot.fromJson(_battleSnapshotJson());
    final battle = snapshot.currentEvent!.battle!;

    expect(battle.round, 1);
    expect(battle.enemy.intent.target, 'front');
    expect(battle.enemy.weaknessLabel, '돌봄');
    expect(battle.party.first.kit.skill.effect, 'shield_all');
    expect(battle.party.last.kit.skill.effect, 'study_refund');
    expect(snapshot.lastCombatExchange.single.enemyGuardAfter, 0);
    expect(snapshot.lastCombatExchange.single.weaknessHit, isTrue);
    expect(snapshot.availableActions.map((action) => action['type']), [
      'combat_turn',
      'retreat',
    ]);
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
    final snapshot = ExpeditionSnapshot.fromJson(_battleSnapshotJson());
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

    // 세로 3존 — 상단 정보 바, 대치 무대, 순차 명령 카드 독.
    expect(find.byKey(const ValueKey('seq-command-dock')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('immersive-combat-stage')), findsOneWidget);
    expect(find.text('R 1/6'), findsOneWidget);
    expect(find.textContaining('장부 발톱'), findsWidgets);
    expect(find.text('약점 돌봄'), findsOneWidget);
    // 첫 대기 대원의 이름으로 프롬프트가 열린다.
    expect(find.text('새싹몬은 무엇을 할까요?'), findsOneWidget);
    final auto = tester.widget<FilterChip>(
      find.byKey(const ValueKey('seq-dock-auto')),
    );
    expect(auto.selected, isFalse);

    // 집중력 1로는 스킬(집중 2)을 쓸 수 없다 — 카드가 사유와 함께 잠긴다.
    final skillCard = find.byKey(const ValueKey('seq-dock-card-skill'));
    await tester.ensureVisible(skillCard);
    await tester.pump();
    expect(find.text('집중 부족'), findsOneWidget);
    await tester.tap(skillCard, warnIfMissed: false);
    await tester.pump();
    expect(controller.combatActionRequests, 0);

    // 길게 누르면 잠긴 카드도 설명을 읽을 수 있다.
    await tester.longPress(skillCard);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('캐릭터의 개성을 살린 고유 행동이에요.'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump(const Duration(milliseconds: 300));

    // 의도 줄을 누르면 발견 정보 시트가 열린다.
    final intentLine = find.byKey(const ValueKey('seq-dock-intent'));
    await tester.tap(intentLine);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('상세 생태 기록'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('seq-dock-card-skill')));
    await tester.pump();
    expect(controller.combatActionRequests, 2);
    expect(controller.combatActionLog.last.memberId, 12);
    expect(controller.combatActionLog.last.action, 'skill');

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

  testWidgets('엉킴 웨이브 전투는 웨이브 표기와 절차적 몸체를 보여 준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final raw = _battleSnapshotJson();
    final event = raw['current_event'] as Map<String, dynamic>;
    final battleJson = event['battle'] as Map<String, dynamic>;
    battleJson['enemy_kind'] = 'tangle';
    battleJson['wave'] = {'index': 1, 'count': 2, 'name': '엉킨 장부 뭉치'};
    final enemyJson = battleJson['enemy'] as Map<String, dynamic>;
    enemyJson['name'] = '엉킨 장부 뭉치';
    enemyJson['elite'] = false;
    final snapshot = ExpeditionSnapshot.fromJson(raw);

    final battle = snapshot.currentEvent!.battle!;
    expect(battle.isTangle, isTrue);
    expect(battle.wave!.index, 1);
    expect(battle.wave!.count, 2);
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
    expect(find.text('웨이브 1/2'), findsOneWidget);
    // 엉킴은 절차적 몸체를 그리고 수호짐승 원화는 쓰지 않는다.
    expect(find.byKey(const ValueKey('tangle-body')), findsOneWidget);
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
    final stageTopBefore = tester.getTopLeft(stage).dy;
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
    expect(find.byTooltip('침수 표찰 동굴'), findsOneWidget);
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
    await tester.pump(const Duration(milliseconds: 650));

    expect(find.text('-86'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('combat-effect-insight_arc-frame-4')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger-keeper-hit')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 550));
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
}
