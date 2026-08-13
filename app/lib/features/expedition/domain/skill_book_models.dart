int _asInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

/// 카탈로그 한 권. 보유하지 않은 책도 내려오므로 `owned`로 구분한다.
///
/// 획득 경로에 확률이 없어서 아직 없는 책도 어디서 얻는지 전부 보여 준다.
class SkillBook {
  const SkillBook({
    required this.code,
    required this.name,
    required this.grade,
    required this.activationMode,
    required this.effectSummary,
    required this.stackGroup,
    required this.minSlot,
    required this.acquireKind,
    required this.owned,
    required this.combatEffect,
    this.priceSeeds,
    this.unlockHint,
    this.tradeoff,
  });

  final String code;
  final String name;
  final int grade;

  /// `command`만 대원의 행동 한 번을 쓴다. `opening`·`trigger`는 스스로 발동한다.
  final String activationMode;
  final String effectSummary;
  final String stackGroup;

  /// 3등급은 `B2`. 두 번째 칸에서만 펼쳐진다.
  final String minSlot;
  final String acquireKind;
  final bool owned;

  /// 전투 판정에 연결됐는지. false면 장착은 되지만 아직 효과가 나지 않는다.
  final bool combatEffect;
  final int? priceSeeds;
  final String? unlockHint;

  /// 3등급이 예산 2를 쓰는 대신 지는 대가.
  final String? tradeoff;

  bool get isGradeThree => grade == 3;

  /// 획득처를 한 줄로 읽는다. 상점가와 조건을 숨기지 않는다.
  String get acquireLabel => switch (acquireKind) {
        'shop' => '상점 씨앗 $priceSeeds',
        'unlock' => '해금 · ${unlockHint ?? ''}',
        _ => '도전 · ${unlockHint ?? ''}',
      };

  factory SkillBook.fromJson(Map<String, dynamic> json) => SkillBook(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        grade: _asInt(json['grade'], 1),
        activationMode: json['activation_mode'] as String? ?? 'command',
        effectSummary: json['effect_summary'] as String? ?? '',
        stackGroup: json['stack_group'] as String? ?? '',
        minSlot: json['min_slot'] as String? ?? 'B1',
        acquireKind: json['acquire_kind'] as String? ?? 'shop',
        owned: json['owned'] == true,
        combatEffect: json['combat_effect'] == true,
        priceSeeds:
            json['price_seeds'] is num ? _asInt(json['price_seeds']) : null,
        unlockHint: json['unlock_hint'] as String?,
        tradeoff: json['tradeoff'] as String?,
      );
}

/// 한 슬롯이 지금 어떻게 읽히는지.
///
/// 서버는 저장된 값과 해석 결과를 따로 준다. 둘이 다르면 [fellBack]이 참이고
/// [lockReason]이 왜 다른지 설명한다. 조용히 바꿔치지 않기 위한 계약이다.
class SkillSlotState {
  const SkillSlotState({
    required this.slot,
    required this.source,
    required this.code,
    required this.locked,
    required this.fellBack,
    this.lockReason,
    this.bookName,
  });

  final String slot;

  /// `skillbook|emotion|default_book|locked`
  final String source;
  final String? code;
  final bool locked;

  /// 저장한 선택을 쓰지 못하고 기본값으로 내려왔는지.
  final bool fellBack;
  final String? lockReason;
  final String? bookName;

  bool get isBook => source == 'skillbook';

  /// 슬롯에 보여 줄 이름. 감정 포인터와 기본 기록서는 고정 문구를 쓴다.
  String get label => switch (source) {
        'skillbook' => bookName ?? code ?? '기록서',
        'emotion' => code == 'emotion.secondary' ? '보조 성장결' : '성장결 기본',
        'default_book' => '현장 기록',
        _ => '아직 열리지 않음',
      };

  factory SkillSlotState.fromJson(String slot, Map<String, dynamic> json) {
    final book = json['book'];
    return SkillSlotState(
      slot: slot,
      source: json['source'] as String? ?? 'emotion',
      code: json['code'] as String?,
      locked: json['locked'] == true,
      fellBack: json['fell_back'] == true,
      lockReason: json['lock_reason'] as String?,
      bookName: book is Map<String, dynamic> ? book['name'] as String? : null,
    );
  }
}

/// 캐릭터 한 명의 한 프리셋.
class SkillLoadout {
  const SkillLoadout({
    required this.plantId,
    required this.presetCode,
    required this.revision,
    required this.level,
    required this.storedB1,
    required this.storedB2,
    required this.slots,
    required this.slotUnlockLevel,
  });

  final int plantId;
  final String presetCode;

  /// 낙관적 동시성 값. 저장할 때 그대로 돌려보낸다.
  final int revision;
  final int level;
  final String? storedB1;
  final String? storedB2;
  final Map<String, SkillSlotState> slots;
  final Map<String, int> slotUnlockLevel;

  SkillSlotState? slot(String code) => slots[code];

  String? storedFor(String slot) => slot == 'B1' ? storedB1 : storedB2;

  bool isSlotOpen(String slot) => level >= (slotUnlockLevel[slot] ?? 99);

  factory SkillLoadout.fromJson(Map<String, dynamic> json) {
    final stored = json['stored'];
    final resolved = json['resolved'];
    final unlock = json['slot_unlock_level'];
    return SkillLoadout(
      plantId: _asInt(json['plant_id']),
      presetCode: json['preset_code'] as String? ?? 'guard',
      revision: _asInt(json['revision']),
      level: _asInt(json['level'], 1),
      storedB1: stored is Map<String, dynamic>
          ? stored['slot_b1_code'] as String?
          : null,
      storedB2: stored is Map<String, dynamic>
          ? stored['slot_b2_code'] as String?
          : null,
      slots: {
        for (final slot in const ['B1', 'B2'])
          if (resolved is Map<String, dynamic> &&
              resolved[slot] is Map<String, dynamic>)
            slot: SkillSlotState.fromJson(
              slot,
              resolved[slot] as Map<String, dynamic>,
            ),
      },
      slotUnlockLevel: {
        for (final slot in const ['B1', 'B2'])
          if (unlock is Map<String, dynamic> && unlock[slot] is num)
            slot: _asInt(unlock[slot]),
      },
    );
  }
}

/// 서고 화면 한 번에 필요한 것.
class SkillBookLibrary {
  const SkillBookLibrary({required this.catalog, required this.presets});

  final List<SkillBook> catalog;
  final List<String> presets;

  List<SkillBook> get owned =>
      catalog.where((book) => book.owned).toList(growable: false);

  /// 이 슬롯에 실제로 넣을 수 있는 책만 고른다.
  ///
  /// 보유하지 않았거나 등급이 맞지 않는 책은 목록에서 빼지 않고 호출부가
  /// 이유와 함께 흐리게 보여 준다 — 무엇을 모으면 되는지가 목표가 된다.
  bool canEquip(SkillBook book, String slot) =>
      book.owned && (slot == 'B2' || !book.isGradeThree);

  factory SkillBookLibrary.fromJson(Map<String, dynamic> json) {
    final catalog = json['catalog'];
    final presets = json['presets'];
    return SkillBookLibrary(
      catalog: catalog is List
          ? catalog
              .whereType<Map<String, dynamic>>()
              .map(SkillBook.fromJson)
              .toList(growable: false)
          : const [],
      presets: presets is List
          ? presets.whereType<String>().toList(growable: false)
          : const ['explore', 'guard', 'personal'],
    );
  }
}
