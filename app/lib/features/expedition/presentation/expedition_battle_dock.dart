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
import 'expedition_combat_audio.dart';
import 'expedition_combat_effects.dart';
import 'expedition_combat_sprites.dart';
import 'expedition_controller.dart';
import 'expedition_settings.dart';

// 소리·배속 설정은 전투 밖에서도 바꿀 수 있어야 해 별도 파일로 옮겼다.
// 독을 통해 쓰던 자리는 그대로 두려고 여기서 다시 내보낸다.
export 'expedition_settings.dart';

/// 스테이지 개편(stage-battle-v2.0)의 순차 명령 카드 독.
///
/// 기존 예약형 지휘 패널을 대체한다. 대원 한 명을 탭하고 카드 한 장을 탭하면
/// 그 행동이 즉시 서버 판정으로 넘어가 연출까지 이어진다. 첫 입력에서 첫
/// 피드백까지 탭 2회라는 개편 문서 4.1의 계약을 이 위젯이 지킨다.

const expeditionCombatActionOrder = <String>[
  'attack',
  'unique_1',
  'unique_2',
  'selected_1',
  'selected_2',
  'guard',
];

const expeditionSkillDetailHoldDuration = Duration(milliseconds: 350);


/// 전투 화면 상단 정보 바 — 라운드 진행과 표준 장비 토글, 긴급 귀환.
class ExpeditionBattleTopBar extends ConsumerWidget {
  const ExpeditionBattleTopBar({
    super.key,
    required this.battle,
    required this.locked,
  });

  final ExpeditionBattle battle;
  final bool locked;

  /// 상태 태그와 조작이 한 줄에 같이 들어가는 최소 폭.
  ///
  /// 실측 폭의 합이다 - R 태그 96, 보스 태그 182, AUTO·연속 148, 버튼 48+48에
  /// 사이 여백까지 546. 그 아래에서는 조작을 아랫줄로 내린다.
  static const double oneLineWidth = 560;

  /// 한 줄일 때의 높이.
  static const double lineHeight = 48;

  /// 두 줄이 될 때 늘어나는 높이 - 상태 줄 34에 사이 여백 4.
  static const double compactExtraHeight = 38;

  /// 주어진 폭에서 이 바가 실제로 차지하는 높이.
  ///
  /// 무대 위에 겹쳐 놓는 장벽 HUD가 이 값만큼 내려가야 한다.
  static double heightFor(double width) =>
      width >= oneLineWidth ? lineHeight : lineHeight + compactExtraHeight;

