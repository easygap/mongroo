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
    final returnRelationship =
        returnScene?['relationship_cue'] is Map<String, dynamic>
            ? returnScene!['relationship_cue'] as Map<String, dynamic>
            : null;
    final storyCue = summary['story_cue'] is Map<String, dynamic>
        ? summary['story_cue'] as Map<String, dynamic>
        : null;
    final story =
        storyCue == null ? null : ExpeditionStageStory.fromJson(storyCue);
    final storyStageNo = storyCue?['stage_no'] is num
        ? (storyCue!['stage_no'] as num).toInt()
        : null;
    final audioEnabled = ref.watch(
      expeditionBattleSettingsProvider.select(
        (settings) => settings.audioEnabled,
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (story != null) ...[
                  _StageStoryRevealCard(
                    key: ValueKey('stage-story-${story.code}'),
                    story: story,
                    audioEnabled: audioEnabled,
                  ),
                  const SizedBox(height: 12),
                ],
                MongrooPanel(
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
                              if (returnRelationship != null) ...[
                                const SizedBox(height: 10),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surface
                                        .withAlpha(145),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.group_outlined,
                                          size: 19,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                returnRelationship['title']
                                                        as String? ??
                                                    '함께 돌아온 순간',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                returnRelationship['caption']
                                                        as String? ??
                                                    '',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              for (final member
                                  in (returnScene['members'] as List? ??
                                      const []))
                                if (member is Map<String, dynamic>)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    leading: Icon(
                                      member['is_guide'] == true
                                          ? Icons.assistant_outlined
                                          : Icons.favorite_outline_rounded,
                                    ),
                                    title: Text(
                                        member['name'] as String? ?? '탐험대원'),
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
                            if (storyStageNo != null) {
                              await ref
                                  .read(expeditionControllerProvider.notifier)
                                  .markStageStorySeen(storyStageNo);
                            }
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}

const _archivePostcardFrames = <String>[
  'assets/adventure/story/archive-postcard-reveal-v1/frame-00.webp',
  'assets/adventure/story/archive-postcard-reveal-v1/frame-01.webp',
  'assets/adventure/story/archive-postcard-reveal-v1/frame-02.webp',
  'assets/adventure/story/archive-postcard-reveal-v1/frame-03.webp',
  'assets/adventure/story/archive-postcard-reveal-v1/frame-04.webp',
  'assets/adventure/story/archive-postcard-reveal-v1/frame-05.webp',
];

List<String> _storyFrames(String? asset) => switch (asset) {
      'archive_postcard_reveal_v1' => _archivePostcardFrames,
      _ => const [],
    };

/// 최초 클리어에서 1.2초 안에 보여 주는 시각 중심 이야기 장면.
///
/// 이미지 생성 원본을 정리한 투명 프레임을 실제 순서로 교체한다. 장면 설명은
/// 두 문장 이하로 제한하고 전문은 도서관에서 다시 본다.
class _StageStoryRevealCard extends StatefulWidget {
  const _StageStoryRevealCard({
    super.key,
    required this.story,
    required this.audioEnabled,
    this.replay = false,
  });

  final ExpeditionStageStory story;
  final bool audioEnabled;
  final bool replay;

  @override
  State<_StageStoryRevealCard> createState() => _StageStoryRevealCardState();
}

class _StageStoryRevealCardState extends State<_StageStoryRevealCard> {
  static const _timings = <Duration>[
    Duration(milliseconds: 150),
    Duration(milliseconds: 150),
    Duration(milliseconds: 150),
    Duration(milliseconds: 170),
    Duration(milliseconds: 190),
    Duration(milliseconds: 420),
  ];

  late final ExpeditionCombatAudio _audio;
  Timer? _frameTimer;
  int _frame = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _audio = ExpeditionCombatAudio(enabled: widget.audioEnabled);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final frames = _storyFrames(widget.story.visualAsset);
    if (frames.isEmpty || MediaQuery.disableAnimationsOf(context)) {
      _frame = frames.isEmpty ? 0 : frames.length - 1;
      _playRevealSound();
      return;
    }
    Future.wait<void>([
      for (final asset in frames) precacheImage(AssetImage(asset), context),
    ]).then((_) {
      if (!mounted) return;
      _playRevealSound();
      _scheduleFrame();
    }).ignore();
  }

  @override
  void didUpdateWidget(covariant _StageStoryRevealCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioEnabled != widget.audioEnabled) {
      unawaited(_audio.setEnabled(widget.audioEnabled));
    }
  }

  void _playRevealSound() {
    if (widget.story.audioCue == 'story_postcard_reveal') {
      unawaited(
        _audio.play(ExpeditionCombatSound.storyReveal, volume: 0.62),
      );
    }
  }

  void _scheduleFrame() {
    final frames = _storyFrames(widget.story.visualAsset);
    if (_frame >= frames.length - 1) return;
    _frameTimer = Timer(_timings[_frame], () {
      if (!mounted) return;
      setState(() => _frame += 1);
      _scheduleFrame();
    });
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    unawaited(_audio.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final frames = _storyFrames(widget.story.visualAsset);
    final scene = expeditionSceneTheme(widget.story.sceneKey);
    return Semantics(
      liveRegion: !widget.replay,
      image: true,
      label: '${widget.story.title}. ${widget.story.caption}',
      child: MongrooPanel(
        key: const ValueKey('stage-story-reveal-card'),
        padding: EdgeInsets.zero,
        radius: 20,
        borderColor: scene.accent.withAlpha(120),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  scene.assetPath,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.1),
                      radius: 0.82,
                      colors: [
                        scene.accent.withAlpha(78),
                        palette.night.withAlpha(190),
                      ],
                    ),
                  ),
                ),
                if (frames.isNotEmpty)
                  Positioned.fill(
                    bottom: 62,
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 70),
                      child: Image.asset(
                        frames[_frame.clamp(0, frames.length - 1)],
                        key: ValueKey('story-frame-$_frame'),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          palette.night.withAlpha(242),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '제 ${widget.story.chapter}장 · ${widget.story.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppTheme.onNight,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.story.caption,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.onNightMuted,
                                      height: 1.35,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: MongrooTag(
                    label: widget.replay ? '기록 다시보기' : '새 이야기',
                    icon: widget.replay
                        ? Icons.replay_rounded
                        : Icons.auto_stories_outlined,
                    backgroundColor: scheme.surface.withAlpha(232),
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
