import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../home/domain/plant.dart';
import '../../home/presentation/plant_view.dart';
import '../domain/expedition_models.dart';
import 'expedition_controller.dart';
import 'expedition_combat_effects.dart';
import 'expedition_combat_sprites.dart';

/// 수호전에서 한 라운드의 행동과 순서를 예약하는 지휘 패널.
///
/// 클라이언트는 예상 집중력과 예상 피해만 보여 준다. 실제 승패와
/// 피해는 항상 서버가 명령 순서대로 다시 계산한 결과를 사용한다.
class ExpeditionBattlePanel extends ConsumerStatefulWidget {
  const ExpeditionBattlePanel({
    super.key,
    required this.expedition,
    required this.event,
    required this.state,
    required this.onTurnStarted,
    this.compact = false,
  });

  final ExpeditionSnapshot expedition;
  final ExpeditionEvent event;
  final ExpeditionUiState state;
  final Future<void> Function() onTurnStarted;
  final bool compact;

  @override
  ConsumerState<ExpeditionBattlePanel> createState() =>
      _ExpeditionBattlePanelState();
}

class _ExpeditionBattlePanelState extends ConsumerState<ExpeditionBattlePanel> {
  final Map<int, String> _commands = {};
  final List<int> _order = [];
  Timer? _autoTimer;
  int? _selectedMemberId;
  String? _battleFingerprint;
  bool _autoEnabled = false;
  bool _submitting = false;

  ExpeditionBattle get _battle => widget.event.battle!;
  bool get _interactionLocked => widget.state.interactionLocked || _submitting;

  @override
  void initState() {
    super.initState();
    _resetRound();
  }

