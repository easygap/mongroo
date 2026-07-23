import '../../home/domain/plant.dart';

/// 박물관에서 사용하는 최종 식물 형태.
///
/// 어느 감정도 상·하위로 취급하지 않는다. [mosaic]는 데이터가 없거나 여러
/// 감정이 비슷하게 쌓인 경우의 자연스러운 혼합 형태다.
enum PlantFinalForm {
  sunny(
    code: 'sunny',
    label: '햇살꽃',
    emotionLabel: '기쁨',
    description: '수확일 관찰: 꽃잎이 해를 향해 넓게 벌어졌고 노란 잎맥이 또렷하다.',
  ),
  rainy(
    code: 'rainy',
    label: '빗방울꽃',
    emotionLabel: '슬픔',
    description: '푸른 잎 끝에 물방울이 오래 머문다. 비가 그치면 줄기가 다시 곧게 선다.',
  ),
  ember(
    code: 'ember',
    label: '불씨꽃',
    emotionLabel: '화남',
    description: '붉은 꽃받침이 단단히 겹쳐 있고, 잎 가장자리에는 불씨 같은 주황 무늬가 남았다.',
  ),
  moonlit(
    code: 'moonlit',
    label: '달그늘꽃',
    emotionLabel: '불안',
    description: '밤에 잎이 반쯤 접히며 은빛 반점이 드러난다. 바람이 닿으면 가늘게 떨린다.',
  ),
  sparkling(
    code: 'sparkling',
    label: '반짝꽃',
    emotionLabel: '놀람',
    description: '새순마다 크기가 다른 꽃망울이 돋았다. 방향을 바꿀 때마다 표면 색이 번쩍인다.',
  ),
  mosaic(
    code: 'mosaic',
    label: '마음모아꽃',
    emotionLabel: '여러 마음',
    description: '한 줄기에서 서로 다른 색과 모양의 잎이 자랐다. 어느 쪽도 다른 잎을 가리지 않는다.',
  );

  const PlantFinalForm({
    required this.code,
    required this.label,
    required this.emotionLabel,
    required this.description,
  });

  final String code;
  final String label;
  final String emotionLabel;
  final String description;

  static PlantFinalForm fromCode(Object? value) {
    final code = value?.toString().trim().toLowerCase() ?? '';
    return switch (code) {
      'sunny' || 'joy' || 'happy' || 'happiness' => sunny,
      'rainy' || 'sad' || 'sadness' || 'hurt' => rainy,
      'ember' || 'anger' || 'angry' => ember,
      'moonlit' || 'anxiety' || 'anxious' || 'fear' => moonlit,
      'sparkling' || 'surprise' || 'surprised' => sparkling,
      _ => mosaic,
    };
  }
}

enum PlantEmotion {
  joy(code: 'joy', label: '기쁨'),
  sadness(code: 'sadness', label: '슬픔'),
  anger(code: 'anger', label: '화남'),
  anxiety(code: 'anxiety', label: '불안'),
  surprise(code: 'surprise', label: '놀람'),
  mixed(code: 'mixed', label: '여러 마음');

  const PlantEmotion({required this.code, required this.label});

  final String code;
  final String label;
}

class PlantEmotionProfile {
  const PlantEmotionProfile({
    this.version = 1,
    this.total = 0,
    this.counts = const {},
    this.ratios = const {},
  });

  final int version;
  final int total;
  final Map<String, int> counts;
  final Map<String, double> ratios;

  bool get hasData =>
      total > 0 ||
      counts.values.any((value) => value > 0) ||
      ratios.values.any((value) => value > 0);

  double ratioFor(PlantEmotion emotion) {
    final explicit = ratios[emotion.code];
    if (explicit != null) return explicit.clamp(0, 1).toDouble();
    if (total <= 0) return 0;
    return ((counts[emotion.code] ?? 0) / total).clamp(0, 1).toDouble();
  }

  factory PlantEmotionProfile.fromJson(Object? value) {
    final json = _map(value);
    final countsJson = _map(json['counts']);
    final weightedRatiosJson = _map(json['weighted_ratios']);
    final ratiosJson = weightedRatiosJson.isNotEmpty
        ? weightedRatiosJson
        : _map(json['ratios']);
    return PlantEmotionProfile(
      version: _integer(json['version'], fallback: 1),
      total: _integer(json['total']),
      counts: {
        for (final emotion in PlantEmotion.values)
          emotion.code: _integer(countsJson[emotion.code]),
      },
      ratios: {
        for (final emotion in PlantEmotion.values)
          if (_number(ratiosJson[emotion.code]) != null)
            emotion.code: _number(ratiosJson[emotion.code])!,
      },
    );
  }
}

/// 감정 기록을 다 키운 뒤 박물관에 보관된 식물 스냅샷.
class HarvestedPlant {
  const HarvestedPlant({
    required this.id,
    required this.name,
    required this.species,
    required this.exp,
    required this.plantedAt,
    required this.harvestedAt,
    this.finalForm = PlantFinalForm.mosaic,
    this.emotionProfile = const PlantEmotionProfile(),
    this.museumFeatured = false,
    this.personality,
    this.secondaryForm,
    this.growthTraits = const PlantGrowthTraits(),
    this.conversationProfile = const PlantConversationProfile(),
    this.growthVisual,
  });

