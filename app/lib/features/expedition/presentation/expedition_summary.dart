part of 'expedition_screen.dart';

// 귀환 결과와 획득 보상을 표시하고 다음 마음일기 행동으로 연결한다.
class _ExpeditionSummary extends ConsumerWidget {
  const _ExpeditionSummary({required this.expedition});

  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completed = expedition.run.status == 'completed';
    final summary = expedition.summary ?? const {};
    final reward = summary['reward'] is Map<String, dynamic>
        ? summary['reward'] as Map<String, dynamic>
        : null;
    final returnScene = summary['return_scene'] is Map<String, dynamic>
        ? summary['return_scene'] as Map<String, dynamic>
        : null;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: MongrooPanel(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    completed
                        ? Icons.home_filled
                        : Icons.health_and_safety_outlined,
                    size: 52,
                    color: completed
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.tertiary,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    summary['title'] as String? ?? '탐험에서 돌아왔어요',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    completed
                        ? '길에서 고른 선택과 캐릭터의 활약이 탐험 기록에 남았어요.'
                        : '무리하지 않고 돌아오는 것도 좋은 탐험 판단이에요.',
                    textAlign: TextAlign.center,
                  ),
                  if (returnScene != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withAlpha(130),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            returnScene['title'] as String? ?? '함께 돌아온 기록',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 5),
                          Text(returnScene['caption'] as String? ?? ''),
                          const SizedBox(height: 8),
                          for (final member
                              in (returnScene['members'] as List? ?? const []))
                            if (member is Map<String, dynamic>)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                leading: Icon(
                                  member['is_guide'] == true
                                      ? Icons.assistant_outlined
                                      : Icons.favorite_outline_rounded,
                                ),
                                title:
                                    Text(member['name'] as String? ?? '탐험대원'),
                                subtitle: Text(
                                  member['contribution'] as String? ??
                                      '함께 무사히 돌아왔어요.',
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                  if (reward != null) ...[
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final event
                            in (reward['events'] as List? ?? const []))
                          if (event is Map<String, dynamic>) ...[
                            MongrooTag(
                              label: '성장 +${event['exp_delta'] ?? 0}',
                              icon: Icons.trending_up,
                            ),
                            MongrooTag(
                              label: '씨앗 +${event['seed_delta'] ?? 0}',
                              icon: Icons.grass_outlined,
                            ),
                          ],
                      ],
                    ),
                  ],
                  if (expedition.loot.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    ...expedition.loot.map(
                      (loot) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(loot.name),
                        trailing: Text('×${loot.quantity}'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await ref
                            .read(expeditionControllerProvider.notifier)
                            .leaveSummary();
                        if (expedition.run.mode == 'tutorial' &&
                            context.mounted) {
                          await Navigator.of(context).maybePop();
                        }
                      },
                      icon: Icon(
                        expedition.run.mode == 'tutorial'
                            ? Icons.home_outlined
                            : Icons.list_alt_outlined,
                      ),
                      label: Text(
                        expedition.run.mode == 'tutorial'
                            ? '홈으로 돌아가 쉬기'
                            : '탐험 목록으로',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(description, textAlign: TextAlign.center),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      );
}

String _formLabel(String form) => switch (form) {
      'sunny' => '햇살',
      'rainy' => '빗결',
      'ember' => '불씨',
      'moonlit' => '달빛',
      'sparkling' => '반짝임',
      _ => '모자이크',
    };