  Future<void> _confirmRetreat(BuildContext context, WidgetRef ref) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지금 긴급 귀환할까요?'),
        content: const Text(
          '지금 물러나면 아직 확정하지 않은 발견물과 보상을 가져갈 수 없어요.',
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

  Future<void> _openSettings(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => const _BattleSettingsSheet(),
      );

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
    final bossPhase = battle.bossPhase;
    final threat = battle.threat;

    // 상태 태그는 남는 폭을 나눠 쓰고 넘치면 말줄임한다. 조작을 밀어내면
    // 안 되는 쪽은 태그가 아니라 버튼이다.
    final statusTags = <Widget>[
      MongrooTag(
        label: 'R ${battle.round}/${battle.maxRounds}',
        icon: Icons.sports_martial_arts_rounded,
        backgroundColor: scheme.errorContainer.withAlpha(130),
      ),
      if (wave != null && wave.count > 1) ...[
        const SizedBox(width: 6),
        Flexible(
          child: Semantics(
            label: '${wave.count}번의 엉킴 중 ${wave.index}번째',
            child: MongrooTag(
              key: const ValueKey('seq-dock-wave'),
              // 바로 위 시맨틱스가 이미 `엉킴`이라고 읽어 준다. 눈에 보이는
              // 쪽만 `웨이브`였다 - 설계 문서 말이지 화면 말이 아니다.
              label: '엉킴 ${wave.index}/${wave.count}',
              icon: Icons.blur_on_rounded,
              backgroundColor: scheme.tertiaryContainer.withAlpha(130),
              maxWidth: 140,
            ),
          ),
        ),
      ],
      if (bossPhase != null) ...[
        const SizedBox(width: 6),
        Flexible(
          child: Semantics(
            liveRegion: true,
            label:
                '${bossPhase.count}단계 보스 중 ${bossPhase.index}단계 ${bossPhase.name}',
            child: MongrooTag(
              key: const ValueKey('seq-dock-boss-phase'),
              label: 'P${bossPhase.index}/${bossPhase.count} · ${bossPhase.name}',
              icon: bossPhase.isFinal
                  ? Icons.warning_amber_rounded
                  : Icons.change_circle_outlined,
              backgroundColor: bossPhase.isFinal
                  ? scheme.errorContainer.withAlpha(160)
                  : scheme.secondaryContainer.withAlpha(140),
              maxWidth: 220,
            ),
          ),
        ),
      ],
      if (threat != null && threat.tier > 0 && bossPhase == null) ...[
        const SizedBox(width: 6),
        Flexible(
          child: Semantics(
            label:
                '위협 ${threat.tier}단계 ${threat.name}, 권장 레벨 ${threat.recommendedLevel}',
            child: MongrooTag(
              key: const ValueKey('seq-dock-threat'),
              label: '위협 ${threat.tier} · ${threat.name}',
              icon: Icons.shield_moon_outlined,
              backgroundColor: scheme.tertiaryContainer.withAlpha(130),
              maxWidth: 220,
            ),
          ),
        ),
      ],
    ];

    // AUTO만 전장에 남긴다. 매 턴 고쳐 잡는 지휘 판단이라 한 번에 닿아야 한다.
    final autoChip = Semantics(
      label: '자동 지휘 $autoLabel. 눌러서 끔, 보조, 연속 순서로 바꿔요',
      child: SizedBox(
        // 옆의 설정·후퇴 아이콘 버튼은 48이다. 이 칩만 44라서 Android 핵심 앱
        // 품질 지침의 48dp에 못 미쳤다 - 매 턴 고쳐 잡는 지휘 판단이라 가장
        // 자주 눌리는 자리다. 줄 높이는 이미 48이라 배치는 그대로다.
        height: 48,
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
    );
    final settingsButton = Semantics(
      label: '전투 설정. 배속 ${settings.pace}배, '
          '짧은 연출 ${settings.shortEffects ? '켜짐' : '꺼짐'}, '
          '소리 ${settings.audioLabel}',
      child: IconButton(
        key: const ValueKey('seq-dock-settings'),
        onPressed: () => _openSettings(context),
        tooltip: '전투 설정',
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        icon: const Icon(Icons.tune_rounded),
      ),
    );
    final retreatButton = IconButton(
      key: const ValueKey('seq-dock-retreat'),
      onPressed: locked ? null : () => _confirmRetreat(context, ref),
      tooltip: '긴급 귀환',
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: const Icon(Icons.directions_run_rounded),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= oneLineWidth) {
          return SizedBox(
            height: lineHeight,
            child: Row(
              children: [
                Expanded(child: Row(children: statusTags)),
                const SizedBox(width: 6),
                autoChip,
                const SizedBox(width: 6),
                settingsButton,
                retreatButton,
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: compactExtraHeight - 4,
              child: Row(children: statusTags),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: lineHeight,
              child: Row(
                children: [
                  autoChip,
                  const SizedBox(width: 6),
                  settingsButton,
                  const Spacer(),
                  retreatButton,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 배속·짧은 연출·소리를 모아 놓은 전투 설정 시트.
///
/// 예전에는 이 셋이 AUTO와 함께 상단 바의 가로 스크롤 안에 있었다. 390px에서
/// 그 스크롤에 주어지는 폭이 70px 남짓이라 네 칩(456px) 중 마지막 하나만
/// 보였고, `reverse: true`라 정작 제일 자주 쓰는 AUTO가 제일 깊이 숨었다.
/// 스크롤이 있다는 표시도 없었다.
class _BattleSettingsSheet extends ConsumerWidget {
  const _BattleSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(expeditionBattleSettingsProvider);
    final notifier = ref.read(expeditionBattleSettingsProvider.notifier);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('전투 설정', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '어느 설정에서도 판정과 결과는 그대로예요.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            _BattleSettingRow(
              itemKey: const ValueKey('seq-dock-pace'),
              icon: Icons.speed_rounded,
              title: '연출 배속',
              description: '판정과 프레임은 건너뛰지 않고 타임라인만 줄여요.',
              value: '${settings.pace}배',
              semanticsLabel: '연출 배속 ${settings.pace}배, 눌러서 바꿔요',
              onTap: notifier.togglePace,
            ),
            _BattleSettingRow(
              itemKey: const ValueKey('seq-dock-short'),
              icon: Icons.bolt_outlined,
              title: '짧은 연출',
              description: '시동과 여운을 줄이되 판정 정보는 그대로 보여 줘요.',
              value: settings.shortEffects ? '켜짐' : '꺼짐',
              semanticsLabel:
                  '짧은 연출 ${settings.shortEffects ? '켜짐' : '꺼짐'}, 눌러서 바꿔요',
              onTap: notifier.toggleShortEffects,
            ),
            _BattleSettingRow(
              itemKey: const ValueKey('seq-dock-audio'),
              icon: switch (settings.audioMode) {
                ExpeditionAudioMode.all => Icons.volume_up_outlined,
                ExpeditionAudioMode.sfxOnly => Icons.music_off_outlined,
                ExpeditionAudioMode.muted => Icons.volume_off_outlined,
              },
              title: '탐험 소리',
              description: '전투뿐 아니라 걸을 때와 모험 탭에도 함께 적용돼요.',
              value: settings.audioLabel,
              semanticsLabel: '탐험 소리 ${settings.audioLabel}, 눌러서 다음 단계',
              onTap: notifier.cycleAudioMode,
            ),
          ],
        ),
      ),
    );
  }
}

class _BattleSettingRow extends StatelessWidget {
  const _BattleSettingRow({
    required this.itemKey,
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.semanticsLabel,
    required this.onTap,
  });

  final Key itemKey;
  final IconData icon;
  final String title;
  final String description;
  final String value;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: ListTile(
          key: itemKey,
          onTap: onTap,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(description),
          trailing: MongrooTag(label: value),
        ),
      ),
    );
  }
}

/// 순차 명령 카드 독 본체.
/// 순차 명령 독. 무엇을 지휘하는지는 호출부가 정한다.
///
/// 스테이지 수호전과 합동 수호전이 같은 여섯 슬롯을 쓴다. 화면마다 사본을
/// 만들면 비용·잠금·상성 표시가 조용히 갈라지므로, 필요한 것만 받아서
/// 두 화면이 같은 독을 쓴다.
class ExpeditionSequentialCommandDock extends ConsumerStatefulWidget {
  const ExpeditionSequentialCommandDock({
    super.key,
    required this.battle,
    required this.members,
    required this.locked,
    required this.fingerprintSeed,
    required this.selectedMemberId,
    required this.onSelectMember,
    required this.onSubmit,
  });

