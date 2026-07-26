/// 서버 계산 stage: 1 씨앗, 2 새싹, 3 줄기, 4 개화, 5 만개.
const List<String> plantStageNames = ['씨앗', '새싹', '줄기', '개화', '만개'];

String plantStageName(int stage) {
  final index = stage.clamp(1, plantStageNames.length).toInt() - 1;
  return plantStageNames[index];
}

/// 일기 본문을 분석해 쌓인 감정이 만드는 성장 형태.
///
/// 형태 사이에 우열은 없다. 1단계에서는 노출하지 않고, 2단계에서는
/// 잎맥과 색의 미세한 단서로만 사용한다. 성격과 말투는 3단계부터
/// 보여 주어 일시적인 기분을 성격으로 낙인하지 않는다.
enum PlantGrowthForm {
  sunny(
    code: 'sunny',
    emotionCode: 'joy',
    label: '햇살꽃',
    emotionLabel: '기쁨',
    personalityName: '햇살결',
    personalityDescription: '따뜻한 기운을 주변과 자연스럽게 나눠요.',
  ),
  rainy(
    code: 'rainy',
    emotionCode: 'sadness',
    label: '빗방울꽃',
    emotionLabel: '슬픔',
    personalityName: '빗물결',
    personalityDescription: '작은 변화를 놓치지 않고 끝까지 들어줘요.',
  ),
  ember(
    code: 'ember',
    emotionCode: 'anger',
    label: '불씨꽃',
    emotionLabel: '화남',
    personalityName: '불씨결',
    personalityDescription: '중요한 마음을 숨기지 않고 밖으로 꺼내요.',
  ),
  moonlit(
    code: 'moonlit',
    emotionCode: 'anxiety',
    label: '달그늘꽃',
    emotionLabel: '불안',
    personalityName: '달빛결',
    personalityDescription: '주변을 살피고 하나씩 준비하며 앞으로 가요.',
  ),
  sparkling(
    code: 'sparkling',
    emotionCode: 'surprise',
    label: '반짝꽃',
    emotionLabel: '놀람',
    personalityName: '별빛결',
    personalityDescription: '예상 밖의 순간에서 새로운 것을 찾아요.',
  ),
  mosaic(
    code: 'mosaic',
    emotionCode: 'mixed',
    label: '마음모아꽃',
    emotionLabel: '여러 마음',
    personalityName: '모아결',
    personalityDescription: '서로 다른 마음을 한결같이 존중해요.',
  );

  const PlantGrowthForm({
    required this.code,
    required this.emotionCode,
    required this.label,
    required this.emotionLabel,
    required this.personalityName,
    required this.personalityDescription,
  });

  final String code;
  final String emotionCode;
  final String label;
  final String emotionLabel;
  final String personalityName;
  final String personalityDescription;

  static PlantGrowthForm? fromCode(Object? value) {
    final code = value?.toString().trim().toLowerCase() ?? '';
    return switch (code) {
      'sunny' || 'joy' || 'happy' || 'happiness' => sunny,
      'rainy' || 'sad' || 'sadness' || 'hurt' => rainy,
      'ember' || 'anger' || 'angry' => ember,
      'moonlit' || 'anxiety' || 'anxious' || 'fear' => moonlit,
      'sparkling' || 'surprise' || 'surprised' => sparkling,
      'mosaic' || 'mixed' => mosaic,
      _ => null,
    };
  }