  @override
  void didUpdateWidget(covariant ExpeditionBattlePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fingerprint = _fingerprint(_battle);
    if (_battleFingerprint != fingerprint) {
      _resetRound();
      _scheduleAutoTurn();
      return;
    }
    if (oldWidget.state.interactionLocked &&
        !widget.state.interactionLocked &&
        _autoEnabled) {
      _scheduleAutoTurn();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  String _fingerprint(ExpeditionBattle battle) =>
      '${widget.expedition.run.id}:${widget.expedition.run.revision}:${battle.round}:'
      '${battle.livingParty.map((member) => member.memberId).join(',')}';

  void _resetRound() {
    _autoTimer?.cancel();
    final living = _battle.livingParty;
    _order
      ..clear()
      ..addAll(living.map((member) => member.memberId));
    _commands
      ..clear()
      ..addEntries(
        living.map((member) => MapEntry(member.memberId, 'attack')),
      );
    if (!living.any((member) => member.memberId == _selectedMemberId)) {
      _selectedMemberId = living.firstOrNull?.memberId;
    }
    _battleFingerprint = _fingerprint(_battle);
  }

  ExpeditionBattleMember _member(int memberId) =>
      _battle.party.firstWhere((member) => member.memberId == memberId);

  ExpeditionBattleAction _actionFor(
    ExpeditionBattleMember member,
    String action,
  ) =>
      switch (action) {
        'skill' => member.kit.skill,
        'guard' => member.kit.guard,
        _ => member.kit.basic,
      };

  bool _matchesWeakness(
    ExpeditionBattleMember member,
    ExpeditionBattleAction action,
  ) =>
      member.kit.version >= 6
          ? action.matchup == 'weak' || action.matchup == 'prism_weak'
          : action.affinity == _battle.enemy.weakness;

  ({
    bool valid,
    int focusAfter,
    int damage,
    String? error,
  }) _forecast() {
    var focus = _battle.focus;
    var damage = 0;
    for (final memberId in _order) {
      final member = _member(memberId);
      final actionCode = _commands[memberId] ?? 'attack';
      final action = _actionFor(member, actionCode);
      if (actionCode == 'skill') {
        if (focus < action.focusCost) {
          return (
            valid: false,
            focusAfter: focus,
            damage: damage,
            error: '${member.name} 순서에서 집중력 ${action.focusCost}이(가) 필요해요.',
          );
        }
        focus -= action.focusCost;
        if (action.effect == 'focus_refund') {
          focus = (focus + 1).clamp(0, _battle.maxFocus);
        } else if (action.effect == 'study_refund') {
          focus = (focus + 2).clamp(0, _battle.maxFocus);
        }
      } else {
        focus = (focus + action.focusDelta).clamp(0, _battle.maxFocus);
      }
      if (actionCode != 'guard') {
        var actionDamage = action.power;
        if (member.kit.version < 6) {
          final weaknessHit = _matchesWeakness(member, action);
          if (weaknessHit) actionDamage += 7;
          if (action.effect == 'weakness_pierce' && weaknessHit) {
            actionDamage += 6;
          } else if (action.effect == 'last_stand' && member.hp == 1) {
            actionDamage += 8;
          } else if (action.effect == 'steady_read' && !weaknessHit) {
            actionDamage += 5;
          }
        }
        damage += actionDamage;
      }
    }
    return (
      valid: true,
      focusAfter: focus,
      damage: damage,
      error: null,
    );
  }

  void _selectMember(int memberId) {
    if (_interactionLocked) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedMemberId = memberId);
    ref.read(expeditionControllerProvider.notifier).selectMember(memberId);
  }

  void _chooseAction(String action) {
    final memberId = _selectedMemberId;
    if (memberId == null || _interactionLocked) return;
    HapticFeedback.selectionClick();
    setState(() => _commands[memberId] = action);
  }

  void _moveMember(int memberId, int delta) {
    if (_interactionLocked) return;
    final from = _order.indexOf(memberId);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= _order.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _order
        ..removeAt(from)
        ..insert(to, memberId);
    });
  }

  void _toggleAuto(bool enabled) {
    HapticFeedback.selectionClick();
    _autoTimer?.cancel();
    setState(() => _autoEnabled = enabled);
    if (!enabled) return;
    _applyAutoPlan();
    _scheduleAutoTurn();
  }

  void _applyAutoPlan() {
    var focus = _battle.focus;
    final targeted = _targetedMemberIds();
    setState(() {
      for (final memberId in _order) {
        final member = _member(memberId);
        final skill = member.kit.skill;
        final danger = targeted.contains(memberId) &&
            (_battle.enemy.intent.power >= member.hp || member.hp <= 1);
        if (danger) {
          _commands[memberId] = 'guard';
          focus =
              (focus + member.kit.guard.focusDelta).clamp(0, _battle.maxFocus);
        } else if (_matchesWeakness(member, skill) &&
            focus >= skill.focusCost) {
          _commands[memberId] = 'skill';
          focus -= skill.focusCost;
          if (skill.effect == 'focus_refund') {
            focus = (focus + 1).clamp(0, _battle.maxFocus);
          } else if (skill.effect == 'study_refund') {
            focus = (focus + 2).clamp(0, _battle.maxFocus);
          }
        } else {
          _commands[memberId] = 'attack';
          focus =
              (focus + member.kit.basic.focusDelta).clamp(0, _battle.maxFocus);
        }
      }
    });
  }

  void _scheduleAutoTurn() {
    _autoTimer?.cancel();
    if (!_autoEnabled || _interactionLocked || !_battle.isActive) {
      return;
    }
    _autoTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted ||
          !_autoEnabled ||
          _interactionLocked ||
          !_forecast().valid) {
        return;
      }
      _submitTurn();
    });
  }

  Future<void> _submitTurn() async {
    final forecast = _forecast();
    if (!forecast.valid || _interactionLocked) return;
    _autoTimer?.cancel();
    HapticFeedback.mediumImpact();
    final commands = _order
        .map(
          (memberId) => ExpeditionCombatCommand(
            memberId: memberId,
            action: _commands[memberId] ?? 'attack',
          ),
        )
        .toList(growable: false);
    setState(() => _submitting = true);
    try {
      await widget.onTurnStarted();
      if (!mounted) return;
      await ref
          .read(expeditionControllerProvider.notifier)
          .resolveCombatTurn(commands);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

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
      _ => {_order.first},
    };
  }

  Future<void> _confirmRetreat() async {
    if (_interactionLocked) return;
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
    if (leave != true || !mounted) return;
    HapticFeedback.mediumImpact();
    await ref.read(expeditionControllerProvider.notifier).retreat();
  }

  ExpeditionMember? _expeditionMember(int memberId) => widget.expedition.party
      .where((member) => member.id == memberId)
      .firstOrNull;

  String _effectKeyForAction(
    ExpeditionBattleAction action,
    String actionCode,
  ) {
    if (actionCode == 'guard') return 'safe_guard';
    if (action.effectKey case final effectKey?) return effectKey;
    return switch (action.affinity) {
      'care' => 'care_vines',
      'focus' => 'prism_burst',
      'courage' => 'ember_arc',
      'insight' => 'insight_arc',
      _ => 'echo_wave',
    };
  }

  Future<void> _showActionDetails(
    ExpeditionBattleAction action,
    String actionCode,
    bool weakness,
  ) async {
    final metadata = switch (actionCode) {
      'skill' => '위력 ${action.power} · 집중 -${action.focusCost}',
      'guard' => '방어 +${action.guard} · 집중 +${action.focusDelta}',
      _ => '위력 ${action.power} · 집중 +${action.focusDelta}',
    };
    final effectKey = _effectKeyForAction(action, actionCode);
    final matchupMultiplier = (action.matchupBp / 10000).toStringAsFixed(2);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CombatEffectThumbnail(effectKey: effectKey, size: 64),
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
              if (action.affinityLabel != null) ...[
                const SizedBox(height: 12),
                MongrooTag(
                  label: weakness
                      ? '${action.affinityLabel} · 약점 ×$matchupMultiplier'
                      : action.affinityLabel!,
                  icon: _affinityIcon(action.affinity ?? ''),
                  backgroundColor:
                      _affinityColor(context, action.affinity ?? '')
                          .withAlpha(42),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
              _DiscoveryLine(
                icon: _affinityIcon(enemy.weakness),
                title: '확인한 약점',
                value: enemy.weaknessLabel,
              ),
              _DiscoveryLine(
                icon: Icons.visibility_outlined,
                title: '다음 행동',
                value:
                    '${enemy.intent.name} · ${enemy.intent.targetLabel} · 위력 ${enemy.intent.power}',
              ),
              const Divider(height: 24),
              const _DiscoveryLine(
                icon: Icons.menu_book_outlined,
                title: '상세 생태 기록',
                value: '??? · 전투 후 도감에서 공개',
                locked: true,
              ),
              const _DiscoveryLine(
                icon: Icons.redeem_outlined,
                title: '숨은 보상',
                value: '??? · 실제 발견 후 공개',
                locked: true,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _interactionLocked
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        unawaited(_confirmRetreat());
                      },
                icon: const Icon(Icons.directions_run_rounded),
                label: const Text('긴급 귀환'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactBattle(BuildContext context) {
    final battle = _battle;
    final selected = battle.party
        .where((member) => member.memberId == _selectedMemberId)
        .firstOrNull;
    final forecast = _forecast();
    final busy = _interactionLocked;
    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    final targeted = _targetedMemberIds();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final roundTag = MongrooTag(
      label: 'R ${battle.round}/${battle.maxRounds}',
      icon: Icons.sports_martial_arts_rounded,
      backgroundColor: scheme.errorContainer.withAlpha(130),
    );
    final focusMeter = Semantics(
      label: '집중력 ${battle.focus}/${battle.maxFocus}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 18, color: palette.butter),
          const SizedBox(width: 3),
          Text(
            '${battle.focus}/${battle.maxFocus}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
    final autoToggle = SizedBox(
      height: 48,
      child: FilterChip(
        key: const ValueKey('combat-auto-toggle'),
        selected: _autoEnabled,
        onSelected: busy ? null : _toggleAuto,
        avatar: Icon(
          _autoEnabled ? Icons.autorenew_rounded : Icons.touch_app_outlined,
          size: 17,
        ),
        label: const Text('AUTO'),
      ),
    );
    final discoveryButton = IconButton(
      key: const ValueKey('combat-discovery-info'),
      onPressed: _showBattleDiscovery,
      tooltip: '발견 정보',
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: const Icon(Icons.info_outline_rounded),
    );

    return MongrooPanel(
      key: const ValueKey('combat-battle-panel'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      radius: 16,
      borderColor: scheme.error.withAlpha(85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (textScale >= 1.35)
            Column(
              children: [
                Row(
                  children: [
                    roundTag,
                    const Spacer(),
                    discoveryButton,
                  ],
                ),
                Row(
                  children: [
                    focusMeter,
                    const Spacer(),
                    autoToggle,
                  ],
                ),
              ],
            )
          else
            Row(
              children: [
                roundTag,
                const SizedBox(width: 8),
                Expanded(child: focusMeter),
                autoToggle,
                discoveryButton,
              ],
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.errorContainer.withAlpha(74),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    expeditionIntentTargetIcon(battle.enemy.intent.target),
                    size: 17,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${battle.enemy.intent.name} · ${battle.enemy.intent.targetLabel}',
                      maxLines: textScale >= 1.35 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: 6),
                  MongrooTag(
                    label: '약점 ${battle.enemy.weaknessLabel}',
                    icon: _affinityIcon(battle.enemy.weakness),
                    backgroundColor:
                        _affinityColor(context, battle.enemy.weakness)
                            .withAlpha(38),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: textScale >= 1.35 ? 118 : 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < _order.length; index++) ...[
                  if (index > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _CompactBattleMemberCard(
                      key: ValueKey('combat-member-${_order[index]}'),
                      member: _member(_order[index]),
                      expeditionMember: _expeditionMember(_order[index]),
                      order: index + 1,
                      selected: _order[index] == _selectedMemberId,
                      targeted: targeted.contains(_order[index]),
                      targetKind: battle.enemy.intent.target,
                      action: _actionFor(
                        _member(_order[index]),
                        _commands[_order[index]] ?? 'attack',
                      ),
                      actionCode: _commands[_order[index]] ?? 'attack',
                      canMoveUp: index > 0 && !busy,
                      canMoveDown: index < _order.length - 1 && !busy,
                      onSelect:
                          busy ? null : () => _selectMember(_order[index]),
                      onMoveUp: () => _moveMember(_order[index], -1),
                      onMoveDown: () => _moveMember(_order[index], 1),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final actionCode in const [
                  'attack',
                  'skill',
                  'guard'
                ]) ...[
                  if (actionCode != 'attack') const SizedBox(width: 6),
                  Expanded(
                    child: _CompactBattleActionChoice(
                      key: ValueKey(
                        'combat-action-$actionCode-${selected.memberId}',
                      ),
                      action: _actionFor(selected, actionCode),
                      actionCode: actionCode,
                      effectKey: _effectKeyForAction(
                        _actionFor(selected, actionCode),
                        actionCode,
                      ),
                      selected: _commands[selected.memberId] == actionCode,
                      weakness: actionCode != 'guard' &&
                          _matchesWeakness(
                            selected,
                            _actionFor(selected, actionCode),
                          ),
                      enabled: !busy,
                      onPressed: () => _chooseAction(actionCode),
                      onLongPress: () => _showActionDetails(
                        _actionFor(selected, actionCode),
                        actionCode,
                        actionCode != 'guard' &&
                            _matchesWeakness(
                              selected,
                              _actionFor(selected, actionCode),
                            ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 140),
                  child: Text(
                    forecast.error ??
                        '예상 피해 ${forecast.damage} · 집중 ${forecast.focusAfter}/${battle.maxFocus}',
                    key: ValueKey(
                      forecast.error == null
                          ? 'combat-forecast-ok'
                          : 'combat-forecast-error',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: forecast.error == null
                              ? scheme.primary
                              : scheme.error,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  key: const ValueKey('combat-submit'),
                  onPressed: busy || !forecast.valid ? null : _submitTurn,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: const Text('전투 개시'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) return _buildCompactBattle(context);
    final battle = _battle;
    final selected = battle.party
        .where((member) => member.memberId == _selectedMemberId)
        .firstOrNull;
    final forecast = _forecast();
    final busy = _interactionLocked;
    final palette = MongrooPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final targeted = _targetedMemberIds();
    return MongrooPanel(
      key: const ValueKey('combat-battle-panel'),
      padding: const EdgeInsets.all(14),
      borderColor: scheme.error.withAlpha(85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '직접 지휘 · ${battle.round}/${battle.maxRounds} 라운드',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '행동 순서와 상성을 정한 뒤 한 번에 실행해요.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: _autoEnabled ? '자동 지휘가 켜져 있어요.' : '자동 지휘. 기본으로 꺼져 있어요.',
                child: FilterChip(
                  key: const ValueKey('combat-auto-toggle'),
                  selected: _autoEnabled,
                  onSelected: busy ? null : _toggleAuto,
                  avatar: Icon(
                    _autoEnabled
                        ? Icons.autorenew_rounded
                        : Icons.touch_app_outlined,
                    size: 18,
                  ),
                  label: Text(_autoEnabled ? '자동 지휘 켜짐' : '자동 지휘'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _EnemyIntentCard(battle: battle),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ResourceMeter(
                  label: '집중력',
                  value: battle.focus,
                  maxValue: battle.maxFocus,
                  icon: Icons.bolt_rounded,
                  color: palette.butter,
                ),
              ),
              const SizedBox(width: 10),
              MongrooTag(
                label: '실행 후 ${forecast.focusAfter}/${battle.maxFocus}',
                icon: Icons.fast_forward_rounded,
                backgroundColor: palette.paperDeep,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('행동 순서', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '1번부터 집중력을 생성·사용해요. 맨 앞 대원은 전면 공격의 대상이 됩니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < _order.length; index++) ...[
            _BattleMemberOrderCard(
              member: _member(_order[index]),
              order: index + 1,
              selected: _order[index] == _selectedMemberId,
              targeted: targeted.contains(_order[index]),
              targetKind: _battle.enemy.intent.target,
              action: _actionFor(
                _member(_order[index]),
                _commands[_order[index]] ?? 'attack',
              ),
              actionCode: _commands[_order[index]] ?? 'attack',
              canMoveUp: index > 0 && !busy,
              canMoveDown: index < _order.length - 1 && !busy,
              onSelect: busy ? null : () => _selectMember(_order[index]),
              onMoveUp: () => _moveMember(_order[index], -1),
              onMoveDown: () => _moveMember(_order[index], 1),
            ),
            if (index < _order.length - 1) const SizedBox(height: 7),
          ],
          if (selected != null) ...[
            const SizedBox(height: 16),
            Text(
              '${selected.name}의 명령',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _BattleActionChoice(
              key: ValueKey('combat-action-attack-${selected.memberId}'),
              action: selected.kit.basic,
              actionCode: 'attack',
              selected: _commands[selected.memberId] == 'attack',
              weakness: _matchesWeakness(selected, selected.kit.basic),
              enabled: !busy,
              onPressed: () => _chooseAction('attack'),
            ),
            const SizedBox(height: 7),
            _BattleActionChoice(
              key: ValueKey('combat-action-skill-${selected.memberId}'),
              action: selected.kit.skill,
              actionCode: 'skill',
              selected: _commands[selected.memberId] == 'skill',
              weakness: _matchesWeakness(selected, selected.kit.skill),
              enabled: !busy,
              onPressed: () => _chooseAction('skill'),
            ),
            const SizedBox(height: 7),
            _BattleActionChoice(
              key: ValueKey('combat-action-guard-${selected.memberId}'),
              action: selected.kit.guard,
              actionCode: 'guard',
              selected: _commands[selected.memberId] == 'guard',
              weakness: false,
              enabled: !busy,
              onPressed: () => _chooseAction('guard'),
            ),
          ],
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: forecast.error == null
                ? Text(
                    '예상 장벽 피해 ${forecast.damage} · '
                    '${battle.enemy.guard - forecast.damage <= 0 ? '이 라운드에 장벽 파괴 가능' : '남은 장벽 ${(battle.enemy.guard - forecast.damage).clamp(0, battle.enemy.maxGuard)}'}',
                    key: const ValueKey('combat-forecast-ok'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                        ),
                  )
                : Text(
                    forecast.error!,
                    key: const ValueKey('combat-forecast-error'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.error,
                        ),
                  ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('combat-submit'),
            onPressed: busy || !forecast.valid ? null : _submitTurn,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 13),
              child: Text('예약한 순서로 행동 시작'),
            ),
          ),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.errorContainer.withAlpha(120),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.timer_outlined, size: 18, color: scheme.error),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${battle.maxRounds}라운드 안에 장벽을 못 깨거나 전원이 쓰러지면 '
                      '긴급 귀환하고 미확정 보상을 잃어요.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton.icon(
            onPressed: busy ? null : _confirmRetreat,
            icon: const Icon(Icons.directions_run_rounded),
            label: const Text('수호전에서 물러나기'),
          ),
        ],
      ),
    );
  }
}

class _CompactBattleMemberCard extends StatelessWidget {
  const _CompactBattleMemberCard({
    super.key,
    required this.member,
    required this.expeditionMember,
    required this.order,
    required this.selected,
    required this.targeted,
    required this.targetKind,
    required this.action,
    required this.actionCode,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onSelect,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ExpeditionBattleMember member;
  final ExpeditionMember? expeditionMember;
  final int order;
  final bool selected;
  final bool targeted;
  final String targetKind;
  final ExpeditionBattleAction action;
  final String actionCode;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onSelect;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hp =
        member.maxHp <= 0 ? 0.0 : (member.hp / member.maxHp).clamp(0.0, 1.0);
    return Semantics(
      selected: selected,
      label:
          '$order번 ${member.name}, 체력 ${member.hp}/${member.maxHp}, ${action.name}${targeted ? ', 적의 다음 공격 대상' : ''}',
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: targeted
                ? scheme.error
                : selected
                    ? scheme.primary
                    : scheme.outlineVariant,
            width: selected || targeted ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onSelect,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 5, 3, 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            child: Text(
                              '$order',
                              textScaler: TextScaler.noScaling,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
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
                              size: 14,
                              color: scheme.error,
                            ),
                        ],
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            if (expeditionMember case final plant?)
                              SizedBox(
                                width: 32,
                                child: PlantView(
                                  stage: plant.stage,
                                  form: PlantGrowthForm.fromCode(plant.form),
                                  speciesCode: plant.speciesCode,
                                  speciesName: plant.speciesName,
                                  spritePose: PlantSpritePose.idle,
                                  outfitKey: plant.outfitKey,
                                  width: 32,
                                  height: 48,
                                ),
                              ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    action.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: _actionColor(
                                            context,
                                            actionCode,
                                          ),
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 3),
                                  LinearProgressIndicator(
                                    value: hp,
                                    minHeight: 5,
                                    borderRadius: BorderRadius.circular(99),
                                    color: hp > .35
                                        ? const Color(0xFF69B77B)
                                        : scheme.error,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (canMoveUp || canMoveDown)
              SizedBox(
                width: 44,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      constraints:
                          const BoxConstraints.tightFor(width: 44, height: 44),
                      padding: EdgeInsets.zero,
                      onPressed: canMoveUp ? onMoveUp : null,
                      tooltip: '${member.name} 순서를 앞으로',
                      icon: const Icon(Icons.keyboard_arrow_left_rounded),
                    ),
                    IconButton(
                      constraints:
                          const BoxConstraints.tightFor(width: 44, height: 44),
                      padding: EdgeInsets.zero,
                      onPressed: canMoveDown ? onMoveDown : null,
                      tooltip: '${member.name} 순서를 뒤로',
                      icon: const Icon(Icons.keyboard_arrow_right_rounded),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactBattleActionChoice extends StatelessWidget {
  const _CompactBattleActionChoice({
    super.key,
    required this.action,
    required this.actionCode,
    required this.effectKey,
    required this.selected,
    required this.weakness,
    required this.enabled,
    required this.onPressed,
    required this.onLongPress,
  });

  final ExpeditionBattleAction action;
  final String actionCode;
  final String effectKey;
  final bool selected;
  final bool weakness;
  final bool enabled;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _actionColor(context, actionCode);
    final cost = switch (actionCode) {
      'skill' => '집중 -${action.focusCost}',
      'guard' => '방어 +${action.guard}',
      _ => '집중 +${action.focusDelta}',
    };
    return Semantics(
      selected: selected,
      button: true,
      label: '${action.name}, $cost${weakness ? ', 약점 일치' : ''}. 길게 눌러 설명 보기',
      child: Material(
        color: selected ? color.withAlpha(34) : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: weakness
                ? scheme.error
                : selected
                    ? color
                    : scheme.outlineVariant,
            width: selected || weakness ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: Stack(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CombatEffectThumbnail(effectKey: effectKey, size: 34),
                      const SizedBox(height: 2),
                      Text(
                        action.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        weakness ? '$cost · 약점' : cost,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: weakness ? scheme.error : color,
                              fontSize: 10,
                            ),
                      ),
                    ],
                  ),
                  if (selected)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: color,
                        size: 16,
                      ),
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

class _CombatEffectThumbnail extends StatelessWidget {
  const _CombatEffectThumbnail({required this.effectKey, required this.size});

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

class _DiscoveryLine extends StatelessWidget {
  const _DiscoveryLine({
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

class _EnemyIntentCard extends StatelessWidget {
  const _EnemyIntentCard({required this.battle});

  final ExpeditionBattle battle;

  @override
  Widget build(BuildContext context) {
    final enemy = battle.enemy;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer.withAlpha(92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withAlpha(65)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    enemy.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                MongrooTag(
                  label: '약점 · ${enemy.weaknessLabel}',
                  icon: _affinityIcon(enemy.weakness),
                  backgroundColor: _affinityColor(context, enemy.weakness),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              label: '수호 장벽 ${enemy.guard}/${enemy.maxGuard}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('수호 장벽')),
                      Text(
                        '${enemy.guard}/${enemy.maxGuard}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value:
                        enemy.maxGuard == 0 ? 0 : enemy.guard / enemy.maxGuard,
                    minHeight: 9,
                    borderRadius: BorderRadius.circular(99),
                    color: scheme.error,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.visibility_rounded, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '다음 공격 · ${enemy.intent.name}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(enemy.intent.telegraph),
                      const SizedBox(height: 5),
                      Text(
                        '대상: ${enemy.intent.targetLabel} · 위력 ${enemy.intent.power}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceMeter extends StatelessWidget {
  const _ResourceMeter({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final int maxValue;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 5),
              Expanded(child: Text(label)),
              Text('$value/$maxValue'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: maxValue == 0 ? 0 : value / maxValue,
            minHeight: 7,
            borderRadius: BorderRadius.circular(99),
            color: color,
          ),
        ],
      );
}

class _BattleMemberOrderCard extends StatelessWidget {
  const _BattleMemberOrderCard({
    required this.member,
    required this.order,
    required this.selected,
    required this.targeted,
    required this.targetKind,
    required this.action,
    required this.actionCode,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onSelect,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ExpeditionBattleMember member;
  final int order;
  final bool selected;
  final bool targeted;
  final String targetKind;
  final ExpeditionBattleAction action;
  final String actionCode;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onSelect;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actionColor = _actionColor(context, actionCode);
    return Semantics(
      selected: selected,
      label:
          '$order번, ${member.name}, 체력 ${member.hp}/${member.maxHp}, ${action.name}${targeted ? ', 다음 공격 대상' : ''}',
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(
            color: selected
                ? scheme.primary
                : targeted
                    ? scheme.error
                    : scheme.outlineVariant,
            width: selected || targeted ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  child: Text('$order'),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              member.name,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            _affinityIcon(member.kit.affinity),
                            size: 15,
                            color: _affinityColor(context, member.kit.affinity),
                          ),
                          if (targeted) ...[
                            const SizedBox(width: 4),
                            Icon(
                              expeditionIntentTargetIcon(targetKind),
                              size: 16,
                              color: scheme.error,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'HP ${member.hp}/${member.maxHp}'
                        '${member.guard > 0 ? ' · 방어 ${member.guard}' : ''} · ${member.kit.affinityLabel}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        action.name,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: actionColor,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      onPressed: canMoveUp ? onMoveUp : null,
                      tooltip: '${member.name} 순서를 앞으로',
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      onPressed: canMoveDown ? onMoveDown : null,
                      tooltip: '${member.name} 순서를 뒤로',
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BattleActionChoice extends StatelessWidget {
  const _BattleActionChoice({
    super.key,
    required this.action,
    required this.actionCode,
    required this.selected,
    required this.weakness,
    required this.enabled,
    required this.onPressed,
  });

  final ExpeditionBattleAction action;
  final String actionCode;
  final bool selected;
  final bool weakness;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _actionColor(context, actionCode);
    final metadata = switch (actionCode) {
      'skill' => '위력 ${action.power} · 집중 -${action.focusCost}',
      'guard' => '방어 +${action.guard} · 집중 +${action.focusDelta}',
      _ => '위력 ${action.power} · 집중 +${action.focusDelta}',
    };
    return Semantics(
      selected: selected,
      button: true,
      label:
          '${action.name}. $metadata. ${action.description}${weakness ? ' 약점 일치.' : ''}',
      child: Material(
        color: selected ? color.withAlpha(35) : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(
            color: selected ? color : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 62),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (actionCode) {
                      'skill' => Icons.auto_awesome_rounded,
                      'guard' => Icons.shield_outlined,
                      _ => Icons.flash_on_rounded,
                    },
                    color: color,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 7,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              action.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              metadata,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: color),
                            ),
                            if (weakness)
                              MongrooTag(
                                label: '약점 일치',
                                icon: Icons.adjust_rounded,
                                backgroundColor: color.withAlpha(45),
                                foregroundColor: color,
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          action.description,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: color, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _actionColor(BuildContext context, String action) {
  final scheme = Theme.of(context).colorScheme;
  return switch (action) {
    'skill' => scheme.secondary,
    'guard' => scheme.primary,
    _ => scheme.tertiary,
  };
}

Color _affinityColor(BuildContext context, String affinity) {
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

IconData _affinityIcon(String affinity) => switch (affinity) {
      'care' => Icons.favorite_outline_rounded,
      'focus' => Icons.center_focus_strong_rounded,
      'courage' => Icons.local_fire_department_outlined,
      _ => Icons.visibility_outlined,
    };
