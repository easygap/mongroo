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
    this.isActive = true,
    this.retiredReason,
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

  /// 아직 새로 얻을 수 있는 책인가. false면 상점에서 내려간 책이다.
  ///
  /// 서고에서 지우지는 않는다 — 이미 가진 사람에게는 그대로 남아야 하고,
  /// 산 것을 조용히 없애면 왜 사라졌는지 알 길이 없다.
  final bool isActive;

  /// 왜 내렸는지. 서버 문장을 그대로 쓴다.
  final String? retiredReason;

  bool get isGradeThree => grade == 3;

  /// 획득처를 한 줄로 읽는다. 상점가와 조건을 숨기지 않는다.
  ///
  /// 내린 책은 값을 먼저 말하지 않는다. 살 수 없는데 `상점 씨앗 120`이라고
  /// 하면 어디서 사는지 찾아 헤매게 된다.
  String get acquireLabel {
    if (!isActive) return retiredReason ?? '지금은 얻을 수 없어요';
    return switch (acquireKind) {
      'shop' => '상점 씨앗 $priceSeeds',
      'unlock' => '해금 · ${unlockHint ?? ''}',
      _ => '도전 · ${unlockHint ?? ''}',
    };
  }

  factory SkillBook.fromJson(Map<String, dynamic> json) => SkillBook(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        grade: _asInt(json['grade'], 1),
        activationMode: json['activation_mode'] as String? ?? 'command',
        isActive: json['is_active'] != false,
        retiredReason: json['retired_reason'] as String?,
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

/// 아직 없는 책의 조건이 얼마나 찼는지.
///
/// 서버가 세어서 내려 준다. 앱이 다시 세면 판정과 화면이 어긋나고, 무엇보다
/// `수호자 장벽 3종 열기`처럼 가짓수를 묻는 조건은 앱에 셀 근거가 없다.
class SkillBookUnlockProgress {
  const SkillBookUnlockProgress({
    required this.code,
    required this.source,
    required this.current,
    required this.goal,
    required this.owned,
  });

  final String code;

  /// `unlock`이면 조건 달성, `challenge`면 도전 과제다.
  final String source;
  final int current;
  final int goal;
  final bool owned;

  bool get complete => goal > 0 && current >= goal;

  /// 0~1. 목표가 0이면(있을 수 없지만) 0으로 둔다.
  double get ratio => goal <= 0 ? 0 : (current / goal).clamp(0, 1).toDouble();

  factory SkillBookUnlockProgress.fromJson(Map<String, dynamic> json) =>
      SkillBookUnlockProgress(
        code: json['code'] as String? ?? '',
        source: json['source'] as String? ?? 'unlock',
        current: _asInt(json['current']),
        goal: _asInt(json['goal'], 1),
        owned: json['owned'] == true,
      );
}

/// 서고 화면 한 번에 필요한 것.
class SkillBookLibrary {
  const SkillBookLibrary({
    required this.catalog,
    required this.presets,
    this.unlockProgress = const {},
  });

  final List<SkillBook> catalog;
  final List<String> presets;

  /// 책 코드 → 조건 진행도. 조건이 없는 책(상점 구매)은 여기에 없다.
  final Map<String, SkillBookUnlockProgress> unlockProgress;

  /// 이 책의 조건이 얼마나 찼는지. 없으면 `null`이고 화면은 조건 문구만 쓴다.
  SkillBookUnlockProgress? progressFor(String code) => unlockProgress[code];

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
    final progress = json['unlock_progress'];
    return SkillBookLibrary(
      unlockProgress: {
        if (progress is List)
          for (final item in progress.whereType<Map<String, dynamic>>())
            if (item['code'] is String)
              item['code'] as String: SkillBookUnlockProgress.fromJson(item),
      },
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
