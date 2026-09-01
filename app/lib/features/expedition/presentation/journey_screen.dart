import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/mongroo_ui.dart';
import '../data/expedition_repository.dart';
import '../domain/expedition_models.dart';
import '../domain/journey_models.dart';
import 'expedition_controller.dart';
import 'journey_controller.dart';

part 'journey_entry_view.dart';
part 'journey_formation_view.dart';
part 'journey_camp_view.dart';

/// 장거리 개척 화면.
///
/// 한 화면 안에서 네 장면이 이어진다 — 입구(어느 방향으로), 편성(이번 구간에
/// 누가), 야영지(더 갈지 여기서 접을지), 그리고 원정 기록. **지금 어느
/// 장면인지는 서버가 준 개척 상태에서 읽는다.** 앱이 따로 단계를 세면 앱을
/// 껐다 켜거나 구간을 걷다 나갔을 때 서버와 어긋난다.
///
/// 구간 안에서 걷고 사건을 만나는 것은 지금까지의 탐험 화면 그대로다. 여기서는
/// 그 화면으로 보내고, 돌아오면 야영지를 보여 준다.
class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(journeyControllerProvider);

    ref.listen<String?>(
      journeyControllerProvider.select((value) => value.error),
      (previous, next) {
        if (next == null || next == previous) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(next)));
      },
    );

    final journey = state.journey;
    return Scaffold(
      appBar: AppBar(
        title: Text(journey?.directionName ?? '장거리 개척'),
      ),
      body: SafeArea(
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : switch (journey) {
                null => const _JourneyEntryView(),
                final Journey done when done.finished =>
                  _JourneySummaryView(journey: done),
                final Journey walking when walking.activeRunId != null =>
                  _JourneyWalkingView(journey: walking),
                final Journey camp when camp.canContinue =>
                  _JourneyFormationView(journey: camp),
                final Journey camp => _JourneyCampView(journey: camp),
              },
      ),
    );
  }
}

/// 원정 띠 — `집 → 지나온 구간 → 지금 → 귀환`.
///
/// 설계서 10.3이 요구하는 화면 상단 고정 요소다. 아직 가지 않은 구간은 이름을
/// 보여 주지 않는다. 다음에 무엇이 있는지 미리 알려 주면 야영지에서 고르는
/// 일이 의미를 잃는다.
class _JourneyRibbon extends StatelessWidget {
  const _JourneyRibbon({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stops = <_RibbonStop>[
      const _RibbonStop(label: '집', done: true),
      for (var index = 0; index < journey.maxLegs; index++)
        _stopFor(index),
      _RibbonStop(
        label: '귀환',
        done: journey.finished,
        current: journey.atCamp && !journey.canContinue,
      ),
    ];

    return Semantics(
      label: '원정 띠. ${stops.map((stop) => stop.label).join(', ')}',
      child: ExcludeSemantics(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final (index, stop) in stops.indexed) ...[
                if (index > 0)
                  Container(
                    width: 18,
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: stop.done
                        ? scheme.primary.withAlpha(150)
                        : scheme.outlineVariant,
                  ),
                _RibbonChip(stop: stop),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _RibbonStop _stopFor(int index) {
    final leg = journey.legs.where((leg) => leg.legIndex == index).firstOrNull;
    if (leg == null) {
      // 아직 가지 않은 구간. 이름 대신 `미지의 구간`이다.
      return _RibbonStop(
        label: '미지의 구간',
        current: journey.canContinue && index == journey.currentLegIndex,
      );
    }
    return _RibbonStop(
      label: leg.routeName,
      done: leg.objectiveSecured,
      current: leg.walking,
      failed: !leg.walking && !leg.objectiveSecured,
    );
  }
}

class _RibbonStop {
  const _RibbonStop({
    required this.label,
    this.done = false,
    this.current = false,
    this.failed = false,
  });

  final String label;
  final bool done;
  final bool current;
  final bool failed;
}

class _RibbonChip extends StatelessWidget {
  const _RibbonChip({required this.stop});

  final _RibbonStop stop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = stop.current
        ? scheme.primaryContainer
        : stop.done
            ? scheme.surfaceContainerHighest
            : Colors.transparent;
    final border = stop.current ? scheme.primary : scheme.outlineVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            stop.done
                ? Icons.check_rounded
                : stop.failed
                    ? Icons.bookmark_border_rounded
                    : stop.current
                        ? Icons.place_rounded
                        : Icons.more_horiz_rounded,
            size: 14,
            color: stop.current ? scheme.onPrimaryContainer : scheme.outline,
          ),
          const SizedBox(width: 5),
          Text(
            stop.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: stop.current
                  ? scheme.onPrimaryContainer
                  : stop.done
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 지나온 구간을 사진처럼 한 줄씩. 누가 갔는지가 이 기록의 본체다.
class _JourneyLegList extends StatelessWidget {
  const _JourneyLegList({required this.legs});

  final List<JourneyLeg> legs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (legs.isEmpty) {
      return Text(
        '아직 걸은 구간이 없어요.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: [
        for (final leg in legs) ...[
          MongrooPanel(
            child: Row(
              children: [
                Icon(
                  leg.objectiveSecured
                      ? Icons.verified_rounded
                      : leg.walking
                          ? Icons.directions_walk_rounded
                          : Icons.bookmark_border_rounded,
                  color: leg.objectiveSecured
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${leg.legIndex + 1}구간 · ${leg.routeName}',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${leg.regionName} · '
                        '${leg.party.map((member) => member.name).join(', ')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
