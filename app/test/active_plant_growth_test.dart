import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/home/domain/plant.dart';

Map<String, dynamic> _plantJson({
  int stage = 3,
  String? growthForm = 'sunny',
  Map<String, dynamic>? profile,
}) =>
    {
      'id': 7,
      'name': '새봄이',
      'species': {'id': 1, 'code': 'mood_seed', 'name': '마음씨앗'},
      'exp': switch (stage) {
        1 => 0,
        2 => 30,
        3 => 130,
        4 => 300,
        _ => 450,
      },
      'stage': stage,
      'stage_thresholds': [0, 20, 100, 250, 450],
      'next_stage_exp': switch (stage) {
        1 => 20,
        2 => 100,
        3 => 250,
        4 => 450,
        _ => null,
      },
      'harvestable': false,
      'planted_at': '2026-07-01T00:00:00Z',
      if (growthForm != null) 'growth_form': growthForm,
      'emotion_profile': profile ??
          {
            'version': 2,
            'source': 'diary_text_analysis',
            'total': 4,
            'pending_count': 0,
            'unavailable_count': 0,
            'empty_count': 0,
            'counts': {
              'joy': 3,
              'sadness': 1,
              'anger': 0,
              'anxiety': 0,
              'surprise': 0,
              'mixed': 0,
            },
            'ratios': {'joy': .75, 'sadness': .25},
          },
    };