  String voiceLine(int stage) => switch (stage.clamp(1, 5)) {
        1 => '아직은 작은 씨앗이야. 일기를 더 들려줘.',
        2 => '새잎에 첫 색이 비치고 있어. 아직 어떤 결인지는 더 지켜보자.',
        3 => switch (this) {
            sunny => '햇빛 자리 찾았어. 오늘 잎을 넓게 펼칠래.',
            rainy => '잎 끝의 물방울, 떨어질 때까지 지켜볼래.',
            ember => '내 불씨는 작아도 또렷해. 길을 밝힐 수 있어.',
            moonlit => '달이 기울 때까지 주변을 한 번 더 살펴볼게.',
            sparkling => '방금 반짝인 거 봤어? 저쪽도 확인하자!',
            mosaic => '오늘은 잎마다 다른 색이야. 어느 쪽도 숨기지 않을래.',
          },
        4 => switch (this) {
            sunny => '온실 가장 밝은 칸까지 꽃잎이 닿았어.',
            rainy => '물방울을 안은 잎이 낮은 가지까지 길게 내려왔어.',
            ember => '뚜렷한 가장자리에 불빛 무늬가 한 칸 더 자랐어.',
            moonlit => '달이 기우는 순서대로 잎이 천천히 펴지고 있어.',
            sparkling => '처음 보는 무늬가 또 생겼어! 살펴보자.',
            mosaic => '새로 난 잎마다 다른 색 자리를 찾았어.',
          },
        _ => switch (this) {
            sunny => '해가 뜨면 열 장의 꽃잎을 한꺼번에 펼칠게.',
            rainy => '비가 그친 뒤에도 잎 끝의 물방울은 천천히 흐를 거야.',
            ember => '화분 가장자리까지 불씨 무늬가 또렷하게 피었어.',
            moonlit => '달빛이 닿으면 접힌 잎 안쪽의 은빛이 보일 거야.',
            sparkling => '꽃망울마다 다른 반짝임이 숨어 있어. 하나씩 찾아보자!',
            mosaic => '다른 색의 잎들이 서로를 가리지 않고 한 그루로 피었어.',
          },
      };
}

enum PlantBranchStatus {
  observing,
  emerging,
  stable;

  static PlantBranchStatus fromCode(Object? value, {required int stage}) {
    return switch (value?.toString().trim().toLowerCase()) {
      'stable' => stable,
      'emerging' => emerging,
      'observing' => observing,
      _ when stage >= 3 => stable,
      _ when stage == 2 => emerging,
      _ => observing,
    };
  }
}

enum PlantBranchPhase {
  unformed,
  hinting,
  branched;

  static PlantBranchPhase fromCode(Object? value, {required int stage}) =>
      switch (value?.toString().trim().toLowerCase()) {
        'branched' => branched,
        'hinting' => hinting,
        'unformed' => unformed,
        _ when stage >= 3 => branched,
        _ when stage == 2 => hinting,
        _ => unformed,
      };
}

enum PlantGrowthPhase {
  seed,
  sprout,
  branching,
  bloom,
  fullBloom;

  static PlantGrowthPhase fromCode(Object? value, {required int stage}) =>
      switch (value?.toString().trim().toLowerCase()) {
        'full_bloom' => fullBloom,
        'bloom' => bloom,
        'branching' => branching,
        'sprout' => sprout,
        'seed' => seed,
        _ => values[stage.clamp(1, 5).toInt() - 1],
      };
}

enum PlantProfileState {
  analyzing,
  limited,
  ready;

  static PlantProfileState fromCode(Object? value) =>
      switch (value?.toString().trim().toLowerCase()) {
        'ready' => ready,
        'limited' => limited,
        _ => analyzing,
      };
}

class PlantPersonality {
  const PlantPersonality({
    required this.code,
    required this.name,
    this.trait = '',
    this.voiceLine = '',
  });

  final String code;
  final String name;
  final String trait;
  final String voiceLine;

  factory PlantPersonality.fromJson(Object? value) {
    final json = _plantMap(value);
    return PlantPersonality(
      code: (json['code'] ?? json['persona_code'] ?? json['persona_key'])
              ?.toString()
              .trim() ??
          '',
      name: (json['name'] ?? json['persona_name'])?.toString().trim() ?? '',
      trait: json['trait']?.toString().trim() ?? '',
      voiceLine: json['voice_line']?.toString().trim() ?? '',
    );
  }
}

/// 누적 감정 분포가 만드는 식물 캐릭터의 연출용 기질.
///
/// 사용자의 성격 검사 결과가 아니며, 서버가 [revealed]를 true로 보낸
/// 성장 단계에서만 축과 요약을 화면에 사용할 수 있다.
class PlantTemperament {
  const PlantTemperament({
    this.revealed = false,
    this.fictionalCharacterAxes = false,
    this.affectsRewards = false,
    this.axes = const {},
    this.labels = const {},
    this.summary = '',
  });

  final bool revealed;
  final bool fictionalCharacterAxes;
  final bool affectsRewards;
  final Map<String, double> axes;
  final Map<String, String> labels;
  final String summary;

  bool get hasDetails =>
      revealed && (summary.isNotEmpty || axes.isNotEmpty || labels.isNotEmpty);

