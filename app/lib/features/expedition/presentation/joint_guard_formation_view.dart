part of 'joint_guard_screen.dart';

final _jointGuardRosterProvider =
    FutureProvider.autoDispose<List<ExpeditionRosterItem>>(
  (ref) => ref.watch(expeditionRepositoryProvider).getRoster(),
);

/// 편성 — 여섯 자리를 채운다.
///
/// 빈자리는 길잡이가 대신 선다. 역할도 품종도 요구하지 않으므로 캐릭터 하나만
/// 있어도 명단이 서고, 그것을 화면에서도 재촉하지 않는다.
class _JointGuardFormationView extends ConsumerStatefulWidget {
  const _JointGuardFormationView({
    required this.beastCode,
    required this.difficulty,
    required this.onBack,
  });

  final String beastCode;
  final String difficulty;
  final VoidCallback onBack;

  @override
  ConsumerState<_JointGuardFormationView> createState() =>
      _JointGuardFormationViewState();
}

class _JointGuardFormationViewState
    extends ConsumerState<_JointGuardFormationView> {
  /// 여섯 자리. 앞 셋이 전열, 뒤 셋이 후열이다. null이면 길잡이가 선다.
  final List<int?> _slots = List<int?>.filled(6, null);

  static const _frontCount = 3;

  bool _isPicked(int plantId) => _slots.contains(plantId);

  void _toggle(int plantId) {
    setState(() {
      final at = _slots.indexOf(plantId);
      if (at >= 0) {
        _slots[at] = null;
        return;
      }
      final free = _slots.indexOf(null);
      if (free >= 0) _slots[free] = plantId;
    });
  }

  void _clearSlot(int index) => setState(() => _slots[index] = null);

  List<Map<String, Object?>> _formation() => [
        for (final (index, plantId) in _slots.indexed)
          {
            'plant_id': plantId,
            'formation': index < _frontCount ? 'front' : 'back',
          },
      ];

  Future<void> _start() async {
    await ref.read(jointGuardControllerProvider.notifier).start(
          beastCode: widget.beastCode,
          difficulty: widget.difficulty,
          formation: _formation(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roster = ref.watch(_jointGuardRosterProvider);
    final busy = ref.watch(
      jointGuardControllerProvider.select((value) => value.busy != null),
    );
    final picked = _slots.whereType<int>().length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('탐험대 편성', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          '앞의 셋이 무대에 서고 뒤의 셋은 기다려요. 빈자리는 길잡이가 대신 서요.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _SlotRow(
          title: '전열',
          hint: '지금 명령을 받는 셋이에요.',
          indexes: const [0, 1, 2],
          slots: _slots,
          roster: roster.valueOrNull ?? const [],
          onClear: _clearSlot,
        ),
        const SizedBox(height: 12),
        _SlotRow(
          title: '후열',
          hint: '라운드 사이에 한 명씩 바꿔 세울 수 있어요.',
          indexes: const [3, 4, 5],
          slots: _slots,
          roster: roster.valueOrNull ?? const [],
          onClear: _clearSlot,
        ),
        const SizedBox(height: 20),
        Text('함께 갈 캐릭터', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        roster.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text(
            '명단을 불러오지 못했어요.',
            style: theme.textTheme.bodyMedium,
          ),
          data: (items) {
            final eligible =
                items.where((item) => item.eligible).toList(growable: false);
            if (eligible.isEmpty) {
              return Text(
                '새싹 단계부터 함께 갈 수 있어요. 길잡이 여섯으로도 다녀올 수 있어요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }
            return Column(
              children: [
                for (final item in eligible)
                  _RosterTile(
                    item: item,
                    picked: _isPicked(item.plantId),
                    onTap: () => _toggle(item.plantId),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('joint-guard-depart'),
          onPressed: busy ? null : _start,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bedtime_rounded),
          label: const Text('꿈으로 들어가기'),
        ),
        const SizedBox(height: 8),
        Text(
          picked == 0
              ? '길잡이 여섯으로 들어가요. 그래도 끝까지 갈 수 있어요.'
              : '$picked명이 함께 가고 나머지는 길잡이가 채워요.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: widget.onBack, child: const Text('다른 꿈 고르기')),
      ],
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.title,
    required this.hint,
    required this.indexes,
    required this.slots,
    required this.roster,
    required this.onClear,
  });

  final String title;
  final String hint;
  final List<int> indexes;
  final List<int?> slots;
  final List<ExpeditionRosterItem> roster;
  final void Function(int index) onClear;

  String _nameFor(int plantId) =>
      roster
          .where((item) => item.plantId == plantId)
          .firstOrNull
          ?.name ??
      '대원';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MongrooPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MongrooTag(label: title),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final index in indexes)
                if (slots[index] case final int plantId)
                  InputChip(
                    key: ValueKey('joint-guard-slot-$index'),
                    label: Text(_nameFor(plantId)),
                    onDeleted: () => onClear(index),
                    deleteButtonTooltipMessage: '자리 비우기',
                  )
                else
                  Chip(
                    key: ValueKey('joint-guard-slot-$index'),
                    avatar: const Icon(Icons.auto_stories_outlined, size: 16),
                    label: const Text('길잡이'),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({
    required this.item,
    required this.picked,
    required this.onTap,
  });

  final ExpeditionRosterItem item;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      key: ValueKey('joint-guard-roster-${item.plantId}'),
      value: picked,
      onChanged: (_) => onTap(),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(item.name),
      subtitle: Text('${item.speciesName} · ${item.stage}단계'),
    );
  }
}