  final ExpeditionBattle battle;

  /// 슬롯이 이름과 스프라이트를 읽는 대원 목록.
  final List<ExpeditionMember> members;

  /// 지금 명령을 받을 수 없는 상태인가. 연출 중이거나 판이 끝났을 때 참이다.
  final bool locked;

  /// 이 값이 바뀌면 고른 대원을 비우고 AUTO를 다시 건다. run과 라운드처럼
  /// `다른 판이 되었다`를 뜻하는 값을 넣는다.
  final String fingerprintSeed;

  final int? selectedMemberId;
  final void Function(int memberId) onSelectMember;
  final Future<bool> Function(ExpeditionCombatCommand command) onSubmit;

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

  ExpeditionBattle get _battle => widget.battle;

  bool get _locked =>
      widget.locked ||
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
    // 지금 이 전투에 나오는 아이콘만 올린다. 지도 전체를 올리면 대원 셋이
    // 최대 열두 칸을 쓰는 자리를 위해 마흔 장을 디코드하게 되고, 품종이나
    // 성장결이 늘 때마다 그 값이 조용히 커진다.
    final assets = <String>{
      for (final member in _battle.party)
        for (final action in member.kit.combatSkills)
          if (_dockSkillIconAssets[action.code] case final asset?) asset,
    };
    for (final asset in assets) {
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
    if (oldWidget.locked && !widget.locked) {
      _scheduleAuto();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  String _battleFingerprint() =>
      '${widget.fingerprintSeed}:'
      '${_battle.round}:${_battle.pendingRound?.acted.join(',') ?? ''}';

  List<ExpeditionBattleMember> get _awaiting => _battle.awaitingParty;

  ExpeditionBattleMember? get _actor {
    final awaiting = _awaiting;
    if (awaiting.isEmpty) return null;
    // 독이 방금 고른 대원이 먼저고, 없으면 화면이 들고 있던 선택을 따른다.
    final wanted = _selectedMemberId ?? widget.selectedMemberId;
    return awaiting.where((member) => member.memberId == wanted).firstOrNull ??
        awaiting.first;
  }

  ExpeditionMember? _plantOf(int memberId) =>
      widget.members.where((member) => member.id == memberId).firstOrNull;

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
    // 잠긴 이유는 레벨만이 아니다. 서버가 사유를 보냈으면 그것을 쓴다 —
    // `넘길 다른 대원이 없어요`를 `Lv.9 해금`으로 바꿔 말하면 거짓말이 된다.
    if (!action.available) {
      return action.lockReason ?? 'Lv.${action.unlockLevel} 해금';
    }
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
    widget.onSelectMember(memberId);
  }

  Future<void> _submit(String actionCode) async {
    final actor = _actor;
    if (actor == null || _locked) return;
    if (_lockReason(actor, actionCode) != null) return;

    // 무엇으로 바꿀지 함께 묻는 기록서는 고르는 단계를 먼저 거친다. 고르지 않고
    // 보내면 서버가 되돌려보내고 아무 일도 일어나지 않으므로, 여기서 미리 묻는다.
    final action = _actionFor(actor, actionCode);
    String? choice;
    if (action.needsChoice) {
      choice = await _askChoice(action);
      if (choice == null || !mounted) return;
    }

    _autoTimer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      final accepted = await widget.onSubmit(
        ExpeditionCombatCommand(
          memberId: actor.memberId,
          action: actionCode,
          choice: choice,
        ),
      );
      if (accepted) {
        ref.read(expeditionBattleSettingsProvider.notifier).finishAssist();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 명령형 기록서가 묻는 선택을 받는다. 취소하면 null이고 행동도 소비되지 않는다.
  ///
  /// 후보와 이름표는 서버가 준 것을 그대로 쓴다. 앱이 목록을 만들면 결이 늘어날
  /// 때 두 곳이 어긋나고, 그러면 사용자가 이유 없이 거절당한다.
  Future<String?> _askChoice(ExpeditionBattleAction action) async {
    final theme = Theme.of(context);
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(action.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                action.mechanicSummary.isEmpty
                    ? switch (action.choiceKind) {
                        'member' => '누가 대신 받을지 골라 주세요.',
                        'book' => '어떤 기록서로 바꿀지 골라 주세요.',
                        _ => '무엇으로 바꿀지 골라 주세요.',
                      }
                    : action.mechanicSummary,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (final option in action.choiceOptions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ChoiceOptionTile(
                    label: option.label,
                    // 지금과 같은 것은 고를 수 없다. 눌러 본 뒤 거절당하는 대신
                    // 왜 못 고르는지 자리에서 보여 준다.
                    isCurrent: option.value == action.choiceCurrent,
                    currentLabel: switch (action.choiceKind) {
                      'member' => '지금 노려짐',
                      'book' => '지금 끼고 있음',
                      _ => '지금 이 결',
                    },
                    onTap: option.value == action.choiceCurrent
                        ? null
                        : () => Navigator.of(context).pop(option.value),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
      // AUTO는 사람이 골라야 하는 행동을 대신 고르지 않는다. 시트를 띄우면
      // 자동 진행이 멈춰 서고, 임의로 고르면 사용자가 안 시킨 선택이 된다.
      if (_actionFor(actor, action).needsChoice) action = 'attack';
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
                if (action.mechanicSummary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '기믹 · ${action.mechanicSummary}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
                if (member.kit.roleLabel.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      MongrooTag(
                        label: member.kit.roleLabel,
                        icon: Icons.badge_outlined,
                      ),
                      for (final key in const [
                        'offense',
                        'vitality',
                        'support',
                        'control',
                      ])
                        if (member.kit.combatStats[key] case final value?)
                          MongrooTag(
                            label:
                                '${member.kit.combatStatLabels[key] ?? key} $value',
                            icon: switch (key) {
                              'offense' => Icons.flash_on_outlined,
                              'vitality' => Icons.favorite_outline_rounded,
                              'support' => Icons.health_and_safety_outlined,
                              _ => Icons.tune_rounded,
                            },
                          ),
                    ],
                  ),
                ],
                if (actionCode != 'guard') ...[
                  const SizedBox(height: 10),
                  // 여기에는 **이름이 붙은 것만** 둔다. 계수를 그대로 얹으면
                  // `계수 107.9%`, `단계 110% · 상성 150%`처럼 판정식 중간값이
                  // 화면에 나오는데, 그 셋을 곱해 나온 결과는 이미 위의
                  // `위력 23`이고 약점 배수는 아래 결 태그가 `×1.50`으로
                  // 말한다. 같은 값을 세 번, 그중 두 번은 내부 표기로 보여
                  // 주고 있었다.
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
                    // 무엇으로 그리는지가 아니라 무엇이 보이는지를 적는다.
                    // `스프라이트 VFX 계열`·`융합 레이어`는 만드는 쪽 말이다.
                    Text(
                      action.fusionVfxFamily == null
                          ? '연출 · 이 캐릭터만의 움직임과 효과가 나와요'
                          : '연출 · 고유 움직임 위에 지금 성장결의 빛이 겹쳐요',
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
                      'skillbook' => '출처 · 기록서',
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
    final mechanic = enemy.intent.mechanic;
    final bossRule = _battle.bossPhase;
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
              if (mechanic != null) ...[
                _DiscoverySheetLine(
                  icon: Icons.extension_outlined,
                  title: '공격 기믹 · ${mechanic.name}',
                  value: mechanic.counter,
                ),
              ],
              if (bossRule?.ruleSummary case final rule?)
                _DiscoverySheetLine(
                  icon: Icons.change_circle_outlined,
                  title: bossRule?.ruleName ?? '현재 페이즈 규칙',
                  value: rule,
                ),
              if (bossRule?.phaseGate == 'resolve_intent' &&
                  bossRule?.phaseGateReady == false)
                const _DiscoverySheetLine(
                  icon: Icons.visibility_outlined,
                  title: '봉인 경계',
                  value: '현재 예고를 한 번 해결하면 다음 봉인을 열 수 있어요.',
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
    // 한 차례가 풀리는 동안 뜨는 문장이다. 상대가 엉킴인지 수호짐승인지와
    // 무관하게 같은 자리라, 이름을 붙이면 `전투` 스테이지에서 `수호전이
    // 진행되고 있어요`가 뜬다.
    final prompt = locked || actor == null
        ? '한 차례가 진행되고 있어요…'
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
          // 같은 라운드에 예고가 더 있으면 주 예고 **바로 아래**에 이어 붙인다.
          // 합동 수호전의 잠꼬대가 여기 온다. 예고가 하나뿐인 전투에서는 이
          // 목록이 비어 있어 화면이 달라지지 않는다.
          for (final extra in battle.enemy.extraIntents)
            _ExtraIntentLine(key: ValueKey('seq-dock-extra-${extra.code}'), intent: extra),
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
    final mechanic = intent.mechanic;
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
    // 폭이 좁으면 공격 이름을 뺀다. 무대 위 예고판이 `종잇장 회오리 예고 ·
    // 낱장들이 맨 앞 대원 쪽으로 몰려가요.`로 이름과 상황을 이미 말하고,
    // 이 줄에서 꼭 읽어야 하는 것은 **누구를 얼마나**다. 넷을 다 넣으면
    // 390px에서 `종잇장 회오리 · 행동 순서 맨…`으로 끊겨 대상이 사라졌다.
    Widget intentSummaryFor(bool compact) => Row(
          children: [
            Icon(
              expeditionIntentTargetIcon(intent.target),
              size: 17,
              color: scheme.error,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                compact
                    ? '${intent.targetLabel} · 위력 ${intent.power}'
                    : '${intent.name} · ${intent.targetLabel} · '
                        '위력 ${intent.power}'
                        '${mechanic == null ? '' : ' · ${mechanic.name}'}',
                maxLines: textScale >= 1.35 ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        );
    // `잔향 읽기`를 쓴 전투에서만 서버가 다음 라운드 예고를 열어 준다.
    // 이 책이 파는 것이 이 한 줄이라, 없으면 아무것도 그리지 않는다.
    final next = battle.enemy.nextIntent;
    final nextLine = next == null
        ? null
        : Row(
            key: const ValueKey('seq-dock-next-intent'),
            children: [
              Icon(Icons.update_rounded, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '다음 라운드 · ${next.name} · ${next.targetLabel} · '
                  '위력 ${next.power}',
                  maxLines: textScale >= 1.35 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      label: '적 의도 ${intent.name}, ${intent.targetLabel}, 위력 ${intent.power}. '
          '${mechanic == null ? '' : '기믹 ${mechanic.name}, ${mechanic.counter}. '}'
          '${next == null ? '' : '다음 라운드는 ${next.name}, ${next.targetLabel}, '
              '위력 ${next.power}. '}'
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final head = textScale >= 1.5
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          intentSummaryFor(false),
                          const SizedBox(height: 5),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: matchupTag,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: intentSummaryFor(constraints.maxWidth < 420),
                          ),
                          const SizedBox(width: 6),
                          matchupTag,
                        ],
                      );
                if (nextLine == null) return head;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [head, const SizedBox(height: 5), nextLine],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 주 예고 아래에 한 줄 더 붙는 예고.
///
/// 스크린리더가 `주 의도` 다음에 `잠꼬대`를 읽도록 역할 이름을 앞에 붙인다.
/// 위력과 대상은 주 예고와 같은 어휘를 쓰므로 다시 배울 것이 없다.
class _ExtraIntentLine extends StatelessWidget {
  const _ExtraIntentLine({super.key, required this.intent});

  final ExpeditionBattleIntent intent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '잠꼬대. ${intent.name}. ${intent.telegraph}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.bedtime_outlined,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${intent.name} · ${intent.telegraph}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
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

/// 명령형 기록서의 선택지 한 줄.
///
/// 지금과 같은 값은 누를 수 없되 목록에서 빼지는 않는다. 빼 버리면 "왜 이것만
/// 없지" 하고 헷갈리고, 남겨 두면 "지금 이거라서 못 고른다"가 그대로 읽힌다.
class _ChoiceOptionTile extends StatelessWidget {
  const _ChoiceOptionTile({
    required this.label,
    required this.isCurrent,
    required this.currentLabel,
    required this.onTap,
  });

  final String label;
  final bool isCurrent;

  /// `지금 이것`을 뭐라고 부를지. 성장결·대원·기록서가 각각 다르게 읽힌다.
  final String currentLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: isCurrent ? '$label, 지금 이 결이에요' : label,
      child: Material(
        color: isCurrent
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isCurrent
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (isCurrent)
                  Text(
                    currentLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
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
                      if ((member.statuses['exposed'] ?? 0) > 0) ...[
                        const SizedBox(width: 3),
                        Icon(
                          Icons.gps_fixed_rounded,
                          size: 12,
                          color: scheme.error,
                        ),
                        Text(
                          '빈틈',
                          textScaler: TextScaler.noScaling,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.error,
                                    fontWeight: FontWeight.w800,
                                  ),
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

/// 이 행동의 전용 아이콘. 없으면 `null`이고 호출부가 효과 시트 조각을 쓴다.
///
/// 지도 자체는 비공개로 둔다. 밖에서 필요한 것은 `이 코드에 그림이 있는가`
/// 하나뿐이고, 지도를 열면 다른 화면이 제 나름의 대체 규칙을 만들기 시작한다.
String? expeditionDockSkillIconAsset(String? code) =>
    code == null ? null : _dockSkillIconAssets[code];

const _dockSkillIconAssets = <String, String>{
  'sprout_cheer': 'assets/adventure/skill-icons/baby-pot/sprout-cheer-v1.webp',
  'root_embrace': 'assets/adventure/skill-icons/baby-pot/root-embrace-v1.webp',
  'command_blade':
      'assets/adventure/skill-icons/handsome-pot/command-blade-v1.webp',
  'command_crescendo':
      'assets/adventure/skill-icons/handsome-pot/command-crescendo-v1.webp',
  'heart_spotlight':
      'assets/adventure/skill-icons/pretty-pot/heart-spotlight-v1.webp',
  'ribbon_encore':
      'assets/adventure/skill-icons/pretty-pot/ribbon-encore-v1.webp',
  'blazing_counter':
      'assets/adventure/skill-icons/tsundere-pot/blazing-counter-v1.webp',
  'iron_uppercut':
      'assets/adventure/skill-icons/tsundere-pot/iron-uppercut-v1.webp',
  'grave_gravity':
      'assets/adventure/skill-icons/zombie-pot/grave-gravity-v1.webp',
  'undying_chain':
      'assets/adventure/skill-icons/zombie-pot/undying-chain-v1.webp',
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
  'prism_meteor':
      'assets/adventure/skill-icons/magical-pot/prism-meteor-v1.webp',
  'timefold_comet':
      'assets/adventure/skill-icons/magical-pot/timefold-comet-v1.webp',
  'absolute_zero_read':
      'assets/adventure/skill-icons/aloof-pot/absolute-zero-read-v1.webp',
  'steel_verdict':
      'assets/adventure/skill-icons/aloof-pot/steel-verdict-v1.webp',
  'ink_formula_burst':
      'assets/adventure/skill-icons/student-pot/ink-formula-burst-v1.webp',
  'seal_rewrite':
      'assets/adventure/skill-icons/student-pot/seal-rewrite-v1.webp',
  'triage_bloom': 'assets/adventure/skill-icons/nurse-pot/triage-bloom-v1.webp',
  'white_garden_oath':
      'assets/adventure/skill-icons/nurse-pot/white-garden-oath-v1.webp',
  'golden_downbeat':
      'assets/adventure/skill-icons/maestro-pot/golden-downbeat-v1.webp',
  'silent_coda': 'assets/adventure/skill-icons/maestro-pot/silent-coda-v1.webp',
  'patina_parry':
      'assets/adventure/skill-icons/restorer-pot/patina-parry-v1.webp',
  'golden_seam':
      'assets/adventure/skill-icons/restorer-pot/golden-seam-v1.webp',
  'softpaw_rush':
      'assets/adventure/skill-icons/marten-pot/softpaw-rush-v1.webp',
  'den_guardian_roar':
      'assets/adventure/skill-icons/marten-pot/den-guardian-roar-v1.webp',
  'patchwork_relay':
      'assets/adventure/skill-icons/gal-pot/patchwork-relay-v1.webp',
  'runway_reversal':
      'assets/adventure/skill-icons/gal-pot/runway-reversal-v1.webp',
  'archive_lantern':
      'assets/adventure/skill-icons/archive-guide/archive-lantern-v1.webp',
  'archive_seal':
      'assets/adventure/skill-icons/archive-guide/archive-seal-v1.webp',
  // 여섯 성장결 스킬. 품종이 아니라 마음이 정하는 자리라 품종 폴더가 아니라
  // `emotion/`에 둔다. 누구든 선택 I에 이 중 하나를 끼우므로 아이콘이 없으면
  // 모든 사용자가 전투마다 대체 그림 한 칸을 본다.
  'sunny_radiant_heart':
      'assets/adventure/skill-icons/emotion/sunny-radiant-heart-v1.webp',
  'rainy_frozen_tide':
      'assets/adventure/skill-icons/emotion/rainy-frozen-tide-v1.webp',
  'ember_rage_breaker':
      'assets/adventure/skill-icons/emotion/ember-rage-breaker-v1.webp',
  'moonlit_lonesome_tempest':
      'assets/adventure/skill-icons/emotion/moonlit-lonesome-tempest-v1.webp',
  'sparkling_shock_wonder':
      'assets/adventure/skill-icons/emotion/sparkling-shock-wonder-v1.webp',
  'mosaic_steel_equilibrium':
      'assets/adventure/skill-icons/emotion/mosaic-steel-equilibrium-v1.webp',
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