  factory PlantTemperament.fromJson(Object? value) {
    final json = _plantMap(value);
    final axes = _plantMap(json['axes']);
    final labels = _plantMap(json['labels']);
    final summary = json['summary']?.toString().trim() ?? '';
    final parsedAxes = <String, double>{
      for (final entry in axes.entries)
        if (_plantDouble(entry.value) != null)
          entry.key: _plantDouble(entry.value)!,
    };
    final parsedLabels = <String, String>{
      for (final entry in labels.entries)
        if (entry.value.toString().trim().isNotEmpty)
          entry.key: entry.value.toString().trim(),
    };
    return PlantTemperament(
      revealed: json['revealed'] == true ||
          (json['revealed'] == null &&
              (summary.isNotEmpty ||
                  parsedAxes.isNotEmpty ||
                  parsedLabels.isNotEmpty)),
      fictionalCharacterAxes: json['fictional_character_axes'] == true,
      affectsRewards: json['affects_rewards'] == true,
      axes: parsedAxes,
      labels: parsedLabels,
      summary: summary,
    );
  }
}

/// 성장한 식물이 대화에서 유지할 말의 속도와 질문 방식.
class PlantConversationProfile {
  const PlantConversationProfile({
    this.cadence = '',
    this.focus = '',
    this.questionStyle = '',
    this.secondaryModifier = '',
    this.stageExpression = '',
  });

  final String cadence;
  final String focus;
  final String questionStyle;
  final String secondaryModifier;
  final String stageExpression;

  bool get hasDetails =>
      cadence.isNotEmpty ||
      focus.isNotEmpty ||
      questionStyle.isNotEmpty ||
      secondaryModifier.isNotEmpty ||
      stageExpression.isNotEmpty;

  factory PlantConversationProfile.fromJson(Object? value) {
    final json = _plantMap(value);
    return PlantConversationProfile(
      cadence: json['cadence']?.toString().trim() ?? '',
      focus: json['focus']?.toString().trim() ?? '',
      questionStyle: json['question_style']?.toString().trim() ?? '',
      secondaryModifier: json['secondary_modifier']?.toString().trim() ?? '',
      stageExpression: json['stage_expression']?.toString().trim() ?? '',
    );
  }
}

/// 성장 단계별로 공개되는 주결·보조결·기질의 설명 계약.
class PlantGrowthTraits {
  const PlantGrowthTraits({
    this.version = 1,
    this.source = '',
    this.stage = 0,
    this.revealState = '',
    this.nextReveal = '',
    this.evidenceCount = 0,
    this.title = '',
    this.traits = const [],
    this.temperament = const PlantTemperament(),
    this.chatStyle = const PlantConversationProfile(),
    this.fictionalCharacterProfile = false,
    this.userPersonalityInference = false,
    this.affectsGrowthSpeed = false,
  });

  final int version;
  final String source;
  final int stage;
  final String revealState;
  final String nextReveal;
  final int evidenceCount;
  final String title;
  final List<String> traits;
  final PlantTemperament temperament;
  final PlantConversationProfile chatStyle;
  final bool fictionalCharacterProfile;
  final bool userPersonalityInference;
  final bool affectsGrowthSpeed;

  bool get hasContent =>
      title.isNotEmpty ||
      traits.isNotEmpty ||
      revealState.isNotEmpty ||
      temperament.hasDetails ||
      chatStyle.hasDetails;

  factory PlantGrowthTraits.fromJson(
    Object? value, {
    Object? temperamentFallback,
    String titleFallback = '',
  }) {
    final json = _plantMap(value);
    final rawTraits = json['traits'];
    final traits = rawTraits is List
        ? rawTraits
            .map((item) {
              if (item is String) return item.trim();
              final mapped = _plantMap(item);
              return (mapped['title'] ?? mapped['label'] ?? mapped['name'])
                      ?.toString()
                      .trim() ??
                  '';
            })
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final title = json['title']?.toString().trim() ?? '';
    return PlantGrowthTraits(
      version: _plantInt(json['version'], fallback: 1),
      source: json['source']?.toString().trim() ?? '',
      stage: _plantInt(json['stage']),
      revealState: json['reveal_state']?.toString().trim() ?? '',
      nextReveal: json['next_reveal']?.toString().trim() ?? '',
      evidenceCount: _plantInt(json['evidence_count']),
      title: title.isEmpty ? titleFallback.trim() : title,
      traits: traits,
      temperament: PlantTemperament.fromJson(
        json['temperament'] ?? temperamentFallback,
      ),
      chatStyle: PlantConversationProfile.fromJson(json['chat_style']),
      fictionalCharacterProfile: json['fictional_character_profile'] == true,
      userPersonalityInference: json['user_personality_inference'] == true,
      affectsGrowthSpeed: json['affects_growth_speed'] == true,
    );
  }
}

