import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/text/korean_particles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../home/domain/plant.dart';
import '../../home/presentation/plant_view.dart';
import '../domain/expedition_models.dart';
import 'expedition_combat_effects.dart';
import 'expedition_combat_sprites.dart';
import 'expedition_controller.dart';

/// 스테이지 개편(stage-battle-v2.0)의 순차 명령 카드 독.
///
/// 기존 예약형 지휘 패널을 대체한다. 대원 한 명을 탭하고 카드 한 장을 탭하면
/// 그 행동이 즉시 서버 판정으로 넘어가 연출까지 이어진다. 첫 입력에서 첫
/// 피드백까지 탭 2회라는 개편 문서 4.1의 계약을 이 위젯이 지킨다.
/// false로 내리면 기존 예약형 패널로 되돌아간다(개편 문서 7장의 기능 플래그).
const bool kSequentialCommandDock = true;

const expeditionCombatActionOrder = <String>[
  'attack',
  'unique_1',
  'unique_2',
  'selected_1',
  'selected_2',
  'guard',
];

const expeditionSkillDetailHoldDuration = Duration(milliseconds: 350);

/// AUTO의 두 단계. `보조`는 다음 한 행동만 맡기고 꺼지며, `연속`은 전투가
/// 끝날 때까지 유지된다. 수동 지휘 계약의 보조/연속 구분을 그대로 옮겼다.
enum ExpeditionAutoMode { off, assist, continuous }

class ExpeditionBattleSettings {
  const ExpeditionBattleSettings({
    this.autoMode = ExpeditionAutoMode.off,
    this.pace = 1,
    this.shortEffects = false,
    this.audioEnabled = true,
  });

  final ExpeditionAutoMode autoMode;

  /// 연출 배속(1 또는 2). 판정·프레임 스킵 없이 타임라인만 줄인다.
  final int pace;

  /// 짧은 연출 모드. 시동·여운을 줄이되 판정 정보는 유지한다.
  final bool shortEffects;

  /// 전투 BGM과 효과음을 함께 끈다. 판정 정보는 시각·촉각으로 그대로 남는다.
  final bool audioEnabled;

  ExpeditionBattleSettings copyWith({
    ExpeditionAutoMode? autoMode,
    int? pace,
    bool? shortEffects,
    bool? audioEnabled,
  }) =>
      ExpeditionBattleSettings(
        autoMode: autoMode ?? this.autoMode,
        pace: pace ?? this.pace,
        shortEffects: shortEffects ?? this.shortEffects,
        audioEnabled: audioEnabled ?? this.audioEnabled,
      );
}

class ExpeditionBattleSettingsNotifier
    extends Notifier<ExpeditionBattleSettings> {
  @override
  ExpeditionBattleSettings build() => const ExpeditionBattleSettings();

  void cycleAutoMode() {
    state = state.copyWith(
      autoMode: switch (state.autoMode) {
        ExpeditionAutoMode.off => ExpeditionAutoMode.assist,
        ExpeditionAutoMode.assist => ExpeditionAutoMode.continuous,
        ExpeditionAutoMode.continuous => ExpeditionAutoMode.off,
      },
    );
  }

  void finishAssist() {
    if (state.autoMode == ExpeditionAutoMode.assist) {
      state = state.copyWith(autoMode: ExpeditionAutoMode.off);
    }
  }

  void togglePace() => state = state.copyWith(pace: state.pace == 1 ? 2 : 1);

  void toggleShortEffects() =>
      state = state.copyWith(shortEffects: !state.shortEffects);

  void toggleAudio() =>
      state = state.copyWith(audioEnabled: !state.audioEnabled);
}

/// 전투 표준 장비(AUTO·배속·짧은 연출) 상태. 앱 세션 동안 유지된다.
/// 계정 설정 동기화는 스테이지 개편 S2에서 서버 설정과 함께 붙인다.
final expeditionBattleSettingsProvider = NotifierProvider<
    ExpeditionBattleSettingsNotifier, ExpeditionBattleSettings>(
  ExpeditionBattleSettingsNotifier.new,
);

/// 전투 화면 상단 정보 바 — 라운드 진행과 표준 장비 토글, 긴급 귀환.
class ExpeditionBattleTopBar extends ConsumerWidget {
  const ExpeditionBattleTopBar({
    super.key,
    required this.battle,
    required this.locked,
  });

  final ExpeditionBattle battle;
  final bool locked;

