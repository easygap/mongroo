import 'dart:math' as math;

const _v2CharacterSlugs = {
  'baby-pot',
  'handsome-pot',
  'pretty-pot',
  'tsundere-pot',
  'zombie-pot',
  'gumiho-pot',
  'ninja-pot',
  'magical-pot',
  'aloof-pot',
  'student-pot',
};

const _v3CharacterSlugs = {
  'tsundere-pot',
  'gumiho-pot',
};

const _v6CharacterSlugs = {
  'nurse-pot',
  'maestro-pot',
};

const _v7CharacterSlugs = {
  'restorer-pot',
  'marten-pot',
  'gal-pot',
};

int gardenInt(Object? value, [int fallback = 0]) => switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text) ?? fallback,
      _ => fallback,
    };

double gardenDouble(Object? value, [double fallback = 0]) => switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text) ?? fallback,
      _ => fallback,
    };

Map<String, dynamic> gardenMap(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

String? gardenAssetPath(Map<String, dynamic> manifest) {
  for (final key in const [
    'preview_url',
    'thumbnail_url',
    'asset_url',
    'preview',
    'thumbnail',
    'image',
    'base',
  ]) {
    final value = manifest[key];
    if (value is String && value.isNotEmpty) return value;
  }
  final stage = manifest['stage_5'] ?? manifest['5'];
  if (stage is String && stage.isNotEmpty) return stage;
  if (stage is Map<String, dynamic>) return gardenAssetPath(stage);
  return null;
}

String? gardenString(Map<String, dynamic> manifest, String key) {
  final value = manifest[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

String _moodFormLabel(String form) => switch (form) {
      'sunny' => '햇살꽃',
      'rainy' => '빗방울꽃',
      'ember' => '불씨꽃',
      'moonlit' => '달그늘꽃',
      'sparkling' => '반짝꽃',
      'mosaic' => '마음모아꽃',
      _ => form,
    };

/// 상점 상품을 얻기 위한 서버 계산 결과.
///
/// [type]이 `purchase`이면 씨앗 구매, 그 밖의 값이면 조건을 달성한 뒤
/// claim API로 받는 보상이다. 진행률은 서버 값을 그대로 보관하되 UI에서만
/// 0~1 범위로 보정해, 새 획득 조건이 추가돼도 모델 변경 없이 표시할 수 있다.
class ShopItemAcquisition {
  const ShopItemAcquisition({
    required this.type,
    required this.label,
    required this.current,
    required this.target,
    required this.eligible,
  });

  final String type;
  final String label;
  final int current;
  final int target;
  final bool eligible;

  bool get isPurchase => type == 'purchase';
  bool get requiresClaim => !isPurchase;

  double get progress {
    if (target <= 0) return eligible ? 1 : 0;
    return (current / target).clamp(0.0, 1.0).toDouble();
  }

  String get progressLabel => target > 0 ? '$current/$target' : label;

  ShopItemAcquisition copyWith({bool? eligible}) => ShopItemAcquisition(
        type: type,
        label: label,
        current: current,
        target: target,
        eligible: eligible ?? this.eligible,
      );

  static ShopItemAcquisition? maybeFromJson(Object? value) {
    final json = gardenMap(value);
    if (json.isEmpty) return null;
    final type = (json['type'] as String?)?.trim();
    if (type == null || type.isEmpty) return null;
    return ShopItemAcquisition(
      type: type,
      label: ((json['label'] as String?)?.trim().isNotEmpty ?? false)
          ? (json['label'] as String).trim()
          : _fallbackLabel(type),
      current: gardenInt(json['current']),
      target: gardenInt(json['target']),
      eligible: json['eligible'] == true,
    );
  }

  static String _fallbackLabel(String type) => switch (type) {
        'purchase' => '씨앗으로 구매',
        'quest_count' => '작은 행동 달성',
        'streak' => '연속 기록 달성',
        'record_count' => '누적 기록 달성',
        'own_item' => '필요한 아이템 보유',
        'collection_count' => '도감 수집 달성',
        'harvest_form' => '해당 마음꽃 첫 수확',
        _ => '획득 조건 달성',
      };
}

class ShopItem {
  const ShopItem({
    required this.id,
    required this.code,
    required this.type,
    required this.name,
    required this.description,
    required this.priceSeeds,
    required this.rarity,
    required this.assetManifest,
    required this.owned,
    this.acquisition,
  });

  final int id;
  final String code;
  final String type;
  final String name;
  final String description;
  final int priceSeeds;
  final int rarity;
  final Map<String, dynamic> assetManifest;
  final bool owned;
  final ShopItemAcquisition? acquisition;

  String? get assetPath => gardenAssetPath(assetManifest);
  String? get assetKey => gardenString(assetManifest, 'asset_key');

  /// 상품 코드를 앱 번들 자산에 연결한다.
  ///
  /// 서버가 실제 URL을 내려주면 [assetPath]가 우선하고, 로컬 데모 카탈로그는
  /// 이 매핑을 사용한다. 보상마다 고유 비주얼을 보장해 fallback 아이콘이 서로
  /// 다른 상품을 같은 물건처럼 보이게 하지 않도록 한다.
  String? get bundledAssetPath => switch (code) {
        'deco_cushion_leaf' => 'assets/decorations/leaf-cushion.webp',
        'deco_lamp_moon' => 'assets/decorations/moon-lamp.webp',
        'deco_rug_cloud' => 'assets/decorations/cloud-rug.webp',
        'deco_lamp_mushroom' => 'assets/decorations/mushroom-reading-lamp.webp',
        'deco_radio_strawberry' => 'assets/decorations/strawberry-radio.webp',
        'deco_stool_frog' => 'assets/decorations/frog-stool.webp',
        'deco_books_pressed' => 'assets/decorations/pressed-flower-books.webp',
        'deco_mobile_moon_seed' => 'assets/decorations/moon-seed-mobile.webp',
        'deco_planter_teacup' => 'assets/decorations/teacup-planter.webp',
        'deco_resonance_sunny' => 'assets/decorations/mood-lamp-sunny.webp',
        'deco_resonance_rainy' =>
          'assets/decorations/listening-chime-rainy.webp',
        'deco_resonance_ember' =>
          'assets/decorations/courage-lantern-ember.webp',
        'deco_resonance_moonlit' =>
          'assets/decorations/preparation-lamp-moonlit.webp',
        'deco_resonance_sparkling' =>
          'assets/decorations/prism-bud-sparkling.webp',
        'deco_resonance_mosaic' =>
          'assets/decorations/many-heart-mobile-mosaic.webp',
        'room_sunny' => 'assets/rooms/sunny-greenhouse.webp',
        'room_pressed_studio' => 'assets/rooms/pressed-flower-studio.webp',
        'companion_dewdrop' => 'assets/companions/dewdrop.webp',
        'companion_star' => 'assets/companions/star-bean.webp',
        'companion_bunny' => 'assets/companions/fluffy-bunny.webp',
        'species_cactus' => 'assets/species/cactus-seed.webp',
        'species_sunflower' => 'assets/species/sunflower-seed.webp',
        _ => null,
      };

  /// 씨앗부터 일기 감정을 먹고 자라는 핵심 캐릭터 품종.
  ///
  /// `main_character`는 초기 카탈로그에서 완성 캐릭터를 따로 팔던 이름이다.
  /// 새 화면은 이를 별도 캐릭터로 취급하지 않고 `species_unlock`과 같은
  /// 성장 씨앗으로 읽는다.
  bool get isGrowthCharacter =>
      type == 'main_character' || type == 'species_unlock';

  /// 기존 사람형 원화가 있는 성장 계보.
  ///
  /// 완성 캐릭터를 별도 상품으로 취급하지 않고, 씨앗이 도달할 수 있는
  /// 완전체 미리보기로 사용한다.
  bool get hasFinalCharacterPreview =>
      type == 'main_character' &&
      (assetKey?.startsWith('characters/') ?? false);

  bool get isCompanion => type == 'companion';

  /// 기존 호출부 호환용. 성장 캐릭터와 작은 동행 아이템을 모두 포함한다.
  bool get isCharacter => isGrowthCharacter || isCompanion;
  bool get isRoomTheme => type == 'room_theme';
  bool get isWardrobe => type == 'wardrobe';
  String? get wardrobeLayerKey =>
      gardenString(assetManifest, 'wardrobe_layer_key');
  Map<String, dynamic> get adventureBonus =>
      gardenMap(assetManifest['adventure_bonus']);
  String? get adventureBonusLabel => gardenString(adventureBonus, 'label');
  String? get adventureBonusContext => gardenString(adventureBonus, 'context');
  String? get adventureBonusStat => gardenString(adventureBonus, 'stat');
  int get adventureBonusAmount => gardenInt(adventureBonus['amount']);
  String get wardrobeSlot =>
      gardenString(assetManifest, 'wardrobe_slot') ?? 'outfit';
  List<String> get compatibleSpecies {
    final value = assetManifest['compatible_species'];
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map((species) => species.trim())
        .where((species) => species.isNotEmpty)
        .toList(growable: false);
  }

  bool supportsSpecies(String speciesCode) =>
      compatibleSpecies.isEmpty || compatibleSpecies.contains(speciesCode);
  String? get collectionCode => gardenString(assetManifest, 'collection');
  String? get reactionCopy => gardenString(assetManifest, 'reaction_copy');

  List<String> get affinityForms {
    final value = assetManifest['affinity_forms'];
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map((form) => form.trim())
        .where((form) => form.isNotEmpty)
        .toList(growable: false);
  }

  bool get isMoodResonance =>
      collectionCode == 'mood_resonance' || affinityForms.isNotEmpty;

  String get affinityLabel {
    final labels = affinityForms.map(_moodFormLabel).toList(growable: false);
    return labels.isEmpty ? '모든 마음꽃' : labels.join(' · ');
  }

  bool get requiresClaim => acquisition?.requiresClaim ?? false;
  bool get canClaim => !owned && requiresClaim && acquisition!.eligible;

  String get acquisitionHint {
    final rule = acquisition;
    if (rule == null) {
      return priceSeeds > 0 ? '씨앗 $priceSeeds개로 구매' : '상점에서 획득';
    }
    return rule.target > 0
        ? '${rule.label} · ${rule.progressLabel}'
        : rule.label;
  }

  String get characterSlug {
    final key = assetKey;
    if (key != null &&
        (key.startsWith('characters/') || key.startsWith('character/'))) {
      return key.substring(key.indexOf('/') + 1);
    }
    return code
        .replaceFirst(RegExp(r'^(character|companion)_'), '')
        .replaceAll('-', '_');
  }

  String? get bundledCharacterAssetPath {
    if (!isCharacter) return null;
    final key = assetKey;
    if (key == null ||
        (!key.startsWith('characters/') && !key.startsWith('character/'))) {
      return bundledAssetPath;
    }
    final slug = key.substring(key.indexOf('/') + 1);
    final version = _v7CharacterSlugs.contains(slug)
        ? '-v7'
        : _v6CharacterSlugs.contains(slug)
            ? '-v6'
            : _v3CharacterSlugs.contains(slug)
                ? '-v3'
                : _v2CharacterSlugs.contains(slug)
                    ? '-v2'
                    : '';
    return 'assets/characters/$slug$version.webp';
  }

  String get motionKey =>
      gardenString(assetManifest, 'motion_key') ?? _fallbackMotionKey;

  String get personality =>
      gardenString(assetManifest, 'personality') ?? _fallbackPersonality;

  String get catchphrase =>
      gardenString(assetManifest, 'catchphrase') ?? _fallbackCatchphrase;

  /// 도감 상세에서만 공개하는 캐릭터 서사 메타데이터.
  ///
  /// 잠금 여부는 화면 계층이 판단한다. 모델은 서버가 제공한 원문만 반환해
  /// 아직 서사가 없는 일반 꾸미기 아이템에 임의의 설정을 붙이지 않는다.
  String? get storyRole => gardenString(assetManifest, 'story_role');
  String? get loreHook => gardenString(assetManifest, 'lore_hook');
  String? get collectionQuote =>
      gardenString(assetManifest, 'collection_quote');
  bool get hasCollectionStory =>
      storyRole != null || loreHook != null || collectionQuote != null;

  Map<String, dynamic> get baseOutfit =>
      gardenMap(assetManifest['base_outfit']);
  String? get baseOutfitName => gardenString(baseOutfit, 'name');
  bool get includesBaseOutfit => baseOutfit['included_with_character'] == true;

  bool get isSpeciesUnlock => type == 'species_unlock';

  String get growthSpeciesCode {
    final manifestCode =
        gardenString(assetManifest, 'species_code')?.trim().toLowerCase();
    if (manifestCode?.isNotEmpty == true) return manifestCode!;
    if (hasFinalCharacterPreview) {
      return characterSlug.replaceAll('-', '_');
    }
    return code
        .replaceFirst(RegExp(r'^(character|species)_'), '')
        .replaceAll('-', '_');
  }

  String get _characterIdentity => '$characterSlug $code'.toLowerCase();
  bool get _isBabyCharacter {
    final identity = _characterIdentity;
    return identity.contains('baby') ||
        RegExp(r'(^|[^a-z0-9])agi([^a-z0-9]|$)').hasMatch(identity);
  }

  String get _fallbackMotionKey {
    final identity = _characterIdentity;
    if (_isBabyCharacter) {
      return 'baby_bounce';
    }
    if (identity.contains('handsome') || identity.contains('prince')) {
      return 'prince_flourish';
    }
    if (identity.contains('pretty')) return 'pretty_sparkle';
    if (identity.contains('tsundere')) return 'tsundere_turn_away';
    if (identity.contains('zombie')) return 'zombie_sway';
    if (identity.contains('gumiho')) return 'gumiho_float';
    if (identity.contains('ninja')) return 'ninja_snap';
    if (identity.contains('aloof')) return 'aloof_glance';
    if (identity.contains('student')) return 'student_adjust';
    if (identity.contains('nurse')) return 'nurse_breathe';
    if (identity.contains('maestro')) return 'maestro_cue';
    if (identity.contains('restorer')) return 'restorer_settle';
    if (identity.contains('marten')) return 'marten_scout';
    if (identity.contains('gal')) return 'gal_style_step';
    if (identity.contains('dewdrop')) return 'dewdrop_bob';
    if (identity.contains('star')) return 'star_hop';
    if (identity.contains('bunny')) return 'bunny_bounce';
    if (identity.contains('mongle')) return 'cloud_float';
    return 'magical_hover';
  }

  String get _fallbackPersonality {
    final identity = _characterIdentity;
    if (_isBabyCharacter) {
      return '쪽쪽이를 문 호기심쟁이 막내';
    }
    if (identity.contains('handsome') || identity.contains('prince')) {
      return '흐트러짐을 못 보는 냉정한 리더';
    }
    if (identity.contains('pretty')) return '무대 체질인 새싹 아이돌';
    if (identity.contains('tsundere')) return '시선을 피하며 챙겨 주는 정석 츤데레';
    if (identity.contains('zombie')) return '해 질 무렵 깨어나는 느긋한 좀비';
    if (identity.contains('gumiho')) return '눈맞춤과 부채로 홀리는 요염한 구미호';
    if (identity.contains('ninja')) return '잎 수리검을 다루는 재빠른 정찰꾼';
    if (identity.contains('aloof')) return '서리꽃을 지키는 말수 적은 라이벌';
    if (identity.contains('student')) return '수첩부터 펴는 원칙주의 학생회장';
    if (identity.contains('nurse')) return '모두의 생명선을 지키는 성숙한 백의 수호사';
    if (identity.contains('maestro')) return '전장의 박자를 바꾸는 냉정한 공명 지휘자';
    if (identity.contains('restorer')) return '상처의 흔적까지 이어 주는 중년 복원사';
    if (identity.contains('marten')) return '발자국과 체온으로 길을 기억하는 숲담비';
    if (identity.contains('gal')) return '좋아하는 마음을 전투복으로 엮는 스타일 메이커';
    if (identity.contains('dewdrop')) return '잎 목도리를 두른 물방울 탐험가';
    if (identity.contains('star')) return '길을 먼저 밝히는 별 모양 씨앗';
    if (identity.contains('bunny')) return '씨앗 가방을 멘 잎귀 토끼';
    if (identity.contains('mongle')) return '새싹을 달고 떠다니는 구름 친구';
    return description.isEmpty ? '별자리 주문을 연구하는 마법학교 우등생' : description;
  }

  String get _fallbackCatchphrase {
    final identity = _characterIdentity;
    if (_isBabyCharacter) {
      return '뽀또! 새싹 하나 더 찾았어!';
    }
    if (identity.contains('handsome') || identity.contains('prince')) {
      return '소매부터 바로잡아. 출발하지.';
    }
    if (identity.contains('pretty')) return '센터는 나야. 박자 맞춰!';
    if (identity.contains('tsundere')) {
      return '오해하지 마. 네가 걱정돼서 그런 건 아니니까.';
    }
    if (identity.contains('zombie')) return '해 뜨기 전까진… 아직 시간 많아.';
    if (identity.contains('gumiho')) {
      return '후후, 그렇게 빤히 보면 내가 먼저 홀려버릴지도 몰라.';
    }
    if (identity.contains('ninja')) return '연막 잎 준비. 셋에 움직여.';
    if (identity.contains('aloof')) return '서리꽃은 함부로 만지지 마.';
    if (identity.contains('student')) return '수첩 펴. 할 일부터 정리하자.';
    if (identity.contains('nurse')) {
      return '괜찮아. 누구도 혼자 쓰러지게 두지 않아.';
    }
    if (identity.contains('maestro')) return '승리할 박자는 내가 정할게.';
    if (identity.contains('restorer')) return '흔적은 지우지 않아. 다시 이어 주지.';
    if (identity.contains('marten')) return '모루가 먼저 가. 이 냄새, 집으로 이어져!';
    if (identity.contains('gal')) return '좋아하는 걸 숨기지 마. 그게 오늘 제일 강해.';
    if (identity.contains('dewdrop')) return '이슬길은 내가 먼저 살펴볼게!';
    if (identity.contains('star')) return '반짝! 이쪽 길이야.';
    if (identity.contains('bunny')) return '새 씨앗 냄새가 나. 따라와!';
    if (identity.contains('mongle')) return '둥실둥실, 오늘은 어디로 갈까?';
    return '별자리 세 번째 줄, 주문 시작!';
  }

  String get typeLabel => switch (type) {
        'deco' => '꾸미기',
        'room_theme' => '방 테마',
        'main_character' => '성장 씨앗',
        'companion' => '동행 친구',
        'species_unlock' => '성장 씨앗',
        'wardrobe' => '의상',
        _ => '아이템',
      };

  String get rarityLabel => switch (rarity) {
        >= 4 => '아주 희귀',
        3 => '희귀',
        2 => '특별',
        _ => '기본',
      };

  ShopItem copyWith({
    bool? owned,
    ShopItemAcquisition? acquisition,
  }) =>
      ShopItem(
        id: id,
        code: code,
        type: type,
        name: name,
        description: description,
        priceSeeds: priceSeeds,
        rarity: rarity,
        assetManifest: assetManifest,
        owned: owned ?? this.owned,
        acquisition: acquisition ?? this.acquisition,
      );

  factory ShopItem.fromJson(Map<String, dynamic> json) {
    final manifest = gardenMap(json['asset_manifest']);
    return ShopItem(
      id: gardenInt(json['id']),
      code: (json['code'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'deco',
      name: (json['name'] as String?) ?? '이름 없는 아이템',
      description: (json['description'] as String?) ?? '',
      priceSeeds: gardenInt(json['price_seeds']),
      rarity: gardenInt(json['rarity'], 1),
      assetManifest: manifest,
      owned: (json['owned'] as bool?) ?? false,
      // 최신 API는 계산된 acquisition을 최상위에 둔다. manifest fallback은
      // 이전 카탈로그 응답과 로컬 fixture를 안전하게 읽기 위한 호환 경로다.
      acquisition: ShopItemAcquisition.maybeFromJson(
        json['acquisition'] ?? manifest['acquisition'],
      ),
    );
  }
}

class UserGardenItem {
  const UserGardenItem({
    required this.id,
    required this.item,
    this.acquiredAt,
  });

  final int id;
  final ShopItem item;
  final DateTime? acquiredAt;

  factory UserGardenItem.fromJson(Map<String, dynamic> json) => UserGardenItem(
        id: gardenInt(json['id']),
        item: ShopItem.fromJson({
          ...gardenMap(json['item']),
          'owned': true,
        }),
        acquiredAt: json['acquired_at'] is String
            ? DateTime.tryParse(json['acquired_at'] as String)
            : null,
      );
}

class ShopCatalog {
  const ShopCatalog({required this.items, required this.seedBalance});

  final List<ShopItem> items;
  final int seedBalance;

  ShopCatalog markOwned(
    int itemId,
    int nextBalance, {
    ShopItemAcquisition? acquisition,
  }) =>
      ShopCatalog(
        items: [
          for (final item in items)
            item.id == itemId
                ? item.copyWith(owned: true, acquisition: acquisition)
                : item.acquisition?.isPurchase == true
                    ? item.copyWith(
                        acquisition: item.acquisition!.copyWith(
                          eligible: nextBalance >= item.priceSeeds,
                        ),
                      )
                    : item,
        ],
        seedBalance: nextBalance,
      );

  factory ShopCatalog.fromJson(Map<String, dynamic> json) => ShopCatalog(
        items: ((json['items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ShopItem.fromJson)
            .toList(),
        seedBalance: gardenInt(json['seed_balance']),
      );
}

class ShopPurchaseResult {
  const ShopPurchaseResult({
    required this.userItem,
    required this.seedBalance,
    this.acquisition,
  });

  final UserGardenItem userItem;
  final int seedBalance;
  final ShopItemAcquisition? acquisition;

  factory ShopPurchaseResult.fromJson(Map<String, dynamic> json) =>
      ShopPurchaseResult(
        userItem: UserGardenItem.fromJson(gardenMap(json['user_item'])),
        seedBalance: gardenInt(json['seed_balance']),
        acquisition: ShopItemAcquisition.maybeFromJson(json['acquisition']),
      );
}

class SpeciesCollectionEntry {
  const SpeciesCollectionEntry({
    required this.id,
    required this.code,
    required this.name,
    required this.rarity,
    required this.unlockPrice,
    required this.isUnlocked,
  });

  final int id;
  final String code;
  final String name;
  final int rarity;
  final int unlockPrice;
  final bool isUnlocked;

  factory SpeciesCollectionEntry.fromJson(Map<String, dynamic> json) =>
      SpeciesCollectionEntry(
        id: gardenInt(json['id']),
        code: (json['code'] as String?) ?? '',
        name: (json['name'] as String?) ?? '이름 없는 식물',
        rarity: gardenInt(json['rarity'], 1),
        unlockPrice: gardenInt(json['unlock_price']),
        isUnlocked: (json['is_unlocked'] as bool?) ?? false,
      );
}

class GardenCollection {
  const GardenCollection({
    required this.items,
    required this.species,
    required this.seedBalance,
    this.catalogItems = const [],
  });

  final List<UserGardenItem> items;
  final List<SpeciesCollectionEntry> species;
  final int seedBalance;
  final List<ShopItem> catalogItems;

  /// 성장 캐릭터 씨앗은 상점에는 남지만 도감의 아이템 분류에서는 제외한다.
  ///
  /// 같은 해금이 [species]와 과거 `main_character`/`species_unlock` 카탈로그
  /// 양쪽에서 내려오는 호환 API라, 이 경계를 두지 않으면 하나의 성장
  /// 캐릭터가 캐릭터 도감과 아이템 도감에 중복 표시된다.
  List<ShopItem> get collectionCatalogItems => catalogItems
      .where((entry) => !entry.isGrowthCharacter)
      .toList(growable: false);

  List<ShopItem> get ownedCollectionItems => items
      .map((entry) => entry.item)
      .where((entry) => !entry.isGrowthCharacter)
      .toList(growable: false);

  /// 사람형 완전체 원화가 연결된 성장 계보.
  ///
  /// 서버가 전체 카탈로그를 주면 잠긴 계보도 보여 주고, 구버전 응답은
  /// 사용자가 보유한 항목만 사용한다.
  /// 계보 항목이 이미 대표하는 품종 코드.
  ///
  /// 품종 목록과 계보 항목은 **같은 캐릭터를 두 번 담는다** - 열여덟 품종 중
  /// 열다섯이 상점의 캐릭터 항목과 짝이다. 코드 표기가 `baby-pot`과
  /// `baby_pot`으로 갈리므로 비교 전에 맞춘다.
  Set<String> get _lineageSpeciesKeys => {
        for (final item in growthLineageItems)
          if (item.growthSpeciesCode.trim().isNotEmpty)
            _speciesKey(item.growthSpeciesCode),
      };

  /// 도감이 세울 품종 카드. 계보 항목과 겹치는 품종은 뺀다.
  ///
  /// 그대로 이어 붙이면 도감에 뽀또가 두 번 서고 수집 숫자도 두 번 세인다.
  List<SpeciesCollectionEntry> get standaloneSpecies {
    final covered = _lineageSpeciesKeys;
    return species
        .where((entry) => !covered.contains(_speciesKey(entry.code)))
        .toList(growable: false);
  }

  List<ShopItem> get growthLineageItems {
    final catalog = catalogItems
        .where((entry) => entry.hasFinalCharacterPreview)
        .toList(growable: false);
    if (catalog.isNotEmpty) return catalog;
    return items
        .map((entry) => entry.item)
        .where((entry) => entry.hasFinalCharacterPreview)
        .toList(growable: false);
  }

  int get unlockedCount {
    final catalog = collectionCatalogItems;
    final itemCount = catalog.isEmpty
        ? ownedCollectionItems.length
        : catalog.where((entry) => entry.owned).length;
    return itemCount +
        species.where((entry) => entry.isUnlocked).length +
        growthLineageItems.where((entry) => entry.owned).length;
  }

  int get totalCount {
    final catalog = collectionCatalogItems;
    final itemCount =
        catalog.isEmpty ? ownedCollectionItems.length : catalog.length;
    return itemCount + species.length + growthLineageItems.length;
  }

  factory GardenCollection.fromJson(Map<String, dynamic> json) =>
      GardenCollection(
        items: ((json['items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(UserGardenItem.fromJson)
            .toList(),
        species: ((json['species'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SpeciesCollectionEntry.fromJson)
            .toList(),
        seedBalance: gardenInt(json['seed_balance']),
        catalogItems: ((json['catalog_items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((entry) {
          final item = gardenMap(entry['item']);
          return ShopItem.fromJson(
            item.isEmpty
                ? entry
                : {
                    ...item,
                    'owned': entry['owned'] ?? item['owned'],
                    'acquisition': entry['acquisition'] ?? item['acquisition'],
                  },
          );
        }).toList(),
      );
}

class FarmDecoration {
  const FarmDecoration({
    required this.userItemId,
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
    required this.zIndex,
  });

  final int userItemId;

  /// 서버와 주고받는 0~1 정규화 좌표.
  final double x;
  final double y;
  final double scale;

  /// Transform.rotate와 서버 계약이 공통으로 쓰는 라디안(-pi~pi).
  final double rotation;
  final int zIndex;

  FarmDecoration copyWith({
    double? x,
    double? y,
    double? scale,
    double? rotation,
    int? zIndex,
  }) =>
      FarmDecoration(
        userItemId: userItemId,
        x: (x ?? this.x).clamp(0.0, 1.0).toDouble(),
        y: (y ?? this.y).clamp(0.0, 1.0).toDouble(),
        scale: (scale ?? this.scale).clamp(0.5, 2.0).toDouble(),
        rotation:
            (rotation ?? this.rotation).clamp(-math.pi, math.pi).toDouble(),
        zIndex: zIndex ?? this.zIndex,
      );

  Map<String, dynamic> toJson() => {
        'user_item_id': userItemId,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'z_index': zIndex,
      };

  factory FarmDecoration.fromJson(Map<String, dynamic> json) => FarmDecoration(
        userItemId: gardenInt(json['user_item_id']),
        x: gardenDouble(json['x'], 0.5).clamp(0.0, 1.0).toDouble(),
        y: gardenDouble(json['y'], 0.6).clamp(0.0, 1.0).toDouble(),
        scale: gardenDouble(json['scale'], 1).clamp(0.5, 2.0).toDouble(),
        rotation:
            gardenDouble(json['rotation']).clamp(-math.pi, math.pi).toDouble(),
        zIndex: gardenInt(json['z_index']),
      );
}

const _farmUnset = Object();

class FarmLayout {
  const FarmLayout({
    required this.version,
    required this.companionUserItemIds,
    required this.decorations,
    this.roomThemeUserItemId,
    this.mainCharacterUserItemId,
    this.wardrobeUserItemId,
  });

  final int version;
  final int? roomThemeUserItemId;
  final int? mainCharacterUserItemId;
  final int? wardrobeUserItemId;
  final List<int> companionUserItemIds;
  final List<FarmDecoration> decorations;

  FarmLayout copyWith({
    int? version,
    Object? roomThemeUserItemId = _farmUnset,
    Object? mainCharacterUserItemId = _farmUnset,
    Object? wardrobeUserItemId = _farmUnset,
    List<int>? companionUserItemIds,
    List<FarmDecoration>? decorations,
  }) =>
      FarmLayout(
        version: version ?? this.version,
        roomThemeUserItemId: roomThemeUserItemId == _farmUnset
            ? this.roomThemeUserItemId
            : roomThemeUserItemId as int?,
        mainCharacterUserItemId: mainCharacterUserItemId == _farmUnset
            ? this.mainCharacterUserItemId
            : mainCharacterUserItemId as int?,
        wardrobeUserItemId: wardrobeUserItemId == _farmUnset
            ? this.wardrobeUserItemId
            : wardrobeUserItemId as int?,
        companionUserItemIds: companionUserItemIds ?? this.companionUserItemIds,
        decorations: decorations ?? this.decorations,
      );

  Map<String, dynamic> toUpdateJson() => {
        'expected_version': version,
        'room_theme_user_item_id': roomThemeUserItemId,
        'main_character_user_item_id': mainCharacterUserItemId,
        'wardrobe_user_item_id': wardrobeUserItemId,
        'companion_user_item_ids': companionUserItemIds,
        'decorations': decorations.map((item) => item.toJson()).toList(),
      };

  factory FarmLayout.fromJson(Map<String, dynamic> json) => FarmLayout(
        version: gardenInt(json['version']),
        roomThemeUserItemId: json['room_theme_user_item_id'] == null
            ? null
            : gardenInt(json['room_theme_user_item_id']),
        mainCharacterUserItemId: json['main_character_user_item_id'] == null
            ? null
            : gardenInt(json['main_character_user_item_id']),
        wardrobeUserItemId: json['wardrobe_user_item_id'] == null
            ? null
            : gardenInt(json['wardrobe_user_item_id']),
        companionUserItemIds:
            ((json['companion_user_item_ids'] as List<dynamic>?) ?? const [])
                .map(gardenInt)
                .where((id) => id > 0)
                .toList(),
        decorations: ((json['decorations'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FarmDecoration.fromJson)
            .toList(),
      );
}

class FarmData {
  const FarmData({required this.layout, required this.ownedItems});

  final FarmLayout layout;
  final List<UserGardenItem> ownedItems;

  UserGardenItem? itemByUserItemId(int? id) {
    if (id == null) return null;
    for (final item in ownedItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// 저장된 방 배치에서 현재 메인 무대에 장착된 캐릭터.
  ///
  /// 보유 목록에 없는 오래된 ID는 안전하게 null로 취급해 호출 화면이 기본
  /// 캐릭터로 대체할 수 있게 한다.
  UserGardenItem? get equippedMainCharacter =>
      itemByUserItemId(layout.mainCharacterUserItemId);

  UserGardenItem? get equippedWardrobe =>
      itemByUserItemId(layout.wardrobeUserItemId);

  List<UserGardenItem> itemsOfType(String type) =>
      ownedItems.where((entry) => entry.item.type == type).toList();

  FarmData copyWith({FarmLayout? layout, List<UserGardenItem>? ownedItems}) =>
      FarmData(
        layout: layout ?? this.layout,
        ownedItems: ownedItems ?? this.ownedItems,
      );

  factory FarmData.fromJson(Map<String, dynamic> json) => FarmData(
        layout: FarmLayout.fromJson(gardenMap(json['layout'])),
        ownedItems: ((json['owned_items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(UserGardenItem.fromJson)
            .toList(),
      );
}

/// 품종 코드 비교용 정규화. `baby-pot`과 `baby_pot`을 같은 것으로 본다.
String _speciesKey(String code) =>
    code.trim().toLowerCase().replaceAll('-', '_');