class PlantEmotionCue {
  const PlantEmotionCue({required this.form, required this.ratio});

  final PlantGrowthForm form;
  final double ratio;
}

class ActivePlantEmotionProfile {
  const ActivePlantEmotionProfile({
    this.version = 3,
    this.source = 'diary_text_analysis',
    this.total = 0,
    this.counts = const {},
    this.ratios = const {},
    this.weights = const {},
    this.weightedRatios = const {},
    this.pendingCount = 0,
    this.excludedCount = 0,
    this.unavailableCount = 0,
    this.emptyCount = 0,
  });

  final int version;
  final String source;
  final int total;
  final Map<String, int> counts;
  final Map<String, double> ratios;
  final Map<String, double> weights;
  final Map<String, double> weightedRatios;
  final int pendingCount;
  final int excludedCount;
  final int unavailableCount;
  final int emptyCount;

  bool get hasData =>
      total > 0 ||
      counts.values.any((count) => count > 0) ||
      ratios.values.any((ratio) => ratio > 0) ||
      weights.values.any((weight) => weight > 0) ||
      weightedRatios.values.any((ratio) => ratio > 0);

  Map<String, double> get effectiveRatios {
    if (weightedRatios.values.any((ratio) => ratio > 0)) {
      return weightedRatios;
    }
    if (ratios.values.any((ratio) => ratio > 0)) return ratios;
    final countTotal = counts.values.fold<int>(0, (sum, count) => sum + count);
    if (countTotal <= 0) return const {};
    return {
      for (final entry in counts.entries) entry.key: entry.value / countTotal,
    };
  }

  double ratioFor(PlantGrowthForm form) =>
      effectiveRatios[form.emotionCode] ?? 0;

  List<PlantEmotionCue> get orderedCues {
    final cues = PlantGrowthForm.values
        .map((form) => PlantEmotionCue(form: form, ratio: ratioFor(form)))
        .where((cue) => cue.ratio > 0)
        .toList()
      ..sort((a, b) => b.ratio.compareTo(a.ratio));
    return cues;
  }

  List<PlantEmotionCue> topCues([int limit = 3]) => orderedCues
      .take(limit.clamp(0, PlantGrowthForm.values.length).toInt())
      .toList();

  /// 2단계의 미세한 시각 단서에만 쓴다. 성격 확정에는 쓰지 않는다.
  PlantGrowthForm? get leadingCue {
    if (!hasData) return null;
    final cues = orderedCues;
    if (cues.isEmpty) return null;
    if (cues.length > 1 && (cues[0].ratio - cues[1].ratio).abs() < .000001) {
      return PlantGrowthForm.mosaic;
    }
    return cues.first.form;
  }

  factory ActivePlantEmotionProfile.fromJson(Object? value) {
    final json = _plantMap(value);
    final counts = _plantMap(json['counts']);
    final ratios = _plantMap(json['ratios']);
    final weights = _plantMap(json['weights']);
    final weightedRatios = _plantMap(json['weighted_ratios']);
    return ActivePlantEmotionProfile(
      version: _plantInt(json['version'], fallback: 2),
      source: json['source']?.toString().trim().isNotEmpty == true
          ? json['source'].toString().trim()
          : 'diary_text_analysis',
      total: _plantInt(json['total']),
      counts: {
        for (final form in PlantGrowthForm.values)
          form.emotionCode: _plantInt(counts[form.emotionCode]),
      },
      ratios: {
        for (final form in PlantGrowthForm.values)
          if (_plantDouble(ratios[form.emotionCode]) != null)
            form.emotionCode: _plantDouble(ratios[form.emotionCode])!,
      },
      weights: {
        for (final form in PlantGrowthForm.values)
          if (_plantDouble(weights[form.emotionCode]) != null)
            form.emotionCode: _plantDouble(weights[form.emotionCode])!,
      },
      weightedRatios: {
        for (final form in PlantGrowthForm.values)
          if (_plantDouble(weightedRatios[form.emotionCode]) != null)
            form.emotionCode: _plantDouble(weightedRatios[form.emotionCode])!,
      },
      pendingCount: _plantInt(json['pending_count']),
      excludedCount: _plantInt(json['excluded_count']),
      unavailableCount: _plantInt(
        json['unavailable_count'] ?? json['failed_count'],
      ),
      emptyCount: _plantInt(json['empty_count']),
    );
  }
}

