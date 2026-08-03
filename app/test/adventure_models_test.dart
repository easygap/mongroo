import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/adventure/domain/adventure_models.dart';
import 'package:mongroo/features/home/domain/plant.dart';

void main() {
  test('탐험 상태에서 일기 우선 보상과 의상 성능을 읽는다', () {
    final state = AdventureState.fromJson({
      'suspended': false,
      'diary_ready': true,
      'diary_requirement': {
        'message': '오늘 마음을 50자 이상 기록하면 탐험이 열려요.',
      },
      'economy': [
        {'code': 'diary', 'label': '마음 일기', 'exp': 40, 'seeds': 15},
        {'code': 'quest', 'label': '일일 미션', 'exp': 20, 'seeds': 5},
        {'code': 'dungeon', 'label': '던전', 'exp': 10, 'seeds': 4},
      ],
      'character': {
        'plant_id': 3,
        'name': '몽실',
        'stage': 3,
        'form': 'sunny',
        'species_code': 'baby-pot',
        'species_name': '아기 화분',
        'stats': [
          {'code': 'care', 'label': '돌봄', 'value': 8},
        ],
        'outfit': {
          'name': '정원 데일리 셋',
          'layer_key': 'garden-daily',
          'bonus': {'amount': 2, 'label': '순찰 돌봄 +2'},
        },
      },
      'routes': [
        {
          'code': 'greenhouse_edge',
          'name': '온실 가장자리',
          'description': '온실 밖을 살펴봐요.',
          'duration_minutes': 10,
          'required_stage': 2,
          'available': true,
          'recommended_stats': ['돌봄', '관찰'],
          'reward': {'exp': 0, 'seeds': 3, 'item_code': 'leaf_map'},
        },
      ],
      'patrol': null,
      'dungeon_run_available': true,
      'dungeons': [],
      'inventory': [],
    });

    expect(state.diaryReady, isTrue);
    expect(state.economy.first.exp, 40);
    expect(state.economy.first.seeds, 15);
    expect(
        state.economy.first.exp,
        greaterThan(state.economy
            .skip(1)
            .map((entry) => entry.exp)
            .reduce((a, b) => a > b ? a : b)));
    expect(state.character?.form, PlantGrowthForm.sunny);
    expect(state.character?.outfit?.layerKey, 'garden-daily');
    expect(state.character?.outfit?.bonusLabel, '순찰 돌봄 +2');
    expect(state.routes.single.available, isTrue);
  });

  test('돌아오는 시각과 발견한 던전 상태를 파싱한다', () {
    final state = AdventureState.fromJson({
      'patrol': {
        'id': 9,
        'route_name': '온실 가장자리',
        'status': 'active',
        'returns_at': '2026-08-03T12:00:00Z',
        'ready_to_claim': false,
        'performance_score': 16,
      },
      'dungeons': [
        {
          'code': 'moss_archive',
          'name': '이끼 낀 기억서고',
          'description': '표본 서고',
          'required_stage': 2,
          'discovered': true,
          'available': true,
          'clear_count': 1,
          'recommended_stats': ['집중', '관찰'],
          'asset_path': 'assets/adventure/dungeon-moss-archive.webp',
          'reward': {'exp': 10, 'seeds': 4, 'item_code': 'moss_key'},
        },
      ],
    });

    expect(state.patrol?.returnsAt?.isUtc, isTrue);
    expect(state.dungeons.single.discovered, isTrue);
    expect(state.dungeons.single.reward.exp, 10);
  });
}