  final int id;
  final String name;
  final PlantSpecies species;
  final int exp;
  final DateTime? plantedAt;
  final DateTime? harvestedAt;
  final PlantFinalForm finalForm;
  final PlantEmotionProfile emotionProfile;
  final bool museumFeatured;
  final PlantPersonality? personality;
  final PlantGrowthForm? secondaryForm;
  final PlantGrowthTraits growthTraits;
  final PlantConversationProfile conversationProfile;
  final PlantGrowthVisual? growthVisual;

  PlantGrowthForm get growthForm =>
      PlantGrowthForm.fromCode(finalForm.code) ?? PlantGrowthForm.mosaic;

  PlantGrowthForm get dominantForm => growthForm;

  String get personalityName {
    final growthTitle = growthTraits.title.trim();
    if (growthTitle.isNotEmpty) return growthTitle;
    final serverName = personality?.name.trim() ?? '';
    return serverName.isEmpty ? growthForm.personalityName : serverName;
  }

  String get personalityDescription {
    final serverTrait = personality?.trait.trim() ?? '';
    if (serverTrait.isNotEmpty) return serverTrait;
    if (growthTraits.traits.isNotEmpty) {
      return growthTraits.traits.join(' · ');
    }
    return growthForm.personalityDescription;
  }

  String get temperamentSummary => growthTraits.temperament.hasDetails
      ? growthTraits.temperament.summary
      : '';

  String get voiceLine {
    final serverLine = personality?.voiceLine.trim() ?? '';
    return serverLine.isEmpty ? growthForm.voiceLine(5) : serverLine;
  }

  HarvestedPlant copyWith({bool? museumFeatured}) => HarvestedPlant(
        id: id,
        name: name,
        species: species,
        exp: exp,
        plantedAt: plantedAt,
        harvestedAt: harvestedAt,
        finalForm: finalForm,
        emotionProfile: emotionProfile,
        museumFeatured: museumFeatured ?? this.museumFeatured,
        personality: personality,
        secondaryForm: secondaryForm,
        growthTraits: growthTraits,
        conversationProfile: conversationProfile,
        growthVisual: growthVisual,
      );

  factory HarvestedPlant.fromJson(Map<String, dynamic> json) {
    final species = _map(json['species']);
    final parsedSpecies =
        PlantSpecies.fromJson(species.isEmpty ? const {'id': 0} : species);
    final growth = _map(json['growth']);
    final growthTraitsJson =
        json['growth_traits'] ?? growth['growth_traits'] ?? growth['traits'];
    final growthTraitsMap = _map(growthTraitsJson);
    final personalityJson = json['growth_persona'] ??
        json['personality'] ??
        growth['persona'] ??
        growth['personality'];
    final personalityMap = _map(personalityJson);
    final growthTraits = PlantGrowthTraits.fromJson(
      growthTraitsJson,
      temperamentFallback: json['temperament'] ?? personalityMap['temperament'],
      titleFallback: (personalityMap['title'] ??
                  personalityMap['persona_name'] ??
                  personalityMap['name'])
              ?.toString() ??
          '',
    );
    final directConversationProfile = PlantConversationProfile.fromJson(
      json['conversation_profile'] ??
          growth['conversation_profile'] ??
          personalityMap['chat_style'],
    );
    return HarvestedPlant(
      id: _integer(json['id']),
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : '이름 없는 식물',
      species: parsedSpecies,
      exp: _integer(json['exp']),
      plantedAt: _date(json['planted_at']),
      harvestedAt: _date(json['harvested_at']),
      finalForm: PlantFinalForm.fromCode(
        json['final_form'] ??
            json['dominant_form'] ??
            growth['dominant_form'] ??
            json['growth_form'] ??
            json['final_emotion'] ??
            json['dominant_emotion'],
      ),
      emotionProfile: PlantEmotionProfile.fromJson(json['emotion_profile']),
      museumFeatured: (json['museum_featured'] as bool?) ??
          (json['is_featured'] as bool?) ??
          false,
      personality: _personality(personalityJson),
      secondaryForm: PlantGrowthForm.fromCode(
        json['secondary_form'] ??
            growth['secondary_form'] ??
            _map(growthTraitsMap['secondary'])['form'] ??
            json['secondary_emotion'],
      ),
      growthTraits: growthTraits,
      conversationProfile: directConversationProfile.hasDetails
          ? directConversationProfile
          : growthTraits.chatStyle,
      growthVisual: PlantGrowthVisual.fromSources(
        active: json['growth_visual'] ?? growth['visual'],
        species: parsedSpecies,
      ),
    );
  }
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const <String, dynamic>{};

int _integer(Object? value, {int fallback = 0}) => switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text) ?? fallback,
      _ => fallback,
    };

double? _number(Object? value) => switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text),
      _ => null,
    };

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

PlantPersonality? _personality(Object? value) {
  final personality = PlantPersonality.fromJson(value);
  return personality.code.isEmpty && personality.name.isEmpty
      ? null
      : personality;
}