class PlantSpecies {
  const PlantSpecies({
    required this.id,
    required this.code,
    required this.name,
    this.rarity,
    this.unlockPrice,
    this.isUnlocked = true,
    this.assetManifest = const {},
  });

  final int id;
  final String code;
  final String name;
  final int? rarity;
  final int? unlockPrice;
  final bool isUnlocked;
  final Map<String, dynamic> assetManifest;

  factory PlantSpecies.fromJson(Map<String, dynamic> json) => PlantSpecies(
        id: json['id'] as int,
        code: (json['code'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        rarity: json['rarity'] as int?,
        unlockPrice: json['unlock_price'] as int?,
        isUnlocked: (json['is_unlocked'] as bool?) ?? true,
        assetManifest: _plantMap(json['asset_manifest']),
      );
}

/// 품종마다 씨앗과 육묘 환경을 바꾸기 위한 가벼운 렌더링 계약.
///
/// 새 서버는 식물의 `growth_visual`을 우선 내려 주고, 이전 응답은
/// `species.asset_manifest.growth`를 사용한다. 둘 다 없으면 품종 코드와
/// 희귀도만으로 번들 painter가 안전한 기본 모습을 고른다.
class PlantGrowthVisual {
  const PlantGrowthVisual({
    required this.seedShape,
    required this.vesselStyle,
    required this.rarityEffect,
    required this.assetNamespace,
    required this.rarity,
    this.secondaryAssetKey,
    this.phase = '',
    this.seedAssetKey,
    this.vesselAssetKey,
    this.baseAssetKey,
    this.renderLayers = const [],
    this.renderKey = '',
  });

  final String seedShape;
  final String vesselStyle;
  final String rarityEffect;
  final String assetNamespace;
  final int rarity;
  final String? secondaryAssetKey;
  final String phase;
  final String? seedAssetKey;
  final String? vesselAssetKey;
  final String? baseAssetKey;
  final List<String> renderLayers;
  final String renderKey;

  bool get isSpecial => rarity >= 2 || rarityEffect != 'none';

  String get seedLabel => switch (seedShape) {
        'heart_speck_seed' => '하트점 씨앗',
        'spined_star_seed' || 'thorn_star' => '가시별 씨앗',
        'striped_sun_seed' || 'striped_drop' => '해무늬 씨앗',
        'crystal_seed' || 'crystal' => '결정 씨앗',
        _ => '콩알 씨앗',
      };

  String get vesselLabel => switch (vesselStyle) {
        'ribbed_desert_incubator' || 'stone_bowl' => '사막결 육묘분',
        'sunbeam_bell_jar' || 'glass_pod' => '햇살 유리 육묘관',
        'crystal_growth_tube' || 'culture_tube' => '희귀 배양관',
        _ => '포근한 토분',
      };

  factory PlantGrowthVisual.fromSources({
    Object? active,
    required PlantSpecies species,
  }) {
    final primary = _plantMap(active);
    final manifestGrowth = _plantMap(
      species.assetManifest['growth_visual'] ?? species.assetManifest['growth'],
    );
    String pick(String key, String fallback) {
      final primaryValue = primary[key]?.toString().trim() ?? '';
      if (primaryValue.isNotEmpty) return primaryValue;
      final manifestValue = manifestGrowth[key]?.toString().trim() ?? '';
      return manifestValue.isEmpty ? fallback : manifestValue;
    }

    String? pickOptional(String key) {
      final primaryValue = primary[key]?.toString().trim() ?? '';
      if (primaryValue.isNotEmpty) return primaryValue;
      final manifestValue = manifestGrowth[key]?.toString().trim() ?? '';
      return manifestValue.isEmpty ? null : manifestValue;
    }

    List<String> pickList(String key) {
      final primaryValue = primary[key];
      if (primaryValue is List) {
        return primaryValue
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
      final manifestValue = manifestGrowth[key];
      if (manifestValue is List) {
        return manifestValue
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
      return const [];
    }

    final fallback = PlantGrowthVisual.fallback(
      speciesCode: species.code,
      rarity: species.rarity,
    );
    return PlantGrowthVisual(
      seedShape: pick('seed_shape', fallback.seedShape),
      vesselStyle: pick('vessel_style', fallback.vesselStyle),
      rarityEffect: pick('rarity_effect', fallback.rarityEffect),
      assetNamespace: pick('asset_namespace', fallback.assetNamespace),
      rarity: _plantInt(
        primary['rarity'] ??
            primary['rarity_level'] ??
            manifestGrowth['rarity'] ??
            species.rarity,
        fallback: fallback.rarity,
      ).clamp(1, 5).toInt(),
      secondaryAssetKey: pickOptional('secondary_asset_key'),
      phase: pick('phase', ''),
      seedAssetKey: pickOptional('seed_asset_key'),
      vesselAssetKey: pickOptional('vessel_asset_key'),
      baseAssetKey: pickOptional('base_asset_key'),
      renderLayers: pickList('render_layers'),
      renderKey: pick('render_key', ''),
    );
  }

  factory PlantGrowthVisual.fallback({
    required String speciesCode,
    int? rarity,
  }) {
    final code = speciesCode.trim().toLowerCase();
    final resolvedRarity = (rarity ??
            switch (code) {
              'cactus' || 'sunflower' => 2,
              _ => 1,
            })
        .clamp(1, 5)
        .toInt();
    return switch (code) {
      'basic_sprout' || 'mood_seed' => PlantGrowthVisual(
          seedShape: 'heart_speck_seed',
          vesselStyle: 'round_terracotta_pot',
          rarityEffect: 'none',
          assetNamespace:
              code == 'mood_seed' ? 'plants/mood_seed' : 'plants/basic_sprout',
          rarity: resolvedRarity,
        ),
      'cactus' => PlantGrowthVisual(
          seedShape: 'spined_star_seed',
          vesselStyle: 'ribbed_desert_incubator',
          rarityEffect: resolvedRarity >= 2 ? 'warm_dust_glint' : 'none',
          assetNamespace: 'plants/cactus',
          rarity: resolvedRarity,
        ),
      'sunflower' => PlantGrowthVisual(
          seedShape: 'striped_sun_seed',
          vesselStyle: 'sunbeam_bell_jar',
          rarityEffect: resolvedRarity >= 2 ? 'soft_sun_motes' : 'none',
          assetNamespace: 'plants/sunflower',
          rarity: resolvedRarity,
        ),
      _ => PlantGrowthVisual(
          seedShape: 'round_seed',
          vesselStyle: 'soft_terracotta_pot',
          rarityEffect: 'none',
          assetNamespace: 'plants/generic',
          rarity: resolvedRarity,
        ),
    };
  }
}

/// GET /plants/me 응답의 활성 식물. stage는 서버 계산값만 사용한다.
class ActivePlant {
  const ActivePlant({
    required this.id,
    required this.name,
    required this.species,
    required this.exp,
    required this.stage,
    required this.stageThresholds,
    required this.nextStageExp,
    required this.harvestable,
    required this.plantedAt,
    this.growthForm,
    this.secondaryForm,
    this.growthTraits = const PlantGrowthTraits(),
    this.conversationProfile = const PlantConversationProfile(),
    this.personality,
    this.branchStatus = PlantBranchStatus.observing,
    this.branchPhase = PlantBranchPhase.unformed,
    this.growthPhase = PlantGrowthPhase.seed,
    this.profileState = PlantProfileState.analyzing,
    this.branchConfidence = 0,
    this.emotionProfile = const ActivePlantEmotionProfile(),
    this.growthVisual,
    this.visualKey = '',
  });

  final int id;
  final String name;
  final PlantSpecies species;
  final int exp;
  final int stage;
  final List<int> stageThresholds;
  final int? nextStageExp;
  final bool harvestable;
  final DateTime? plantedAt;
  final PlantGrowthForm? growthForm;
  final PlantGrowthForm? secondaryForm;
  final PlantGrowthTraits growthTraits;
  final PlantConversationProfile conversationProfile;
  final PlantPersonality? personality;
  final PlantBranchStatus branchStatus;
  final PlantBranchPhase branchPhase;
  final PlantGrowthPhase growthPhase;
  final PlantProfileState profileState;
  final double branchConfidence;
  final ActivePlantEmotionProfile emotionProfile;
  final PlantGrowthVisual? growthVisual;
  final String visualKey;

  /// 새 계약의 이름을 그대로 쓸 수 있게 하되 기존 [growthForm] 호출부를
  /// 깨지 않는다.
  PlantGrowthForm? get dominantForm => growthForm;

  /// 씨앗은 공통 모습, 새싹은 분석 중인 미세 단서, 3단계부터는
  /// 서버가 확정한 분기를 보여 준다.
  PlantGrowthForm? get visualForm {
    if (stage <= 1) return null;
    if (stage == 2) return emotionProfile.leadingCue;
    return growthForm;
  }

  String get personalityName {
    if (stage < 3 || growthForm == null) return '아직 관찰 중';
    final growthTitle = growthTraits.title.trim();
    if (growthTitle.isNotEmpty) return growthTitle;
    final serverName = personality?.name.trim() ?? '';
    return serverName.isEmpty ? growthForm!.personalityName : serverName;
  }

  String get personalityDescription {
    final serverTrait = personality?.trait.trim() ?? '';
    if (serverTrait.isNotEmpty) return serverTrait;
    if (growthTraits.traits.isNotEmpty) {
      return growthTraits.traits.join(' · ');
    }
    return growthForm?.personalityDescription ?? '일기를 더 들어 보며 자라고 있어요.';
  }

  String get temperamentSummary => growthTraits.temperament.hasDetails
      ? growthTraits.temperament.summary
      : '';

  String get growthSummary => switch (stage.clamp(1, 5)) {
        1 => '일기에서 읽힌 마음을 차곡차곡 모으고 있어요.',
        2 when visualForm != null => '잎맥에 첫 색이 비치고 있어요. 아직 어떤 결인지는 더 지켜봐요.',
        2 => '일기가 더 쌓이면 잎맥에 첫 단서가 보여요.',
        _ when growthForm != null && secondaryForm != null =>
          '${growthForm!.emotionLabel} 주결에 ${secondaryForm!.emotionLabel} 보조결이 더해져 '
              '$personalityName으로 자라고 있어요.',
        _ when growthForm != null =>
          '${growthForm!.emotionLabel} 기록을 바탕으로 $personalityName으로 자라고 있어요.',
        _ => '일기 분석을 더 모아 성장 분기를 찾고 있어요.',
      };

  String? get analysisNotice {
    if (emotionProfile.pendingCount > 0) {
      return '일기 ${emotionProfile.pendingCount}편의 마음을 읽는 중이에요.';
    }
    final needed = 3 - emotionProfile.total;
    if (stage >= 5 && !harvestable && needed > 0) {
      if (emotionProfile.unavailableCount > 0) {
        return '분석할 수 없던 기록을 제외하고 수확 조건을 확인 중이에요.';
      }
      return '일기를 $needed편 더 들려주면 수확 준비가 끝나요.';
    }
    return null;
  }

  String get voiceLine {
    if (stage < 3) {
      return stage <= 1
          ? '아직은 작은 씨앗이야. 일기를 더 들려줘.'
          : '새잎에 어떤 마음빛이 나타날지 살펴보고 있어.';
    }
    final form = visualForm;
    if (form == null) {
      return '일기 분석이 더 쌓이면 내 결이 보일 거야.';
    }
    final serverLine = personality?.voiceLine.trim() ?? '';
    if (serverLine.isNotEmpty) return serverLine;
    return form.voiceLine(stage);
  }

  /// 숫자 XP만 보지 않아도 다음 성장 장면을 예상할 수 있게 하는 안내.
  /// 감정의 종류는 보상이나 성장 속도를 바꾸지 않는다.
  String get nextMilestoneLabel => switch (stage.clamp(1, 5)) {
        1 => '다음 장면 · 새싹에 첫 마음빛 단서가 나타나요.',
        2 => '다음 장면 · 줄기가 자라면 외형과 성격의 결이 드러나요.',
        3 => '다음 장면 · 꽃봉오리에 보조 마음빛과 기질이 더해져요.',
        4 => '다음 장면 · 만개하면 움직임과 대화 습관이 완성되고 박물관에 남을 수 있어요.',
        _ when harvestable => '만개 완료 · 이제 식물의 이야기를 박물관에 남길 수 있어요.',
        _ => '만개 완료 · 남은 일기 분석이 끝나면 박물관 준비가 완성돼요.',
      };

  /// 현재 단계 구간 안에서의 진행률(0.0~1.0). 만개면 1.0.
  double get stageProgress {
    if (stageThresholds.isEmpty) return 0;
    final currentIndex =
        (stage - 1).clamp(0, stageThresholds.length - 1).toInt();
    final currentFloor = stageThresholds[currentIndex];
    final next = nextStageExp;
    if (next == null || next <= currentFloor) return 1;
    final progress = (exp - currentFloor) / (next - currentFloor);
    return progress.clamp(0.0, 1.0).toDouble();
  }

  factory ActivePlant.fromJson(Map<String, dynamic> json) {
    final stage = _plantInt(json['stage'], fallback: 1).clamp(1, 5).toInt();
    final growth = _plantMap(json['growth']);
    final growthTraitsJson =
        json['growth_traits'] ?? growth['growth_traits'] ?? growth['traits'];
    final growthTraitsMap = _plantMap(growthTraitsJson);
    final growthForm = PlantGrowthForm.fromCode(
      json['dominant_form'] ??
          growth['dominant_form'] ??
          json['growth_form'] ??
          growth['form'] ??
          json['growth_branch'] ??
          growth['branch'] ??
          json['dominant_emotion'],
    );
    final secondaryForm = PlantGrowthForm.fromCode(
      json['secondary_form'] ??
          growth['secondary_form'] ??
          _plantMap(growthTraitsMap['secondary'])['form'] ??
          json['secondary_emotion'],
    );
    final personalityJson = json['growth_persona'] ??
        json['personality'] ??
        growth['persona'] ??
        growth['personality'];
    final personalityMap = _plantMap(personalityJson);
    final personality = PlantPersonality.fromJson(personalityJson);
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
    final conversationProfile = directConversationProfile.hasDetails
        ? directConversationProfile
        : growthTraits.chatStyle;
    final species = PlantSpecies.fromJson(
        (json['species'] as Map<String, dynamic>?) ?? const {'id': 0});
    return ActivePlant(
      id: json['id'] as int,
      name: (json['name'] as String?) ?? '',
      species: species,
      exp: (json['exp'] as int?) ?? 0,
      stage: stage,
      stageThresholds: ((json['stage_thresholds'] as List<dynamic>?) ??
              const [0, 20, 100, 250, 450])
          .whereType<int>()
          .toList(),
      nextStageExp: json['next_stage_exp'] as int?,
      harvestable: (json['harvestable'] as bool?) ?? false,
      plantedAt: json['planted_at'] == null
          ? null
          : DateTime.tryParse(json['planted_at'] as String),
      growthForm: stage >= 3 ? growthForm : null,
      secondaryForm: stage >= 4 ? secondaryForm : null,
      growthTraits: growthTraits,
      conversationProfile: conversationProfile,
      personality: personality.code.isEmpty && personality.name.isEmpty
          ? null
          : personality,
      branchStatus: PlantBranchStatus.fromCode(
        json['branch_status'] ?? growth['status'],
        stage: stage,
      ),
      branchPhase: PlantBranchPhase.fromCode(
        json['branch_phase'] ?? growth['branch_phase'],
        stage: stage,
      ),
      growthPhase: PlantGrowthPhase.fromCode(
        json['growth_phase'] ?? growth['growth_phase'],
        stage: stage,
      ),
      profileState: PlantProfileState.fromCode(
        json['profile_state'] ?? growth['profile_state'],
      ),
      branchConfidence: (_plantDouble(
                json['branch_confidence'] ?? growth['confidence'],
              ) ??
              0)
          .clamp(0, 1)
          .toDouble(),
      emotionProfile: ActivePlantEmotionProfile.fromJson(
        json['emotion_profile'] ??
            json['growth_profile'] ??
            growth['emotion_profile'] ??
            growth['profile'],
      ),
      growthVisual: PlantGrowthVisual.fromSources(
        active: json['growth_visual'] ?? growth['visual'],
        species: species,
      ),
      visualKey: json['visual_key']?.toString() ??
          growth['visual_key']?.toString() ??
          '',
    );
  }
}

Map<String, dynamic> _plantMap(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const <String, dynamic>{};

int _plantInt(Object? value, {int fallback = 0}) => switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text) ?? fallback,
      _ => fallback,
    };

double? _plantDouble(Object? value) => switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text),
      _ => null,
    };
