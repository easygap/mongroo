part of 'joint_guard_screen.dart';

/// 입구 — 어떤 짐승의 꿈으로 갈지 고른다.
///
/// 잠긴 짐승도 숨기지 않는다. 무엇이 기다리는지 알아야 열어 볼 마음이 생기고,
/// 잠긴 이유는 배지가 아니라 문장으로 읽어 준다.
class _JointGuardEntryView extends ConsumerWidget {
  const _JointGuardEntryView({required this.onChoose});

  final void Function(String beastCode, String difficulty) onChoose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(
      jointGuardControllerProvider.select((value) => value.entry),
    );
    if (entry == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('깊은 꿈', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          '너무 깊이 잠든 수호짐승을 여섯이서 살며시 깨워 줘요. '
          '씨앗도 성장도 오가지 않는 자리라, 실패해도 잃는 것이 없어요.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        for (final beast in entry.beasts) ...[
          _BeastCard(
            beast: beast,
            difficulties: entry.difficulties,
            onChoose: onChoose,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _BeastCard extends StatelessWidget {
  const _BeastCard({
    required this.beast,
    required this.difficulties,
    required this.onChoose,
  });

  final JointGuardBeast beast;
  final List<JointGuardDifficulty> difficulties;
  final void Function(String beastCode, String difficulty) onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return MongrooPanel(
      key: ValueKey('joint-guard-beast-${beast.code}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(beast.name, style: theme.textTheme.titleMedium),
              ),
              const SizedBox(width: 8),
              MongrooTag(
                label: beast.unlocked ? '열림' : '아직',
                icon: beast.unlocked
                    ? Icons.bedtime_rounded
                    : Icons.lock_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            beast.dreamScene,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 4),
          Text(
            '${koreanObject(beast.holding)} 꼭 끌어안고 있어요.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (!beast.unlocked)
            Text(
              beast.lockedReason ?? '아직 열리지 않았어요.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final difficulty in difficulties)
                  _DifficultyButton(
                    beast: beast,
                    difficulty: difficulty,
                    onChoose: onChoose,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DifficultyButton extends StatelessWidget {
  const _DifficultyButton({
    required this.beast,
    required this.difficulty,
    required this.onChoose,
  });

  final JointGuardBeast beast;
  final JointGuardDifficulty difficulty;
  final void Function(String beastCode, String difficulty) onChoose;

  @override
  Widget build(BuildContext context) {
    final label = '${difficulty.name} · ${difficulty.layers}겹';
    return Tooltip(
      message: difficulty.summary,
      child: difficulty.tutorial
          ? FilledButton.tonal(
              key: ValueKey('joint-guard-start-${difficulty.code}'),
              onPressed: () => onChoose(beast.code, difficulty.code),
              child: Text(label),
            )
          : OutlinedButton(
              key: ValueKey('joint-guard-start-${difficulty.code}'),
              onPressed: () => onChoose(beast.code, difficulty.code),
              child: Text(label),
            ),
    );
  }
}
