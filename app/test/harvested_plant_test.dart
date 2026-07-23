import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/gallery/domain/harvested_plant.dart';
import 'package:mongroo/features/home/domain/plant.dart';

void main() {
  test('박물관 응답의 최종 형태·감정 분포·대표 전시 상태를 읽는다', () {
    final plant = HarvestedPlant.fromJson({
      'id': 14,
      'name': '해님이',
      'species': {'id': 1, 'code': 'sunflower', 'name': '해바라기'},
      'exp': 1200,
      'planted_at': '2026-06-01T00:00:00Z',
      'harvested_at': '2026-07-12T03:00:00Z',
      'final_form': 'sunny',
      'museum_featured': true,
      'growth_persona': {
        'persona_key': 'sunny_share',
        'persona_name': '햇살결',
      },
      'emotion_profile': {
        'version': 1,
        'total': 5,
        'counts': {
          'joy': 4,
          'sadness': 1,
          'anger': 0,
          'anxiety': 0,
          'surprise': 0,
          'mixed': 0,
        },
        'ratios': {
          'joy': .8,
          'sadness': .2,
          'anger': 0,
          'anxiety': 0,
          'surprise': 0,
          'mixed': 0,
        },
      },
    });

    expect(plant.finalForm, PlantFinalForm.sunny);
    expect(plant.museumFeatured, isTrue);
    expect(plant.personalityName, '햇살결');
    expect(plant.emotionProfile.total, 5);
    expect(plant.emotionProfile.counts['joy'], 4);
    expect(plant.emotionProfile.ratioFor(PlantEmotion.joy), .8);
    expect(plant.harvestedAt, isNotNull);
  });

  test('이전 서버 응답은 혼합 형태와 빈 프로필로 안전하게 보완한다', () {
    final plant = HarvestedPlant.fromJson({
      'id': 7,
      'name': '',
      'species': {'id': 2},
      'exp': 1000,
    });

    expect(plant.name, '이름 없는 식물');
    expect(plant.finalForm, PlantFinalForm.mosaic);
    expect(plant.museumFeatured, isFalse);
    expect(plant.emotionProfile.hasData, isFalse);
    expect(plant.emotionProfile.ratioFor(PlantEmotion.joy), 0);
  });

  test('박물관 감정 비율은 성장 판정에 쓴 가중치 비율을 우선한다', () {
    final profile = PlantEmotionProfile.fromJson({
      'version': 3,
      'total': 5,
      'counts': {'joy': 4, 'sadness': 1},
      'ratios': {'joy': .8, 'sadness': .2},
      'weighted_ratios': {'joy': .35, 'sadness': .65},
    });

    expect(profile.ratioFor(PlantEmotion.joy), .35);
    expect(profile.ratioFor(PlantEmotion.sadness), .65);
  });

  test('비율 스냅샷만 남은 표본도 세부 감정 기록이 있는 것으로 본다', () {
    final profile = PlantEmotionProfile.fromJson({
      'version': 3,
      'weighted_ratios': {'joy': .4, 'sadness': .6},
    });

    expect(profile.hasData, isTrue);
    expect(profile.ratioFor(PlantEmotion.sadness), .6);
  });

  test('박물관 표본은 주결·보조결·기질과 보조 렌더 레이어를 보존한다', () {
    final plant = HarvestedPlant.fromJson({
      'id': 23,
      'name': '빗별이',
      'species': {'id': 1, 'code': 'mood_seed', 'name': '마음씨앗'},
      'exp': 900,
      'dominant_form': 'rainy',
      'secondary_form': 'sunny',
      'growth_traits': {
        'stage': 5,
        'reveal_state': 'signature_complete',
        'title': '햇살 한 줌 품은 빗물결',
        'traits': ['오래 귀 기울이는 결', '빛을 나누는 결'],
        'temperament': {
          'revealed': true,
          'fictional_character_axes': true,
          'axes': {'sensitivity': .78},
          'labels': {'sensitivity': '섬세한'},
          'summary': '섬세한 반응 · 천천히 고르는 말',
        },
        'chat_style': {
          'cadence': '천천히 말한다',
          'question_style': '감정을 재촉하지 않는다',
        },
      },
      'growth_visual': {
        'seed_shape': 'heart_speck_seed',
        'vessel_style': 'round_terracotta_pot',
        'rarity_effect': 'none',
        'asset_namespace': 'plants/mood_seed',
        'secondary_asset_key': 'plants/mood_seed/accents/sunny/full_bloom',
      },
    });

    expect(plant.finalForm, PlantFinalForm.rainy);
    expect(plant.dominantForm, PlantGrowthForm.rainy);
    expect(plant.secondaryForm, PlantGrowthForm.sunny);
    expect(plant.growthTraits.revealState, 'signature_complete');
    expect(plant.personalityName, '햇살 한 줌 품은 빗물결');
    expect(plant.temperamentSummary, contains('섬세한 반응'));
    expect(plant.conversationProfile.cadence, '천천히 말한다');
    expect(
      plant.growthVisual?.secondaryAssetKey,
      'plants/mood_seed/accents/sunny/full_bloom',
    );
  });

  test('가중치 비율이 없는 기존 응답은 원본 비율을 유지한다', () {
    final profile = PlantEmotionProfile.fromJson({
      'version': 1,
      'total': 5,
      'counts': {'joy': 4, 'sadness': 1},
      'ratios': {'joy': .8, 'sadness': .2},
    });

    expect(profile.ratioFor(PlantEmotion.joy), .8);
    expect(profile.ratioFor(PlantEmotion.sadness), .2);
  });

  test('최종 감정 별칭도 대응하는 형태로 정규화한다', () {
    expect(PlantFinalForm.fromCode('joy'), PlantFinalForm.sunny);
    expect(PlantFinalForm.fromCode('sadness'), PlantFinalForm.rainy);
    expect(PlantFinalForm.fromCode('anger'), PlantFinalForm.ember);
    expect(PlantFinalForm.fromCode('anxiety'), PlantFinalForm.moonlit);
    expect(PlantFinalForm.fromCode('surprise'), PlantFinalForm.sparkling);
    expect(PlantFinalForm.fromCode('unknown'), PlantFinalForm.mosaic);
  });

  test('여섯 최종 형태는 서로 다른 관찰 기록으로 설명한다', () {
    final descriptions = {
      for (final form in PlantFinalForm.values) form: form.description,
    };

    expect(
        descriptions.values.toSet(), hasLength(PlantFinalForm.values.length));
    expect(
      descriptions[PlantFinalForm.sunny],
      '수확일 관찰: 꽃잎이 해를 향해 넓게 벌어졌고 노란 잎맥이 또렷하다.',
    );
    expect(
      descriptions[PlantFinalForm.rainy],
      '푸른 잎 끝에 물방울이 오래 머문다. 비가 그치면 줄기가 다시 곧게 선다.',
    );
    expect(
      descriptions[PlantFinalForm.ember],
      '붉은 꽃받침이 단단히 겹쳐 있고, 잎 가장자리에는 불씨 같은 주황 무늬가 남았다.',
    );
    expect(
      descriptions[PlantFinalForm.moonlit],
      '밤에 잎이 반쯤 접히며 은빛 반점이 드러난다. 바람이 닿으면 가늘게 떨린다.',
    );
    expect(
      descriptions[PlantFinalForm.sparkling],
      '새순마다 크기가 다른 꽃망울이 돋았다. 방향을 바꿀 때마다 표면 색이 번쩍인다.',
    );
    expect(
      descriptions[PlantFinalForm.mosaic],
      '한 줄기에서 서로 다른 색과 모양의 잎이 자랐다. 어느 쪽도 다른 잎을 가리지 않는다.',
    );
    for (final description in descriptions.values) {
      expect(description, isNot(endsWith('식물이에요.')));
    }
  });
}