void main() {
  test('활성 식물의 최종 growth 계약을 모두 읽는다', () {
    final json = _plantJson(stage: 4, growthForm: 'moonlit')
      ..addAll({
        'growth_branch': 'anxiety',
        'growth_persona': {
          'persona_key': 'moonlit_careful',
          'persona_name': '달빛결',
          'trait': '꼼꼼히 살피고 차분하게 준비',
          'voice_line': '달이 기울 때까지 주변을 한 번 더 살펴볼게.',
        },
        'branch_status': 'stable',
        'branch_phase': 'branched',
        'growth_phase': 'bloom',
        'profile_state': 'ready',
        'branch_confidence': .82,
        'visual_key': 'stage_4_moonlit',
        'growth_visual': {
          'seed_shape': 'crystal_seed',
          'vessel_style': 'crystal_growth_tube',
          'rarity_effect': 'prismatic',
          'asset_namespace': 'plants/moonlit_deluxe',
          'rarity': 4,
          'phase': 'bloom',
          'seed_asset_key': 'plants/moonlit_deluxe/seeds/crystal_seed',
          'vessel_asset_key':
              'plants/moonlit_deluxe/vessels/crystal_growth_tube',
          'base_asset_key': 'plants/moonlit_deluxe/stages/bloom',
          'render_layers': [
            'plants/moonlit_deluxe/vessels/crystal_growth_tube',
            'plants/moonlit_deluxe/stages/bloom',
          ],
          'render_key':
              'plants/moonlit_deluxe/vessels/crystal_growth_tube|plants/moonlit_deluxe/stages/bloom',
        },
      });

    final plant = ActivePlant.fromJson(json);

    expect(plant.growthForm, PlantGrowthForm.moonlit);
    expect(plant.visualForm, PlantGrowthForm.moonlit);
    expect(plant.personality?.code, 'moonlit_careful');
    expect(plant.personalityName, '달빛결');
    expect(plant.personalityDescription, contains('꼼꼼히'));
    expect(plant.voiceLine, contains('달이 기울'));
    expect(plant.branchStatus, PlantBranchStatus.stable);
    expect(plant.branchPhase, PlantBranchPhase.branched);
    expect(plant.growthPhase, PlantGrowthPhase.bloom);
    expect(plant.profileState, PlantProfileState.ready);
    expect(plant.branchConfidence, .82);
    expect(plant.visualKey, 'stage_4_moonlit');
    expect(plant.growthVisual?.seedShape, 'crystal_seed');
    expect(plant.growthVisual?.vesselStyle, 'crystal_growth_tube');
    expect(plant.growthVisual?.assetNamespace, 'plants/moonlit_deluxe');
    expect(plant.growthVisual?.phase, 'bloom');
    expect(
      plant.growthVisual?.renderLayers,
      hasLength(2),
    );
    expect(
      plant.growthVisual?.renderKey,
      contains('stages/bloom'),
    );
    expect(plant.emotionProfile.source, 'diary_text_analysis');
  });

  test('1단계는 서버가 form을 보내도 공통 씨앗으로 보여 준다', () {
    final plant = ActivePlant.fromJson(_plantJson(stage: 1));

    expect(plant.growthForm, isNull);
    expect(plant.visualForm, isNull);
    expect(plant.personalityName, '아직 관찰 중');
  });

  test('2단계는 profile을 시각 단서로만 쓰고 감정·성격을 단정하지 않는다', () {
    final plant = ActivePlant.fromJson(_plantJson(
      stage: 2,
      growthForm: null,
      profile: {
        'total': 2,
        'counts': {'anger': 2},
        'ratios': {'anger': 1},
      },
    ));

    expect(plant.growthForm, isNull);
    expect(plant.visualForm, PlantGrowthForm.ember);
    expect(plant.personalityName, '아직 관찰 중');
    expect(plant.growthSummary, isNot(contains('화남')));
    expect(plant.voiceLine, isNot(PlantGrowthForm.ember.voiceLine(3)));
  });

  test('v3 다중 감정 점수는 대표 라벨 개수보다 시각 단서에 우선한다', () {
    final plant = ActivePlant.fromJson(_plantJson(
      stage: 2,
      growthForm: null,
      profile: {
        'version': 3,
        'total': 3,
        'counts': {'anger': 3},
        'ratios': {'anger': 1},
        'weights': {'anger': 1.2, 'joy': 1.05, 'sadness': .75},
        'weighted_ratios': {'anger': .4, 'joy': .35, 'sadness': .25},
      },
    ));

    expect(plant.emotionProfile.version, 3);
    expect(plant.emotionProfile.leadingCue, PlantGrowthForm.ember);
    expect(plant.emotionProfile.ratioFor(PlantGrowthForm.ember), .4);
    expect(
      plant.emotionProfile.topCues().map((cue) => cue.form),
      [
        PlantGrowthForm.ember,
        PlantGrowthForm.sunny,
        PlantGrowthForm.rainy,
      ],
    );
  });

  test('비율만 내려오는 감정 프로필도 성장 단서로 인정한다', () {
    final profile = ActivePlantEmotionProfile.fromJson({
      'version': 3,
      'weighted_ratios': {'sadness': .62, 'surprise': .38},
    });

    expect(profile.hasData, isTrue);
    expect(profile.leadingCue, PlantGrowthForm.rainy);
    expect(profile.ratioFor(PlantGrowthForm.sparkling), .38);
  });

  test('주결·보조결·식물 기질과 보조 렌더 레이어를 하위호환 파싱한다', () {
    final json = _plantJson(stage: 4, growthForm: 'sunny')
      ..addAll({
        'dominant_form': 'rainy',
        'growth_traits': {
          'version': 1,
          'stage': 4,
          'reveal_state': 'secondary_revealed',
          'title': '별빛 품은 빗물결',
          'traits': ['물방울을 오래 바라보는 결', '뜻밖의 반짝임을 좇는 결'],
          'secondary': {'form': 'sparkling'},
          'temperament': {
            'revealed': true,
            'fictional_character_axes': true,
            'affects_rewards': false,
            'axes': {'energy': .42, 'curiosity': .73},
            'labels': {'energy': '잔잔한', 'curiosity': '호기심 많은'},
            'summary': '잔잔한 움직임 · 호기심 많은 시선',
          },
          'chat_style': {
            'cadence': '짧게 숨을 고르며 말한다',
            'focus': '놓친 장면을 함께 바라본다',
            'question_style': '한 번에 하나씩 묻는다',
            'secondary_modifier': '뜻밖의 관점을 가볍게 더한다',
            'stage_expression': '보조결이 자연스럽게 섞인다',
          },
        },
        'growth_visual': {
          'seed_shape': 'heart_speck_seed',
          'vessel_style': 'round_terracotta_pot',
          'rarity_effect': 'none',
          'asset_namespace': 'plants/mood_seed',
          'secondary_asset_key': 'plants/mood_seed/accents/sparkling/bloom',
        },
      });

    final plant = ActivePlant.fromJson(json);

    expect(plant.dominantForm, PlantGrowthForm.rainy);
    expect(plant.growthForm, PlantGrowthForm.rainy);
    expect(plant.secondaryForm, PlantGrowthForm.sparkling);
    expect(plant.growthTraits.revealState, 'secondary_revealed');
    expect(plant.growthTraits.title, '별빛 품은 빗물결');
    expect(plant.growthTraits.traits, hasLength(2));
    expect(plant.growthTraits.temperament.revealed, isTrue);
    expect(plant.growthTraits.temperament.fictionalCharacterAxes, isTrue);
    expect(plant.growthTraits.temperament.axes['curiosity'], .73);
    expect(plant.temperamentSummary, contains('호기심 많은'));
    expect(plant.personalityName, '별빛 품은 빗물결');
    expect(plant.conversationProfile.questionStyle, '한 번에 하나씩 묻는다');
    expect(plant.conversationProfile.secondaryModifier, contains('뜻밖의 관점'));
    expect(
      plant.growthVisual?.secondaryAssetKey,
      'plants/mood_seed/accents/sparkling/bloom',
    );
  });

  test('보조결은 서버가 일찍 보내도 4단계 전에는 공개하지 않는다', () {
    final json = _plantJson(stage: 3, growthForm: 'rainy')
      ..['secondary_form'] = 'sparkling';

    expect(ActivePlant.fromJson(json).secondaryForm, isNull);
  });

  test('growth_profile 별칭과 분석 대기·제외 건수를 안전하게 읽는다', () {
    final json = _plantJson(stage: 5, growthForm: 'rainy')
      ..remove('emotion_profile')
      ..['growth_profile'] = {
        'version': 2,
        'source': 'diary_text_analysis',
        'total': 2,
        'pending_count': 1,
        'unavailable_count': 2,
        'empty_count': 3,
        'counts': {'sadness': 2},
      };
    final plant = ActivePlant.fromJson(json);

    expect(plant.emotionProfile.pendingCount, 1);
    expect(plant.emotionProfile.unavailableCount, 2);
    expect(plant.emotionProfile.emptyCount, 3);
    expect(plant.analysisNotice, '일기 1편의 마음을 읽는 중이에요.');
  });

  test('여섯 분기는 동등하고 서로 다른 성격·말투를 갖는다', () {
    expect(
      PlantGrowthForm.values.map((form) => form.personalityName).toSet(),
      hasLength(6),
    );
    expect(
      PlantGrowthForm.values.map((form) => form.personalityDescription).toSet(),
      hasLength(6),
    );
    expect(
      PlantGrowthForm.values.map((form) => form.voiceLine(3)).toSet(),
      hasLength(6),
    );
  });

  test('품종 잠금과 렌더링 메타데이터를 식물 심기 화면까지 보존한다', () {
    final species = PlantSpecies.fromJson({
      'id': 2,
      'code': 'cactus',
      'name': '가시니',
      'rarity': 2,
      'unlock_price': 100,
      'is_unlocked': false,
      'asset_manifest': {'asset_key': 'species/cactus'},
    });

    expect(species.isUnlocked, isFalse);
    expect(species.unlockPrice, 100);
    expect(species.assetManifest['asset_key'], 'species/cactus');
  });

  test('품종 manifest growth를 시각 계약 fallback으로 읽는다', () {
    final json = _plantJson(stage: 1)
      ..['species'] = {
        'id': 2,
        'code': 'cactus',
        'name': '가시니',
        'rarity': 2,
        'asset_manifest': {
          'growth': {
            'seed_shape': 'spined_star_seed',
            'vessel_style': 'ribbed_desert_incubator',
            'rarity_effect': 'warm_dust_glint',
            'asset_namespace': 'plants/cactus',
          },
        },
      };

    final plant = ActivePlant.fromJson(json);

    expect(plant.growthVisual?.seedShape, 'spined_star_seed');
    expect(plant.growthVisual?.seedLabel, '가시별 씨앗');
    expect(plant.growthVisual?.vesselStyle, 'ribbed_desert_incubator');
    expect(plant.growthVisual?.vesselLabel, '사막결 육묘분');
    expect(plant.growthVisual?.assetNamespace, 'plants/cactus');
    expect(plant.growthVisual?.rarity, 2);
  });

  test('이전 응답도 품종별 canonical 시각 기본값으로 보완한다', () {
    final basic = ActivePlant.fromJson(_plantJson(stage: 1));
    final sunflowerJson = _plantJson(stage: 1)
      ..['species'] = {
        'id': 3,
        'code': 'sunflower',
        'name': '해바라기',
        'rarity': 2,
      };
    final sunflower = ActivePlant.fromJson(sunflowerJson);

    expect(basic.growthVisual?.seedShape, 'heart_speck_seed');
    expect(basic.growthVisual?.vesselStyle, 'round_terracotta_pot');
    expect(basic.growthVisual?.assetNamespace, 'plants/mood_seed');
    expect(sunflower.growthVisual?.seedShape, 'striped_sun_seed');
    expect(sunflower.growthVisual?.seedLabel, '해무늬 씨앗');
    expect(sunflower.growthVisual?.vesselStyle, 'sunbeam_bell_jar');
    expect(sunflower.growthVisual?.rarityEffect, 'soft_sun_motes');
    expect(sunflower.growthVisual?.assetNamespace, 'plants/sunflower');
  });

  test('알 수 없는 일반 품종은 서버와 같은 generic 시각 계약으로 보완한다', () {
    final visual = PlantGrowthVisual.fallback(speciesCode: 'future_species');

    expect(visual.seedShape, 'round_seed');
    expect(visual.vesselStyle, 'soft_terracotta_pot');
    expect(visual.assetNamespace, 'plants/generic');
  });

  test('현재 단계는 숫자 XP와 함께 다음 성장 장면을 안내한다', () {
    final sprout = ActivePlant.fromJson(_plantJson(stage: 2));
    final bloom = ActivePlant.fromJson(_plantJson(stage: 4));

    expect(sprout.nextMilestoneLabel, contains('외형과 성격'));
    expect(bloom.nextMilestoneLabel, contains('박물관'));
  });
}
