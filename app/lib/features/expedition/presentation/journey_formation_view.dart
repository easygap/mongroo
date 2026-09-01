part of 'journey_screen.dart';

final _journeyRosterProvider =
    FutureProvider.autoDispose<List<ExpeditionRosterItem>>(
  (ref) => ref.watch(expeditionRepositoryProvider).getRoster(),
);

/// 이번 구간 편성 — 갈림길 하나와 두 자리.
///
/// 다녀온 캐릭터는 목록에 남기되 고를 수 없게 한다. 숨기면 "왜 없지?"가 되고,
/// 회색으로 남겨 두면 "이번 개척에서는 이미 다녀왔구나"가 된다.
class _JourneyFormationView extends ConsumerStatefulWidget {
  const _JourneyFormationView({required this.journey});

  final Journey journey;

  @override
  ConsumerState<_JourneyFormationView> createState() =>
      _JourneyFormationViewState();
}

class _JourneyFormationViewState extends ConsumerState<_JourneyFormationView> {
  String? _routeCode;
  final List<int> _picked = [];

  String get _selectedRoute =>
      _routeCode ?? widget.journey.nextRoutes.firstOrNull?.code ?? '';

  void _toggle(int plantId) {
    setState(() {
      if (_picked.remove(plantId)) return;
      if (_picked.length >= widget.journey.partySize) return;
      _picked.add(plantId);
    });
  }

  Future<void> _depart() async {
    final started = await ref
        .read(journeyControllerProvider.notifier)
        .departLeg(routeCode: _selectedRoute, plantIds: List.of(_picked));
    if (!started || !mounted) return;
    // 구간은 평범한 탐험이다. 걷는 화면은 이미 있는 그 화면이다.
    //
    // 다만 그 화면의 상태를 **먼저 다시 받아야** 한다. 탐험 컨트롤러는 이 화면에
    // 들어오기 전에 이미 살아 있고, 그때는 진행 중인 run이 없었다. 그대로 밀어
    // 넣으면 방금 연 구간 대신 낡은 허브가 뜬다.
    await ref.read(expeditionControllerProvider.notifier).load();
    if (!mounted) return;
    await context.push('/expedition');
    if (!mounted) return;
    await ref.read(journeyControllerProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journey = widget.journey;
    final roster = ref.watch(_journeyRosterProvider);
    final busy = ref.watch(
      journeyControllerProvider.select((value) => value.busy != null),
    );
    final used = journey.usedPlantIds.toSet();

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      children: [
        _JourneyRibbon(journey: journey),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${journey.currentLegIndex + 1}구간 · 어느 길로 갈까요',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '고른 길에 따라 걷는 곳이 달라져요. 멀리 갈수록 귀환할 때의 '
                '보상 기준도 함께 올라가요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final route in journey.nextRoutes) ...[
                _RouteCard(
                  route: route,
                  selected: route.code == _selectedRoute,
                  onTap: busy
                      ? null
                      : () => setState(() => _routeCode = route.code),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
              Text('이번 구간에 설 두 사람', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '${_picked.length}명을 골랐어요. 남은 '
                '${journey.partySize - _picked.length}자리는 길잡이가 채워요.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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
                      '길잡이 둘로도 이 구간을 걸을 수 있어요.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final item in eligible)
                        _RosterRow(
                          item: item,
                          picked: _picked.contains(item.plantId),
                          alreadyWalked: used.contains(item.plantId),
                          onTap: busy ? null : () => _toggle(item.plantId),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey('journey-depart'),
                onPressed: busy || _selectedRoute.isEmpty ? null : _depart,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.hiking_rounded),
                label: const Text('이 길로 떠나기'),
              ),
              if (journey.legs.isNotEmpty) ...[
                const SizedBox(height: 10),
                TextButton(
                  key: const ValueKey('journey-return-from-formation'),
                  onPressed: busy
                      ? null
                      : () => ref
                          .read(journeyControllerProvider.notifier)
                          .returnHome(),
                  child: const Text('여기서 마치고 돌아가기'),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '여기서 앱을 닫아도 개척은 그대로 남아요. 나중에 이어서 걸을 수 있어요.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.route,
    required this.selected,
    required this.onTap,
  });

  final JourneyRoute route;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('journey-route-${route.code}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: MongrooPanel(
          borderColor: selected ? scheme.primary : null,
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(route.name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      route.hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({
    required this.item,
    required this.picked,
    required this.alreadyWalked,
    required this.onTap,
  });

  final ExpeditionRosterItem item;
  final bool picked;
  final bool alreadyWalked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CheckboxListTile(
      key: ValueKey('journey-roster-${item.plantId}'),
      value: picked,
      onChanged: alreadyWalked || onTap == null ? null : (_) => onTap!(),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(item.name),
      subtitle: Text(
        alreadyWalked
            ? '이번 개척에서 이미 한 구간을 걸었어요'
            : '${item.speciesName} · ${item.stage}단계',
        style: alreadyWalked
            ? theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
    );
  }
}
