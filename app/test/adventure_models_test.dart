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
      'weekly_board': {
        'week_start': '2026-08-03',
        'week_end': '2026-08-09',
        'goals': [
          {
            'code': 'diary_3',
            'name': '마음 일기 3일',
            'description': '서로 다른 3일에 마음을 기록해요.',
            'progress': 3,
            'target': 3,
            'reward_exp': 0,
            'reward_seeds': 20,
            'completed': true,
            'claimed': false,
            'can_claim': true,
          },
          {
            'code': 'patrol_3',
            'name': '순찰 귀환 3회',
            'progress': 1,
            'target': 3,
            'reward_exp': 0,
            'reward_seeds': 8,
            'completed': false,
            'claimed': false,
            'can_claim': false,
          },
        ],
      },
      'milestones': {
        'current_title': '마음 기록가',
        'unlocked_count': 1,
        'total_count': 5,
        'items': [
          {
            'code': 'seven_day_diary',
            'name': '일곱 날의 마음',
            'description': '50자 이상 마음 일기를 서로 다른 7일에 남겨요.',
            'progress': 7,
            'target': 7,
            'unlocked': true,
            'title': '마음 기록가',
          },
          {
            'code': 'five_patrol_returns',
            'name': '익숙해진 산책길',
            'description': '캐릭터의 순찰 귀환을 5번 맞이해요.',
            'progress': 3,
            'target': 5,
            'unlocked': false,
            'title': '정원 길잡이',
          },
        ],
      },
      'donation': {
        'available_today': true,
        'used_today': false,
        'has_eligible_item': true,
        'required_quantity': 3,
        'reward_exp': 0,
        'reward_seeds': 2,
        'message': '연구에 필요한 수량을 남기고 여분 표본만 기증할 수 있어요.',
      },
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
          'base_duration_minutes': 15,
          'time_reduction_minutes': 5,
          'required_stage': 2,
          'available': true,
          'recommended_stats': ['돌봄', '관찰'],
          'performance_score': 18,
          'projected_quantity': 3,
          'best_match': true,
          'reward': {'exp': 0, 'seeds': 3, 'item_code': 'leaf_map'},
        },
      ],
      'patrol': null,
      'dungeon_run_available': true,
      'dungeons': [],
      'inventory': [
        {
          'code': 'pressed_leaf_map',
          'name': '눌러 말린 잎 지도',
          'description': '다음 길을 찾을 때 쓰는 지도 조각',
          'quantity': 6,
          'reserved_quantity': 3,
          'donatable_quantity': 3,
          'can_donate': true,
        },
      ],
      'research_summary': {
        'completed_count': 1,
        'total_count': 5,
        'chapter_completed': false,
        'chapter_name': '온실 밖 탐험 1장',
      },
      'research_projects': [
        {
          'code': 'pressed_leaf_atlas',
          'name': '압화 길잡이 도감',
          'description': '작은 흔적을 찾아요.',
          'completed': false,
          'can_complete': true,
          'requirements': [
            {
              'code': 'pressed_leaf_map',
              'name': '눌러 말린 잎 지도',
              'current': 2,
              'required': 2,
            },
          ],
          'effect': {'label': '순찰 수집량 영구 +1'},
        },
      ],
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
    expect(state.weeklyBoard.weekStart, DateTime(2026, 8, 3));
    expect(state.weeklyBoard.weekEnd, DateTime(2026, 8, 9));
    expect(state.weeklyBoard.goals.first.isDiary, isTrue);
    expect(state.weeklyBoard.goals.first.progressRatio, 1);
    expect(state.weeklyBoard.goals.first.canClaim, isTrue);
    expect(state.weeklyBoard.goals.first.rewardExp, 0);
    expect(
      state.weeklyBoard.goals.first.rewardSeeds,
      greaterThan(state.weeklyBoard.goals.last.rewardSeeds),
    );
    expect(state.milestones.currentTitle, '마음 기록가');
    expect(state.milestones.unlockedCount, 1);
    expect(state.milestones.totalCount, 5);
    expect(state.milestones.items.first.unlocked, isTrue);
    expect(state.milestones.items.first.progressRatio, 1);
    expect(state.milestones.items.last.progressRatio, .6);
    expect(state.donation.availableToday, isTrue);
    expect(state.donation.rewardExp, 0);
    expect(state.donation.rewardSeeds, 2);
    expect(state.inventory.single.reservedQuantity, 3);
    expect(state.inventory.single.donatableQuantity, 3);
    expect(state.inventory.single.canDonate, isTrue);
    expect(state.character?.form, PlantGrowthForm.sunny);
    expect(state.character?.outfit?.layerKey, 'garden-daily');
    expect(state.character?.outfit?.bonusLabel, '순찰 돌봄 +2');
    expect(state.routes.single.available, isTrue);
    expect(state.routes.single.baseDurationMinutes, 15);
    expect(state.routes.single.timeReductionMinutes, 5);
    expect(state.routes.single.performanceScore, 18);
    expect(state.routes.single.projectedQuantity, 3);
    expect(state.routes.single.bestMatch, isTrue);
    expect(state.researchProjects.single.canComplete, isTrue);
    expect(state.researchProjects.single.requirements.single.fulfilled, isTrue);
    expect(state.researchProjects.single.effectLabel, '순찰 수집량 영구 +1');
    expect(state.researchSummary.completedCount, 1);
    expect(state.researchSummary.totalCount, 5);
    expect(state.researchSummary.progress, .2);
    expect(state.researchSummary.chapterCompleted, isFalse);
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
          'approaches': [
            {
              'code': 'focus',
              'name': '호흡을 고르고 집중하기',
              'description': '한 갈래의 기척을 따라가요.',
              'stat_code': 'focus',
              'stat_label': '집중',
              'stat_value': 6,
              'recommended': true,
              'performance_score': 10,
              'projected_quantity': 2,
              'projected_outcome': 'resonant',
            },
          ],
        },
      ],
      'journal': {
        'discovered_count': 1,
        'total_dungeons': 4,
        'total_clear_count': 2,
        'recent_entries': [
          {
            'kind': 'dungeon',
            'title': '뒤집힌 표본 서랍',
            'description':
                '젖은 라벨 사이에서 씨앗 기록이 섞여 있었어요. · 호흡을 고르고 집중하기 · 이끼 열쇠 2개',
            'occurred_at': '2026-08-03T12:03:00Z',
            'location_code': 'moss_archive',
            'item_code': 'moss_key',
            'item_name': '이끼 열쇠',
            'quantity': 2,
            'outcome_code': 'resonant',
          },
        ],
      },
      'story_collection': {
        'collected_count': 1,
        'total_count': 24,
        'completed': false,
        'chapters': [
          {
            'code': 'patrol_memories',
            'name': '순찰에서 주운 장면',
            'description': '온실 밖에서 발견한 이야기',
            'collected_count': 1,
            'total_count': 12,
            'items': [
              {
                'kind': 'patrol',
                'code': 'first_birdsong',
                'location_code': 'dawn_canopy_walk',
                'location_name': '새벽 수관 회랑',
                'discovered': true,
                'title': '첫 새소리의 자리',
                'text': '수관 사이 쉼터를 찾았어요.',
                'detail': '모아 “같이 기억하자.”',
                'discovered_at': '2026-08-03T12:01:00Z',
              },
              {
                'kind': 'patrol',
                'code': 'feather_marker',
                'location_code': 'dawn_canopy_walk',
                'location_name': '새벽 수관 회랑',
                'discovered': false,
                'title': null,
                'text': null,
                'detail': null,
                'discovered_at': null,
              },
            ],
          },
        ],
      },
    });

    expect(state.patrol?.returnsAt?.isUtc, isTrue);
    expect(state.dungeons.single.discovered, isTrue);
    expect(state.dungeons.single.reward.exp, 10);
    expect(state.dungeons.single.approaches.single.resonant, isTrue);
    expect(state.dungeons.single.approaches.single.projectedQuantity, 2);
    expect(state.journal.discoveredCount, 1);
    expect(state.journal.totalDungeons, 4);
    expect(state.journal.totalClearCount, 2);
    expect(state.journal.recentEntries.single.isDungeon, isTrue);
    expect(state.journal.recentEntries.single.resonant, isTrue);
    expect(state.journal.recentEntries.single.occurredAt?.isUtc, isTrue);
    expect(state.storyCollection.collectedCount, 1);
    expect(state.storyCollection.totalCount, 24);
    expect(state.storyCollection.progress, closeTo(1 / 24, .0001));
    expect(
        state.storyCollection.chapters.single.items.first.discovered, isTrue);
    expect(
      state.storyCollection.chapters.single.items.first.discoveredAt?.isUtc,
      isTrue,
    );
    expect(state.storyCollection.chapters.single.items.last.title, isNull);

    final result = AdventureActionResult.fromJson({
      'state': const <String, dynamic>{},
      'run': {
        'outcome_message': '뒤집힌 표본 서랍: 씨앗 기록이 섞여 있었어요.\n'
            '집중 성장이 길과 맞았어요.',
      },
    });
    expect(
      result.outcomeMessage,
      '뒤집힌 표본 서랍: 씨앗 기록이 섞여 있었어요.\n집중 성장이 길과 맞았어요.',
    );

    final patrolResult = AdventureActionResult.fromJson({
      'state': const <String, dynamic>{},
      'outcome_message': '달빛 발자국: 밤꽃 사이의 안전한 길을 찾았어요.\n'
          '초록이: “천천히 걸으니 작은 소리까지 들렸어.”',
    });
    expect(
      patrolResult.outcomeMessage,
      '달빛 발자국: 밤꽃 사이의 안전한 길을 찾았어요.\n'
      '초록이: “천천히 걸으니 작은 소리까지 들렸어.”',
    );
  });
}