  Future<void> _confirmRetreat(BuildContext context, WidgetRef ref) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지금 긴급 귀환할까요?'),
        content: const Text(
          '수호전에서 물러나면 아직 확정하지 않은 발견물과 보상을 가져갈 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('계속 지휘'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('긴급 귀환'),
          ),
        ],
      ),
    );
    if (leave != true) return;
    HapticFeedback.mediumImpact();
    await ref.read(expeditionControllerProvider.notifier).retreat();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(expeditionBattleSettingsProvider);
    final notifier = ref.read(expeditionBattleSettingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final autoLabel = switch (settings.autoMode) {
      ExpeditionAutoMode.off => 'AUTO',
      ExpeditionAutoMode.assist => 'AUTO·보조',
      ExpeditionAutoMode.continuous => 'AUTO·연속',
    };
    final wave = battle.wave;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          MongrooTag(
            label: 'R ${battle.round}/${battle.maxRounds}',
            icon: Icons.sports_martial_arts_rounded,
            backgroundColor: scheme.errorContainer.withAlpha(130),
          ),
          if (wave != null && wave.count > 1) ...[
            const SizedBox(width: 6),
            Semantics(
              label: '${wave.count}번의 엉킴 중 ${wave.index}번째',
              child: MongrooTag(
                key: const ValueKey('seq-dock-wave'),
                label: '웨이브 ${wave.index}/${wave.count}',
                icon: Icons.blur_on_rounded,
                backgroundColor: scheme.tertiaryContainer.withAlpha(130),
              ),
            ),
          ],
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: '자동 지휘 $autoLabel. 눌러서 끔, 보조, 연속 순서로 바꿔요',
                    child: SizedBox(
                      height: 44,
                      child: FilterChip(
                        key: const ValueKey('seq-dock-auto'),
                        selected: settings.autoMode != ExpeditionAutoMode.off,
                        onSelected: (_) => notifier.cycleAutoMode(),
                        avatar: Icon(
                          settings.autoMode == ExpeditionAutoMode.off
                              ? Icons.touch_app_outlined
                              : Icons.autorenew_rounded,
                          size: 16,
                        ),
                        visualDensity: VisualDensity.compact,
                        label: Text(autoLabel),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Semantics(
                    label: '연출 배속 ${settings.pace}배',
                    child: SizedBox(
                      height: 44,
                      child: FilterChip(
                        key: const ValueKey('seq-dock-pace'),
                        selected: settings.pace == 2,
                        onSelected: (_) => notifier.togglePace(),
                        avatar: const Icon(Icons.speed_rounded, size: 16),
                        visualDensity: VisualDensity.compact,
                        label: Text('${settings.pace}×'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Semantics(
                    label: '짧은 연출 ${settings.shortEffects ? '켜짐' : '꺼짐'}',
                    child: SizedBox(
                      height: 44,
                      child: FilterChip(
                        key: const ValueKey('seq-dock-short'),
                        selected: settings.shortEffects,
                        onSelected: (_) => notifier.toggleShortEffects(),
                        avatar: const Icon(Icons.bolt_outlined, size: 16),
                        visualDensity: VisualDensity.compact,
                        label: const Text('짧은 연출'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Semantics(
                    label: '전투 소리 ${settings.audioEnabled ? '켜짐' : '꺼짐'}',
                    child: SizedBox(
                      height: 44,
                      child: FilterChip(
                        key: const ValueKey('seq-dock-audio'),
                        selected: settings.audioEnabled,
                        onSelected: (_) => notifier.toggleAudio(),
                        avatar: Icon(
                          settings.audioEnabled
                              ? Icons.volume_up_outlined
                              : Icons.volume_off_outlined,
                          size: 16,
                        ),
                        visualDensity: VisualDensity.compact,
                        label: const Text('소리'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('seq-dock-retreat'),
            onPressed: locked ? null : () => _confirmRetreat(context, ref),
            tooltip: '긴급 귀환',
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: const Icon(Icons.directions_run_rounded),
          ),
        ],
      ),
    );
  }
}

/// 순차 명령 카드 독 본체.
class ExpeditionSequentialCommandDock extends ConsumerStatefulWidget {
  const ExpeditionSequentialCommandDock({
    super.key,
    required this.expedition,
    required this.event,
    required this.state,
  });

  final ExpeditionSnapshot expedition;
  final ExpeditionEvent event;
  final ExpeditionUiState state;

  @override
  ConsumerState<ExpeditionSequentialCommandDock> createState() =>
      _ExpeditionSequentialCommandDockState();
}

class _ExpeditionSequentialCommandDockState
    extends ConsumerState<ExpeditionSequentialCommandDock> {
  Timer? _autoTimer;
  int? _selectedMemberId;
  String? _fingerprint;
  bool _submitting = false;
  bool _detailsOpen = false;
  bool _skillIconsPrecached = false;

  ExpeditionBattle get _battle => widget.event.battle!;

  bool get _locked =>
      widget.state.interactionLocked ||
      _submitting ||
      _detailsOpen ||
      !_battle.isActive;

  @override
  void initState() {
    super.initState();
    _fingerprint = _battleFingerprint();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAuto());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_skillIconsPrecached) return;
    _skillIconsPrecached = true;
    for (final asset in _dockSkillIconAssets.values) {
      unawaited(precacheImage(AssetImage(asset), context));
    }
  }

  @override
  void didUpdateWidget(covariant ExpeditionSequentialCommandDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fingerprint = _battleFingerprint();
    if (_fingerprint != fingerprint) {
      _fingerprint = fingerprint;
      _selectedMemberId = null;
      _scheduleAuto();
      return;
    }
    if (oldWidget.state.interactionLocked && !widget.state.interactionLocked) {
      _scheduleAuto();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  String _battleFingerprint() =>
      '${widget.expedition.run.id}:${widget.expedition.run.revision}:'
      '${_battle.round}:${_battle.pendingRound?.acted.join(',') ?? ''}';

  List<ExpeditionBattleMember> get _awaiting => _battle.awaitingParty;

  ExpeditionBattleMember? get _actor {
    final awaiting = _awaiting;
    if (awaiting.isEmpty) return null;
    return awaiting
            .where((member) => member.memberId == _selectedMemberId)
            .firstOrNull ??
        awaiting.first;
  }

  ExpeditionMember? _plantOf(int memberId) => widget.expedition.party
      .where((member) => member.id == memberId)
      .firstOrNull;

  /// 적의 예고 대상. front 의도는 이번 라운드 첫 행동 대원(아직 없으면 지금
  /// 고른 대원)을 노린다는 서버 규칙을 그대로 읽는다.
  Set<int> _targetedMemberIds() {
    final living = _battle.livingParty;
    if (living.isEmpty) return const {};
    return switch (_battle.enemy.intent.target) {
      'all' => living.map((member) => member.memberId).toSet(),
      'lowest' => {
          living.reduce((a, b) {
            if (a.hp != b.hp) return a.hp < b.hp ? a : b;
            return a.memberId < b.memberId ? a : b;
          }).memberId,
        },
      _ => {
          _battle.pendingRound?.acted.firstOrNull ??
              _actor?.memberId ??
              living.first.memberId,
        },
    };
  }

  ExpeditionBattleAction _actionFor(
    ExpeditionBattleMember member,
    String actionCode,
  ) =>
      member.kit.actionFor(actionCode);

  bool _isWeak(ExpeditionBattleAction action) {
    if (_battle.version >= 2 && _battle.enemy.weakKel != null) {
      return action.matchup == 'weak' || action.matchup == 'prism_weak';
    }
    if (_battle.enemy.weakKel case final weakKel?) {
      return action.matchup == 'weak' || action.kels.contains(weakKel);
    }
    if (action.matchup == 'weak') return true;
    final weakElement = _battle.enemy.weakElement;
    if (weakElement != null) {
      return action.elements.contains(weakElement) ||
          action.element == weakElement;
    }
    return action.affinity == _battle.enemy.weakness;
  }

  bool _isResisted(ExpeditionBattleAction action) {
    if (_battle.version >= 2 && _battle.enemy.weakKel != null) {
      return !_isWeak(action) && action.matchup == 'resist';
    }
    if (_battle.enemy.resistKel case final resistKel?) {
      return !_isWeak(action) &&
          (action.matchup == 'resist' || action.kels.contains(resistKel));
    }
    if (action.matchup == 'resist') return true;
    final resistElement = _battle.enemy.resistElement;
    if (resistElement == null || _isWeak(action)) return false;
    return action.elements.contains(resistElement) ||
        action.element == resistElement;
  }

  int _expectedDamage(ExpeditionBattleMember member, String actionCode) {
    if (actionCode == 'guard') return 0;
    final action = _actionFor(member, actionCode);
    if (!action.available) return 0;
    return action.power;
  }

  String? _lockReason(ExpeditionBattleMember member, String actionCode) {
    final action = _actionFor(member, actionCode);
    if (!action.available) return 'Lv.${action.unlockLevel} 해금';
    if (actionCode == 'attack' || actionCode == 'guard') return null;
    if (action.cooldownRemaining > 0) {
      return '재사용 ${action.cooldownRemaining}';
    }
    final cost = action.focusCost;
    return _battle.focus < cost ? '집중 부족' : null;
  }

  String _effectKeyFor(ExpeditionBattleMember member, String actionCode) {
    if (actionCode == 'guard') return 'safe_guard';
    final action = _actionFor(member, actionCode);
    if (action.effectKey case final effectKey?) return effectKey;
    return switch (action.affinity) {
      'care' => 'care_vines',
      'focus' => 'prism_burst',
      'courage' => 'ember_arc',
      'insight' => 'insight_arc',
      _ => 'echo_wave',
    };
  }

  void _selectMember(int memberId) {
    if (_locked) return;
    if (!_awaiting.any((member) => member.memberId == memberId)) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedMemberId = memberId);
    ref.read(expeditionControllerProvider.notifier).selectMember(memberId);
  }

  Future<void> _submit(String actionCode) async {
    final actor = _actor;
    if (actor == null || _locked) return;
    if (_lockReason(actor, actionCode) != null) return;
    _autoTimer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      final accepted = await ref
          .read(expeditionControllerProvider.notifier)
          .resolveCombatAction(
            ExpeditionCombatCommand(
              memberId: actor.memberId,
              action: actionCode,
            ),
          );
      if (accepted) {
        ref.read(expeditionBattleSettingsProvider.notifier).finishAssist();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// AUTO 판단. 현재 공개된 의도·약점·집중력만 읽고 미래 정보를 쓰지 않는다.
  String _autoActionFor(ExpeditionBattleMember member) {
    final targeted = _targetedMemberIds();
    final danger = targeted.contains(member.memberId) &&
        (_battle.enemy.intent.power >= member.hp || member.hp <= 1);
    if (danger) return 'guard';
    final matchingSkills = member.kit.combatSkills
        .where(
          (skill) =>
              skill.available &&
              skill.cooldownRemaining == 0 &&
              _isWeak(skill) &&
              _battle.focus >= skill.focusCost,
        )
        .toList(growable: false)
      ..sort((a, b) => b.power.compareTo(a.power));
    if (matchingSkills.isNotEmpty) {
      return matchingSkills.first.slot;
    }
    return 'attack';
  }

  void _scheduleAuto() {
    _autoTimer?.cancel();
    final autoMode = ref.read(expeditionBattleSettingsProvider).autoMode;
    if (autoMode == ExpeditionAutoMode.off || _locked) return;
    _autoTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || _locked) return;
      final mode = ref.read(expeditionBattleSettingsProvider).autoMode;
      if (mode == ExpeditionAutoMode.off) return;
      final actor = _actor;
      if (actor == null) return;
      var action = _autoActionFor(actor);
      if (_lockReason(actor, action) != null) action = 'attack';
      unawaited(_submit(action));
    });
  }

  Future<void> _showActionDetails(
    ExpeditionBattleMember member,
    String actionCode,
  ) async {
    _autoTimer?.cancel();
    if (mounted) setState(() => _detailsOpen = true);
    final action = _actionFor(member, actionCode);
    final weaknessHit = actionCode != 'guard' && _isWeak(action);
    final resistanceHit = actionCode != 'guard' && _isResisted(action);
    final coefficient = action.powerScaleBp / 100;
    final coefficientLabel = coefficient == coefficient.roundToDouble()
        ? coefficient.toStringAsFixed(0)
        : coefficient.toStringAsFixed(1);
    final tierCoefficient = action.tierPowerBp / 100;
    final matchupCoefficient = action.matchupBp / 100;
    final matchupMultiplier = (action.matchupBp / 10000).toStringAsFixed(2);
    final matchupAdjustment =
        _battle.version >= 2 && _battle.enemy.weakKel != null
            ? '×$matchupMultiplier'
            : weaknessHit
                ? '+7'
                : '−4';
    String matchupLabel(String label) {
      if (resistanceHit) return '↓ $label · 내성 $matchupAdjustment';
      if (weaknessHit) return '↑ $label · 약점 $matchupAdjustment';
      return label;
    }

    final metadata = switch (actionCode) {
      'guard' => '방어 +${action.guard} · 집중 +${action.focusDelta}',
      'attack' => '위력 ${action.power} · 집중 +${action.focusDelta}',
      _ => action.available
          ? '위력 ${action.power} · 집중 -${action.focusCost} · '
              '재사용 ${action.cooldownTurns}턴'
          : '현재 서버에서는 사용할 수 없어요',
    };
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .4,
        ),
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DockActionVisual(
                      action: action,
                      actionCode: actionCode,
                      effectKey: _effectKeyFor(member, actionCode),
                      color: _dockActionColor(context, actionCode),
                      size: 64,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            metadata,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(action.description),
                if (actionCode != 'guard') ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (action.tierLabel.isNotEmpty)
                        MongrooTag(
                          label: 'T${action.tier} · ${action.tierLabel}',
                          icon: Icons.auto_awesome_rounded,
                        ),
                      if (action.elementLabel case final label?)
                        MongrooTag(
                          label: action.kelLabels.isEmpty
                              ? matchupLabel(label)
                              : label,
                          icon: _dockElementIcon(action.element ?? ''),
                          backgroundColor:
                              _dockElementColor(context, action.element ?? '')
                                  .withAlpha(42),
                        ),
                      if (action.damageTypeLabel case final label?)
                        MongrooTag(
                          label: label,
                          icon: Icons.sports_martial_arts_rounded,
                        ),
                      if (action.rawPower > 0)
                        MongrooTag(
                          label: '계수 $coefficientLabel%',
                          icon: Icons.trending_up_rounded,
                        ),
                      if (action.rawPower > 0)
                        MongrooTag(
                          label:
                              '단계 ${tierCoefficient.toStringAsFixed(0)}% · 상성 ${matchupCoefficient.toStringAsFixed(0)}%',
                          icon: Icons.calculate_outlined,
                        ),
                      if (action.kelLabels.isNotEmpty)
                        MongrooTag(
                          label: matchupLabel(action.kelLabels.join(' · ')),
                          icon: Icons.hub_outlined,
                        ),
                      if (action.fusionVariant != null)
                        const MongrooTag(
                          label: 'T3 감정 융합',
                          icon: Icons.layers_rounded,
                        ),
                    ],
                  ),
                  if (action.vfxFamily != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      action.fusionVfxFamily == null
                          ? '연출 · 전용 모션과 스프라이트 VFX 계열 적용'
                          : '연출 · 캐릭터 고유 VFX 위에 성장결 융합 레이어 적용',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ],
                if (action.source case final source?) ...[
                  const SizedBox(height: 10),
                  Text(
                    switch (source) {
                      'signature' => '출처 · 캐릭터 고유',
                      'emotion' => '출처 · 현재 성장결',
                      'skillbook' => '출처 · 스킬북',
                      _ => '출처 · $source',
                    },
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
                if (action.affinityLabel != null &&
                    action.elementLabel == null) ...[
                  const SizedBox(height: 12),
                  MongrooTag(
                    label: weaknessHit
                        ? '${action.affinityLabel} · 약점 일치 ×1.50'
                        : action.affinityLabel!,
                    icon: _dockAffinityIcon(action.affinity ?? ''),
                    backgroundColor:
                        _dockAffinityColor(context, action.affinity ?? '')
                            .withAlpha(42),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _detailsOpen = false);
        _scheduleAuto();
      }
    }
  }

  Future<void> _showBattleDiscovery() async {
    final enemy = _battle.enemy;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(enemy.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _DiscoverySheetLine(
                icon: enemy.weakElement != null
                    ? _dockElementIcon(enemy.weakElement!)
                    : _dockAffinityIcon(enemy.weakness),
                title: '확인한 약점',
                value: enemy.weakKelLabel ??
                    enemy.weakElementLabel ??
                    enemy.weaknessLabel,
              ),
              if (enemy.resistKelLabel ?? enemy.resistElementLabel
                  case final resistance?)
                _DiscoverySheetLine(
                  icon: _dockElementIcon(enemy.resistElement ?? ''),
                  title: '확인한 내성',
                  value: resistance,
                ),
              _DiscoverySheetLine(
                icon: Icons.visibility_outlined,
                title: '다음 행동',
                value:
                    '${enemy.intent.name} · ${enemy.intent.targetLabel} · 위력 ${enemy.intent.power}',
              ),
              const Divider(height: 24),
              const _DiscoverySheetLine(
                icon: Icons.menu_book_outlined,
                title: '상세 생태 기록',
                value: '??? · 전투 후 도감에서 공개',
                locked: true,
              ),
              const _DiscoverySheetLine(
                icon: Icons.redeem_outlined,
                title: '숨은 보상',
                value: '??? · 실제 발견 후 공개',
                locked: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final battle = _battle;
    final actor = _actor;
    final scheme = Theme.of(context).colorScheme;
    final targeted = _targetedMemberIds();
    final locked = _locked;
    final prompt = locked || actor == null
        ? '수호전이 진행되고 있어요…'
        : '${koreanTopic(actor.name)} 무엇을 할까요?';
    Widget promptLine() => Semantics(
          liveRegion: true,
          child: Text(
            prompt,
            key: const ValueKey('seq-dock-prompt'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        );

    return MongrooPanel(
      key: const ValueKey('seq-command-dock'),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      radius: 16,
      color: scheme.surface.withAlpha(238),
      borderColor: scheme.error.withAlpha(85),
      shadowOffset: const Offset(0, -3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IntentLine(
            battle: battle,
            onTap: _showBattleDiscovery,
          ),
          const SizedBox(height: 7),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(1) >= 1.5;
              final beads = _FocusBeads(
                focus: battle.focus,
                maxFocus: battle.maxFocus,
              );
              final chips = Row(
                children: [
                  for (final member in battle.party) ...[
                    if (member.memberId != battle.party.first.memberId)
                      const SizedBox(width: 6),
                    Expanded(
                      child: _DockMemberChip(
                        key: ValueKey('seq-member-${member.memberId}'),
                        member: member,
                        plant: _plantOf(member.memberId),
                        isActor: !locked && member.memberId == actor?.memberId,
                        acted: battle.hasActed(member.memberId),
                        awaiting: _awaiting.any(
                          (item) => item.memberId == member.memberId,
                        ),
                        targeted: targeted.contains(member.memberId),
                        targetKind: battle.enemy.intent.target,
                        onTap: locked
                            ? null
                            : () => _selectMember(member.memberId),
                      ),
                    ),
                  ],
                ],
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    beads,
                    const SizedBox(height: 7),
                    chips,
                    const SizedBox(height: 8),
                    promptLine(),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: promptLine()),
                      const SizedBox(width: 8),
                      beads,
                    ],
                  ),
                  const SizedBox(height: 6),
                  chips,
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          if (actor != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final wrap = constraints.maxWidth < 340 ||
                    MediaQuery.textScalerOf(context).scale(1) >= 1.5;
                final cards = [
                  for (final actionCode in expeditionCombatActionOrder)
                    _DockActionCard(
                      key: ValueKey('seq-dock-card-$actionCode'),
                      action: _actionFor(actor, actionCode),
                      actionCode: actionCode,
                      effectKey: _effectKeyFor(actor, actionCode),
                      weakness: actionCode != 'guard' &&
                          _isWeak(_actionFor(actor, actionCode)),
                      resistance: actionCode != 'guard' &&
                          _isResisted(_actionFor(actor, actionCode)),
                      expectedDamage: _expectedDamage(actor, actionCode),
                      lockReason: _lockReason(actor, actionCode),
                      enabled:
                          !locked && _lockReason(actor, actionCode) == null,
                      onPressed: () => unawaited(_submit(actionCode)),
                      onLongPress: () =>
                          unawaited(_showActionDetails(actor, actionCode)),
                    ),
                ];
                if (wrap) {
                  return GridView.count(
                    key: const ValueKey('seq-dock-action-grid'),
                    crossAxisCount: 3,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 1.65,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: cards,
                  );
                }
                return Row(
                  key: const ValueKey('seq-dock-action-row'),
                  children: [
                    for (var index = 0; index < cards.length; index++) ...[
                      if (index > 0) const SizedBox(width: 6),
                      Expanded(child: cards[index]),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// 적 의도와 약점을 한 줄로 읽는 안내선. 확정 전에 항상 공개하며,
/// 누르면 발견 정보 시트가 열린다.
class _IntentLine extends StatelessWidget {
  const _IntentLine({required this.battle, required this.onTap});

  final ExpeditionBattle battle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final intent = battle.enemy.intent;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final weakLabel = battle.enemy.weakKelLabel ??
        battle.enemy.weakElementLabel ??
        battle.enemy.weaknessLabel;
    final resistLabel =
        battle.enemy.resistKelLabel ?? battle.enemy.resistElementLabel;
    final matchupTag = MongrooTag(
      label:
          resistLabel == null ? '↑ $weakLabel' : '↑ $weakLabel  ↓ $resistLabel',
      icon: _dockElementIcon(
        battle.enemy.weakElement ?? battle.enemy.weakness,
      ),
      backgroundColor: _dockElementColor(
        context,
        battle.enemy.weakElement ?? battle.enemy.weakness,
      ).withAlpha(38),
      maxWidth: textScale >= 1.5 ? 180 : null,
    );
    final intentSummary = Row(
      children: [
        Icon(
          expeditionIntentTargetIcon(intent.target),
          size: 17,
          color: scheme.error,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${intent.name} · ${intent.targetLabel} · 위력 ${intent.power}',
            maxLines: textScale >= 1.35 ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      label: '적 의도 ${intent.name}, ${intent.targetLabel}, 위력 ${intent.power}. '
          '약점 $weakLabel${resistLabel == null ? '' : ', 내성 $resistLabel'}. '
          '눌러서 발견 정보 보기',
      child: Material(
        color: scheme.errorContainer.withAlpha(74),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('seq-dock-intent'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            child: textScale >= 1.5
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      intentSummary,
                      const SizedBox(height: 5),
                      Align(alignment: Alignment.centerLeft, child: matchupTag),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: intentSummary),
                      const SizedBox(width: 6),
                      matchupTag,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _DiscoverySheetLine extends StatelessWidget {
  const _DiscoverySheetLine({
    required this.icon,
    required this.title,
    required this.value,
    this.locked = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool locked;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              locked ? Icons.lock_outline_rounded : icon,
              size: 21,
              color: locked
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// 공유 집중력 구슬. 전투 중 상시 노출하는 자원은 HP와 이것 둘뿐이다.
class _FocusBeads extends StatelessWidget {
  const _FocusBeads({required this.focus, required this.maxFocus});

  final int focus;
  final int maxFocus;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '공유 집중력 $focus/$maxFocus',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 17, color: palette.butter),
          const SizedBox(width: 4),
          for (var index = 0; index < maxFocus; index++)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index < focus
                      ? palette.butter
                      : scheme.outlineVariant.withAlpha(90),
                  border: Border.all(
                    color:
                        index < focus ? palette.butter : scheme.outlineVariant,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 3),
          Text(
            '$focus/$maxFocus',
            textScaler: TextScaler.noScaling,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _DockMemberChip extends StatelessWidget {
  const _DockMemberChip({
    super.key,
    required this.member,
    required this.plant,
    required this.isActor,
    required this.acted,
    required this.awaiting,
    required this.targeted,
    required this.targetKind,
    required this.onTap,
  });

  final ExpeditionBattleMember member;
  final ExpeditionMember? plant;
  final bool isActor;
  final bool acted;
  final bool awaiting;
  final bool targeted;
  final String targetKind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hp =
        member.maxHp <= 0 ? 0.0 : (member.hp / member.maxHp).clamp(0.0, 1.0);
    final down = !member.isAlive;
    final statusLabel = down
        ? '지쳐서 물러남'
        : acted
            ? '행동 완료'
            : isActor
                ? '지금 차례'
                : '대기';
    return Semantics(
      selected: isActor,
      button: onTap != null && awaiting,
      label:
          '${member.name}, 체력 ${member.hp}/${member.maxHp}, $statusLabel${targeted ? ', 적의 다음 공격 대상' : ''}',
      child: Opacity(
        opacity: down
            ? .55
            : acted
                ? .72
                : 1,
        child: Material(
          color: isActor ? scheme.primaryContainer : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: targeted
                  ? scheme.error
                  : isActor
                      ? scheme.primary
                      : scheme.outlineVariant,
              width: isActor || targeted ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: awaiting ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (plant case final plant?)
                        SizedBox(
                          width: 26,
                          child: PlantView(
                            stage: plant.stage,
                            form: PlantGrowthForm.fromCode(plant.form),
                            speciesCode: plant.speciesCode,
                            speciesName: plant.speciesName,
                            spritePose: PlantSpritePose.idle,
                            outfitKey: plant.outfitKey,
                            width: 26,
                            height: 38,
                          ),
                        ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (targeted)
                        Icon(
                          expeditionIntentTargetIcon(targetKind),
                          size: 13,
                          color: scheme.error,
                        )
                      else if (acted)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: scheme.primary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: hp,
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(99),
                          color:
                              hp > .35 ? const Color(0xFF69B77B) : scheme.error,
                        ),
                      ),
                      if (member.guard > 0) ...[
                        const SizedBox(width: 3),
                        Icon(
                          Icons.shield_rounded,
                          size: 12,
                          color: scheme.primary,
                        ),
                        Text(
                          '${member.guard}',
                          textScaler: TextScaler.noScaling,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockActionCard extends StatefulWidget {
  const _DockActionCard({
    super.key,
    required this.action,
    required this.actionCode,
    required this.effectKey,
    required this.weakness,
    required this.resistance,
    required this.expectedDamage,
    required this.lockReason,
    required this.enabled,
    required this.onPressed,
    required this.onLongPress,
  });

  final ExpeditionBattleAction action;
  final String actionCode;
  final String effectKey;
  final bool weakness;
  final bool resistance;
  final int expectedDamage;
  final String? lockReason;
  final bool enabled;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;

  @override
  State<_DockActionCard> createState() => _DockActionCardState();
}

class _DockActionCardState extends State<_DockActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _dockActionColor(context, widget.actionCode);
    final line = widget.lockReason ??
        switch (widget.actionCode) {
          'guard' =>
            '방어 +${widget.action.guard} · 집중 +${widget.action.focusDelta}',
          'attack' => widget.weakness
              ? '예상 ${widget.expectedDamage} · 약점'
              : widget.resistance
                  ? '예상 ${widget.expectedDamage} · 내성'
                  : '예상 ${widget.expectedDamage} · 집중 +${widget.action.focusDelta}',
          _ => widget.weakness
              ? '예상 ${widget.expectedDamage} · 약점'
              : widget.resistance
                  ? '예상 ${widget.expectedDamage} · 내성'
                  : '예상 ${widget.expectedDamage} · 집중 -${widget.action.focusCost}',
        };
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: '${widget.action.name}, $line. 탭하면 실행해요. 길게 누르면 상세 보기',
      customSemanticsActions: {
        CustomSemanticsAction(label: '상세 보기'): widget.onLongPress,
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
              duration: expeditionSkillDetailHoldDuration,
            ),
            (recognizer) {
              recognizer.onLongPress = widget.onLongPress;
            },
          ),
        },
        child: AnimatedScale(
          scale: widget.enabled && _pressed ? .96 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: Material(
            color: widget.lockReason != null
                ? scheme.surfaceContainerHighest.withAlpha(210)
                : scheme.surface.withAlpha(238),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: widget.weakness && widget.lockReason == null
                    ? scheme.error
                    : widget.resistance && widget.lockReason == null
                        ? scheme.outline
                        : scheme.outlineVariant,
                width: (widget.weakness || widget.resistance) &&
                        widget.lockReason == null
                    ? 1.8
                    : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.enabled ? widget.onPressed : null,
              onHighlightChanged: widget.enabled
                  ? (value) => setState(() => _pressed = value)
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 58,
                ),
                child: Opacity(
                  opacity: widget.lockReason != null ? .58 : 1,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ExcludeSemantics(
                        child: _DockActionVisual(
                          action: widget.action,
                          actionCode: widget.actionCode,
                          effectKey: widget.effectKey,
                          color: color,
                        ),
                      ),
                      if (widget.actionCode != 'attack' &&
                          widget.actionCode != 'guard' &&
                          widget.action.focusCost > 0)
                        Positioned(
                          top: 3,
                          left: 3,
                          child: _DockActionBadge(
                            icon: Icons.bolt_rounded,
                            label: '${widget.action.focusCost}',
                            color: color,
                          ),
                        ),
                      if (widget.weakness && widget.lockReason == null)
                        Positioned(
                          top: 3,
                          right: 3,
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 17,
                            color: scheme.error,
                          ),
                        )
                      else if (widget.resistance && widget.lockReason == null)
                        Positioned(
                          top: 3,
                          right: 3,
                          child: Icon(
                            Icons.arrow_downward_rounded,
                            size: 17,
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else if (widget.lockReason != null)
                        Positioned(
                          top: 3,
                          right: 3,
                          child: widget.action.cooldownRemaining > 0
                              ? _DockActionBadge(
                                  icon: Icons.timer_outlined,
                                  label: '${widget.action.cooldownRemaining}',
                                  color: scheme.onSurfaceVariant,
                                )
                              : Icon(
                                  Icons.lock_outline_rounded,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                        ),
                      if (widget.lockReason != null)
                        Positioned(
                          left: 2,
                          right: 2,
                          bottom: 2,
                          child: Text(
                            widget.lockReason!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            textScaler: TextScaler.noScaling,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(fontSize: 8, height: 1),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockActionVisual extends StatelessWidget {
  const _DockActionVisual({
    required this.action,
    required this.actionCode,
    required this.effectKey,
    required this.color,
    this.size = 44,
  });

  final ExpeditionBattleAction action;
  final String actionCode;
  final String effectKey;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (actionCode == 'attack' || actionCode == 'guard') {
      return Icon(
        actionCode == 'guard'
            ? Icons.shield_outlined
            : Icons.sports_martial_arts_rounded,
        size: size * .68,
        color: color,
      );
    }
    if (_dockSkillIconAssets[action.code] case final asset?) {
      return SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * .25),
            border: Border.all(color: Colors.white.withAlpha(34)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * .25 - 1),
            child: Image.asset(
              asset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
          ),
        ),
      );
    }
    return _DockEffectThumbnail(effectKey: effectKey, size: size);
  }
}

class _DockActionBadge extends StatelessWidget {
  const _DockActionBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withAlpha(235),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(color: color.withAlpha(70), blurRadius: 3),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 9, color: color),
              Text(
                label,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
}

class _DockEffectThumbnail extends StatelessWidget {
  const _DockEffectThumbnail({required this.effectKey, required this.size});

  final String effectKey;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * .28),
          child: ColoredBox(
            color: expeditionCombatEffectColor(effectKey).withAlpha(24),
            child: Image.asset(
              expeditionCombatEffectAsset(effectKey, 6),
              fit: BoxFit.cover,
              alignment: effectKey == 'safe_guard'
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              excludeFromSemantics: true,
            ),
          ),
        ),
      );
}

Color _dockActionColor(BuildContext context, String action) {
  final scheme = Theme.of(context).colorScheme;
  return switch (action) {
    'unique_1' || 'unique_2' => scheme.secondary,
    'selected_1' || 'selected_2' => scheme.tertiary,
    'guard' => scheme.primary,
    _ => scheme.error,
  };
}

const _dockSkillIconAssets = <String, String>{
  'sprout_cheer': 'assets/adventure/skill-icons/baby-pot/sprout-cheer-v1.webp',
  'root_embrace': 'assets/adventure/skill-icons/baby-pot/root-embrace-v1.webp',
  'sunny_warmth_share':
      'assets/adventure/skill-icons/baby-pot/sunny-warmth-share-v1.webp',
  'field_note_echo':
      'assets/adventure/skill-icons/baby-pot/field-note-echo-v1.webp',
  'heart_moon_charm':
      'assets/adventure/skill-icons/gumiho-pot/heart-moon-charm-v1.webp',
  'nine_tail_eclipse':
      'assets/adventure/skill-icons/gumiho-pot/nine-tail-eclipse-v1.webp',
  'venom_seam': 'assets/adventure/skill-icons/ninja-pot/venom-seam-v1.webp',
  'shadow_execution':
      'assets/adventure/skill-icons/ninja-pot/shadow-execution-v1.webp',
};

Color _dockAffinityColor(BuildContext context, String affinity) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  return switch (affinity) {
    'care' => scheme.tertiary,
    'focus' => theme.brightness == Brightness.dark
        ? const Color(0xFF91C9FF)
        : const Color(0xFF25608A),
    'courage' => scheme.error,
    _ => scheme.secondary,
  };
}

Color _dockElementColor(BuildContext context, String element) {
  return switch (element) {
    'fire' || 'strike' => const Color(0xFFD9553F),
    'water' || 'ice' => const Color(0xFF3F7FBF),
    'wind' => const Color(0xFF43A58D),
    'lightning' => const Color(0xFFE1AD32),
    'light' || 'heart' => const Color(0xFFD66591),
    'steel' || 'force' => const Color(0xFF667585),
    'poison' => const Color(0xFF7B4AA8),
    'shadow' || 'moon' => const Color(0xFF625A9C),
    'nature' => const Color(0xFF4E8A55),
    _ => _dockAffinityColor(context, element).withAlpha(230),
  };
}

IconData _dockElementIcon(String element) => switch (element) {
      'fire' => Icons.local_fire_department_rounded,
      'strike' => Icons.sports_martial_arts_rounded,
      'water' => Icons.water_drop_outlined,
      'ice' => Icons.ac_unit_rounded,
      'wind' => Icons.air_rounded,
      'lightning' => Icons.bolt_rounded,
      'light' => Icons.wb_sunny_outlined,
      'heart' => Icons.favorite_rounded,
      'steel' => Icons.shield_outlined,
      'force' => Icons.blur_circular_rounded,
      'poison' => Icons.science_outlined,
      'shadow' => Icons.brightness_2_outlined,
      'moon' => Icons.nightlight_round,
      'nature' => Icons.eco_outlined,
      _ => _dockAffinityIcon(element),
    };

IconData _dockAffinityIcon(String affinity) => switch (affinity) {
      'care' => Icons.favorite_outline_rounded,
      'focus' => Icons.center_focus_strong_rounded,
      'courage' => Icons.local_fire_department_outlined,
      _ => Icons.visibility_outlined,
    };
