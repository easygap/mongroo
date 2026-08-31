part of 'expedition_screen.dart';

// 사건·수호전의 선택, 담당 캐릭터, 스킬 사용 UI를 한 흐름으로 묶는다.
class _EventDecisionPanel extends ConsumerWidget {
  const _EventDecisionPanel({
    required this.state,
    required this.expedition,
    required this.event,
  });

  final ExpeditionUiState state;
  final ExpeditionSnapshot expedition;
  final ExpeditionEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberId = state.selectedMemberId ?? expedition.party.first.id;
    final selected =
        expedition.party.firstWhere((member) => member.id == memberId);
    final busy = state.interactionLocked;
    final guardianEncounter = event.encounter?.kind == 'guardian';
    return MongrooPanel(
      borderColor: Theme.of(context).colorScheme.secondary.withAlpha(110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.question_mark_rounded,
                  color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(event.title,
                      style: Theme.of(context).textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: 8),
          Text(event.text),
          // 스킬이 판정 기준을 낮추면 미리보기 숫자는 조용히 내려간다. 왜
          // 내려갔는지 말해 주지 않으면 스킬을 쓴 값을 받은 줄 모른다.
          if (event.skillHint case final hint? when hint.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              key: const ValueKey('event-skill-hint'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.tertiary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ],
          if (guardianEncounter) ...[
            const SizedBox(height: 12),
            _GuardianEncounterBrief(encounter: event.encounter!),
          ],
          const SizedBox(height: 16),
          Text('누가 나설까요?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _PartySelector(
            expedition: expedition,
            selectedMemberId: memberId,
            busy: busy,
            spotlightMemberId: event.spotlightMemberId,
          ),
          const SizedBox(height: 12),
          _MemberSkillActions(selected: selected, busy: busy),
          const SizedBox(height: 12),
          ...event.choices.map((choice) {
            final preview = choice.previewFor(memberId);
            Future<void> choose() async {
              final success = await ref
                  .read(expeditionControllerProvider.notifier)
                  .choose(choice.code);
              if (success && event.encounter == null) {
                HapticFeedback.mediumImpact();
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: guardianEncounter
                  ? _GuardianChoiceCard(
                      choice: choice,
                      preview: preview,
                      enabled: !busy,
                      onPressed: choose,
                    )
                  : OutlinedButton(
                      onPressed: busy ? null : choose,
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(choice.label),
                          if (preview != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              '${preview.label}${preview.forecast == null ? '' : ' · ${preview.forecast}'}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
            );
          }),
        ],
      ),
    );
  }
}

class _GuardianEncounterBrief extends StatelessWidget {
  const _GuardianEncounterBrief({required this.encounter});

  final ExpeditionEncounter encounter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '${encounter.attackName} 공격 예고. ${encounter.telegraph}. '
          '수호 장벽을 풀거나 안전하게 물러날 수 있어요.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer.withAlpha(118),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: scheme.tertiary.withAlpha(34),
              blurRadius: 0,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withAlpha(12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.tertiary.withAlpha(34),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const SizedBox.square(
                      dimension: 40,
                      child: Icon(Icons.visibility_outlined, size: 21),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '공격 예고 · ${encounter.attackName}',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          encounter.telegraph,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '쓰러뜨리는 전투가 아니에요. 장벽을 풀거나 안전하게 물러나는 선택 모두 탐험 기록에 남아요.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuardianChoiceCard extends StatefulWidget {
  const _GuardianChoiceCard({
    required this.choice,
    required this.preview,
    required this.enabled,
    required this.onPressed,
  });

  final ExpeditionChoice choice;
  final ExpeditionChoicePreview? preview;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_GuardianChoiceCard> createState() => _GuardianChoiceCardState();
}

class _GuardianChoiceCardState extends State<_GuardianChoiceCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final choice = widget.choice;
    final preview = widget.preview;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final color = _guardianChoiceColor(choice.effectKey, choice.safe);
    final scheme = Theme.of(context).colorScheme;
    final status = choice.safe ? '안전 이탈' : '장벽 -${choice.guardDamage}';
    final previewText = preview == null
        ? null
        : '${preview.label}${preview.forecast == null ? '' : ' · ${preview.forecast}'}';
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label:
          '${choice.label}. $status${previewText == null ? '' : '. $previewText'}',
      child: IgnorePointer(
        ignoring: !widget.enabled,
        child: AnimatedOpacity(
          opacity: widget.enabled ? 1 : .52,
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 140),
          child: AnimatedScale(
            scale: !reduceMotion && _pressed && widget.enabled ? .96 : 1,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 140),
            curve: MongrooMotion.enter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  color.withAlpha(18),
                  scheme.surface,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: color.withAlpha(68),
                    blurRadius: 0,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withAlpha(14),
                    blurRadius: 9,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onPressed,
                  onHighlightChanged: (value) {
                    if (_pressed == value) return;
                    setState(() => _pressed = value);
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 76),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: color.withAlpha(34),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: SizedBox.square(
                                  dimension: 40,
                                  child: Icon(
                                    choice.safe
                                        ? Icons.health_and_safety_outlined
                                        : _guardianChoiceIcon(choice.effectKey),
                                    color: color,
                                    size: 21,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  choice.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 7,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: color.withAlpha(28),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    status,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w900,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (previewText != null)
                                Text(
                                  previewText,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
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

Color _guardianChoiceColor(String? effectKey, bool safe) {
  if (safe) return const Color(0xFF4E8D7C);
  return switch (effectKey) {
    'care_vines' => const Color(0xFF4F9465),
    'ember_arc' => const Color(0xFFC75B42),
    'prism_burst' => const Color(0xFF8064B4),
    'mist_dash' => const Color(0xFF3E829C),
    'insight_arc' => const Color(0xFF397FA7),
    _ => const Color(0xFF9B7140),
  };
}

IconData _guardianChoiceIcon(String? effectKey) => switch (effectKey) {
      'care_vines' => Icons.spa_outlined,
      'ember_arc' => Icons.local_fire_department_outlined,
      'prism_burst' => Icons.auto_awesome_outlined,
      'mist_dash' => Icons.air_rounded,
      'insight_arc' => Icons.visibility_outlined,
      _ => Icons.waves_outlined,
    };

class _PartySelector extends ConsumerWidget {
  const _PartySelector({
    required this.expedition,
    required this.selectedMemberId,
    required this.busy,
    this.spotlightMemberId,
  });

  final ExpeditionSnapshot expedition;
  final int selectedMemberId;
  final bool busy;
  final int? spotlightMemberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: expedition.party
            .map(
              (member) => ChoiceChip(
                avatar: Icon(
                  member.id == spotlightMemberId
                      ? Icons.star_outline_rounded
                      : member.isGuide
                          ? Icons.assistant_outlined
                          : Icons.person_outline,
                  size: 18,
                ),
                label: Text(member.name),
                selected: member.id == selectedMemberId,
                onSelected: busy
                    ? null
                    : (_) => ref
                        .read(expeditionControllerProvider.notifier)
                        .selectMember(member.id),
              ),
            )
            .toList(growable: false),
      );
}

class _MemberSkillActions extends ConsumerWidget {
  const _MemberSkillActions({required this.selected, required this.busy});

  final ExpeditionMember selected;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selected.isGuide) {
      return Text(
        '기록 안내자는 조작을 설명하지만 캐릭터 스킬은 사용하지 않아요.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    final actions = [
      _SkillActionData(
        type: 'signature',
        icon: Icons.bolt_outlined,
        skill: selected.signatureSkill,
      ),
      _SkillActionData(
        type: 'form',
        icon: Icons.auto_awesome_outlined,
        skill: selected.formSkill,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final buttons = actions
                .map(
                  (action) => _SkillButton(
                    data: action,
                    busy: busy,
                    onPressed: () => _activateSkill(context, ref, action),
                  ),
                )
                .toList(growable: false);
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buttons.first,
                  const SizedBox(height: 8),
                  buttons.last,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: buttons.first),
                const SizedBox(width: 8),
                Expanded(child: buttons.last),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          '${selected.signatureSkill.name}: ${selected.signatureSkill.description}\n'
          '${selected.formSkill.name}: ${selected.formSkill.description}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        if (selected.hasRegionAdjustment) ...[
          const SizedBox(height: 6),
          Text(
            '이 지역은 능력치를 ${selected.statCap}까지 보정해요. '
            '선택지에서 원래 수치와 탐험 수치를 함께 보여 줄게요.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

class _SkillActionData {
  const _SkillActionData({
    required this.type,
    required this.icon,
    required this.skill,
  });

  final String type;
  final IconData icon;
  final ExpeditionSkill skill;
}

class _SkillButton extends StatelessWidget {
  const _SkillButton({
    required this.data,
    required this.busy,
    required this.onPressed,
  });

  final _SkillActionData data;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skill = data.skill;
    final status = skill.used
        ? '사용함'
        : skill.available
            ? null
            : '지금은 사용 불가';
    return Semantics(
      button: true,
      enabled: !busy && skill.available,
      label:
          '${skill.name}. ${skill.description}${status == null ? '' : '. $status'}',
      child: Tooltip(
        message: skill.description,
        child: OutlinedButton.icon(
          onPressed: busy || !skill.available ? null : onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          icon: Icon(data.icon),
          label: Text(status == null ? skill.name : '${skill.name} · $status'),
        ),
      ),
    );
  }
}

Future<void> _activateSkill(
  BuildContext context,
  WidgetRef ref,
  _SkillActionData action,
) async {
  final modes = action.skill.modes;
  String? modeCode;
  if (modes.length == 1) {
    modeCode = modes.single.code;
  } else if (modes.length > 1) {
    modeCode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(action.skill.name,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(action.skill.description),
              const SizedBox(height: 16),
              ...modes.map(
                (mode) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, mode.code),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(48, 48),
                    ),
                    child: Text(mode.label),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (modeCode == null) return;
  }
  final success = await ref
      .read(expeditionControllerProvider.notifier)
      .useSkill(action.type, modeCode: modeCode);
  if (success) HapticFeedback.lightImpact();
}
