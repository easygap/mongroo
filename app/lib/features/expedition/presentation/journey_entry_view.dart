part of 'journey_screen.dart';

/// 입구 — 어느 방향으로 떠날지 고른다.
///
/// 잠긴 방향도 숨기지 않는다. 무엇이 기다리는지 알아야 열어 볼 마음이 생기고,
/// 잠긴 이유는 배지가 아니라 문장으로 읽어 준다. 다만 **구간의 내용은 적지
/// 않는다** — 어디로 갈지는 야영지에서 그때 고르는 것이 이 콘텐츠다.
class _JourneyEntryView extends ConsumerWidget {
  const _JourneyEntryView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(
      journeyControllerProvider.select((value) => value.entry),
    );
    if (entry == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('온실 밖으로 멀리', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          '두세 구간을 서로 다른 조가 나눠 맡아요. 한 캐릭터는 한 구간에만 서고, '
          '빈자리는 길잡이가 채워요.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        for (final direction in entry.directions) ...[
          _DirectionCard(direction: direction),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _DirectionCard extends ConsumerWidget {
  const _DirectionCard({required this.direction});

  final JourneyDirection direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final busy = ref.watch(
      journeyControllerProvider.select((value) => value.busy != null),
    );
    final enabled = !direction.locked && !busy;

    return Semantics(
      button: enabled,
      label: '${direction.name}. ${direction.summary} '
          '${direction.locked ? direction.lockReason ?? '' : ''}',
      child: MongrooPanel(
        borderColor: direction.locked ? null : scheme.primary.withAlpha(90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  direction.locked ? Icons.lock_outline : Icons.map_outlined,
                  color: direction.locked ? scheme.outline : scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(direction.name, style: theme.textTheme.titleMedium),
                ),
                MongrooTag(label: '${direction.maxLegs}구간'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              direction.summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Fact(
                  icon: Icons.schedule_rounded,
                  label: '${direction.minMinutes}~${direction.maxMinutes}분',
                ),
                _Fact(
                  icon: Icons.groups_2_outlined,
                  label: '구간마다 ${direction.partySize}명',
                ),
                _Fact(
                  icon: Icons.person_outline,
                  label: '내 캐릭터 최대 ${direction.maxOwnMembers}명',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (direction.locked)
              Text(
                direction.lockReason ?? '아직 열리지 않았어요.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: ValueKey('journey-start-${direction.code}'),
                      onPressed: enabled
                          ? () => ref
                              .read(journeyControllerProvider.notifier)
                              .start(
                                directionCode: direction.code,
                                mode: 'heart_resonance',
                              )
                          : null,
                      icon: const Icon(Icons.favorite_outline),
                      label: const Text('마음 공명 개척'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: ValueKey('journey-free-${direction.code}'),
                    onPressed: enabled
                        ? () => ref
                            .read(journeyControllerProvider.notifier)
                            .start(
                              directionCode: direction.code,
                              mode: 'free_explore',
                            )
                        : null,
                    child: const Text('보상 없이'),
                  ),
                ],
              ),
            if (!direction.locked) ...[
              const SizedBox(height: 6),
              Text(
                '마음 공명은 오늘 마음 일기를 쓴 뒤 열려요. 보상은 가장 멀리 간 '
                '곳 기준으로 귀환할 때 한 번만 받아요.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
