import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../expedition/presentation/expedition_scene.dart';
import '../../expedition/presentation/moss_archive_scene.dart';
import '../domain/trial_progress.dart';
import 'trial_controller.dart';

class TrialScreen extends ConsumerStatefulWidget {
  const TrialScreen({super.key});

  @override
  ConsumerState<TrialScreen> createState() => _TrialScreenState();
}

class _TrialScreenState extends ConsumerState<TrialScreen> {
  final _scrollController = ScrollController();
  late final ProviderSubscription<TrialStage> _stageSubscription;

  @override
  void initState() {
    super.initState();
    _stageSubscription = ref.listenManual(
      trialControllerProvider.select((state) => state.progress.stage),
      (previous, next) {
        if (previous == next) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        });
      },
    );
  }

  @override
  void dispose() {
    _stageSubscription.close();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trialControllerProvider);
    final signedIn =
        ref.watch(authControllerProvider).status == AuthStatus.signedIn;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final progress = state.progress;

    void close() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(signedIn ? '/home' : '/login');
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: signedIn ? '홈으로 돌아가기' : '로그인으로 돌아가기',
          onPressed: close,
          icon: const Icon(Icons.close_rounded),
        ),
        title: const Text('몽그루 3분 체험'),
        actions: [
          if (progress.stage != TrialStage.welcome)
            IconButton(
              tooltip: '체험 처음부터 다시 시작',
              onPressed: () => _confirmReset(context, ref),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    constraints.maxWidth >= 720 ? 32 : 16,
                    12,
                    constraints.maxWidth >= 720 ? 32 : 16,
                    40,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TrialProgressHeader(stage: progress.stage),
                          if (!state.storageAvailable) ...[
                            const SizedBox(height: 10),
                            const _StorageWarning(),
                          ],
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: reduceMotion
                                ? Duration.zero
                                : MongrooMotion.standard,
                            switchInCurve: MongrooMotion.enter,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, .025),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                            child: switch (progress.stage) {
                              TrialStage.welcome => _TrialWelcome(
                                  key: const ValueKey('welcome'),
                                  onStart: ref
                                      .read(trialControllerProvider.notifier)
                                      .start,
                                ),
                              TrialStage.diary => _TrialDiary(
                                  key: const ValueKey('diary'),
                                  progress: progress,
                                  onSubmit: ({
                                    required emotionCode,
                                    required text,
                                  }) =>
                                      ref
                                          .read(
                                              trialControllerProvider.notifier)
                                          .saveDiary(
                                            text: text,
                                            emotionCode: emotionCode,
                                          ),
                                ),
                              TrialStage.growth => _TrialGrowth(
                                  key: const ValueKey('growth'),
                                  progress: progress,
                                  onContinue: ref
                                      .read(trialControllerProvider.notifier)
                                      .openExploration,
                                ),
                              TrialStage.exploration => _TrialExploration(
                                  key: const ValueKey('exploration'),
                                  progress: progress,
                                  onPath: ref
                                      .read(trialControllerProvider.notifier)
                                      .choosePath,
                                  onResolve: ref
                                      .read(trialControllerProvider.notifier)
                                      .resolveEvent,
                                ),
                              TrialStage.complete => _TrialComplete(
                                  key: const ValueKey('complete'),
                                  progress: progress,
                                  signedIn: signedIn,
                                  onPrimary: () => context.go(
                                    signedIn ? '/home' : '/signup',
                                  ),
                                  onReset: ref
                                      .read(trialControllerProvider.notifier)
                                      .reset,
                                ),
                            },
                          ),
                          const SizedBox(height: 18),
                          const _TrialSupportLink(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// 체험 어느 단계에서든 닿는 지원 안내 입구.
///
/// 본편은 글에서 위험 신호를 읽으면 지원 화면을 먼저 띄운다. 체험에는 읽어 줄
/// 서버가 없어서 그 길이 통째로 없었다 — 마음을 적는 화면인데 힘든 사람이
/// 갈 곳이 한 군데도 없다는 뜻이다. 판정을 흉내 내는 대신 **늘 열려 있는
/// 문 하나**를 둔다. 놀라게 하지 않도록 조용한 글자 버튼이다.
class _TrialSupportLink extends StatelessWidget {
  const _TrialSupportLink();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          key: const Key('trial-support-link'),
          onPressed: () => context.push('/safety'),
          icon: const Icon(Icons.favorite_border_rounded, size: 18),
          label: const Text('지금 많이 힘들다면, 도움받을 수 있는 곳'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.refresh_rounded),
      title: const Text('체험을 처음부터 다시 할까요?'),
      content: const Text('이 기기에 저장된 체험용 일기와 선택만 지워져요. 정식 계정 데이터는 건드리지 않아요.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('계속하기'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('처음부터'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(trialControllerProvider.notifier).reset();
  }
}

class _TrialProgressHeader extends StatelessWidget {
  const _TrialProgressHeader({required this.stage});

  final TrialStage stage;

  int get step => switch (stage) {
        TrialStage.welcome => 0,
        TrialStage.diary => 1,
        TrialStage.growth => 2,
        TrialStage.exploration => 3,
        TrialStage.complete => 4,
      };

  String get label => switch (stage) {
        TrialStage.welcome => '준비',
        TrialStage.diary => '마음 기록',
        TrialStage.growth => '성장',
        TrialStage.exploration => '직접 탐험',
        TrialStage.complete => '귀환',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '체험 진행 $step/4, $label 단계',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  step == 0 ? '회원가입 없는 로컬 체험' : '$step/4 · $label',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const _LocalOnlyBadge(),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: step / 4,
              color: scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalOnlyBadge extends StatelessWidget {
  const _LocalOnlyBadge();

  @override
  Widget build(BuildContext context) => MongrooTag(
        label: '이 기기에만 저장',
        icon: Icons.phonelink_lock_outlined,
        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
      );
}

class _StorageWarning extends StatelessWidget {
  const _StorageWarning();

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Builder(
          builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            // 붉은 면 위에 본문 기본색을 얹으면 2.3:1이다. 그 면을 위해
            // 마련된 짝 색을 쓴다.
            final foreground = scheme.onErrorContainer;
            return MongrooPanel(
              color: scheme.errorContainer,
              borderColor: scheme.error.withAlpha(85),
              shadowOffset: Offset.zero,
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.storage_outlined, size: 20, color: foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '브라우저 저장소를 사용할 수 없어 이번 화면을 닫으면 체험 진행이 사라져요.',
                      style: TextStyle(color: foreground),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
}

class _TrialWelcome extends StatelessWidget {
  const _TrialWelcome({super.key, required this.onStart});

  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const Key('trial-diary-growth-hero'),
          height: MediaQuery.sizeOf(context).width < 420 ? 220 : 280,
          child: Semantics(
            image: true,
            label: '마음 기록을 받아 따뜻한 방에서 자라는 아기 몽그루',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/illustrations/cozy-room.webp',
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          palette.night.withAlpha(18),
                          Colors.transparent,
                          palette.night.withAlpha(112),
                        ],
                        stops: const [0, .55, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 42,
                    height: MediaQuery.sizeOf(context).width < 420 ? 178 : 222,
                    child: Transform.scale(
                      key: const Key('trial-growth-character'),
                      scale: 2.45,
                      alignment: Alignment.bottomCenter,
                      child: Image.asset(
                        'assets/plants/baby-pot-25d-sprout-sunny.webp',
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    top: 14,
                    child: MongrooTag(
                      label: '마음 기록 → 성장',
                      icon: Icons.edit_note_rounded,
                      backgroundColor: palette.paper.withAlpha(235),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    top: 14,
                    child: MongrooTag(
                      label: '약 3분',
                      icon: Icons.timer_outlined,
                      backgroundColor: palette.paper.withAlpha(235),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.paper.withAlpha(235),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(24),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                        child: Text(
                          '“오늘 마음은 어떤 날씨인가요?”',
                          maxLines: 2,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '가입하기 전에, 마음 하나를 키워 봐요',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '좋고 나쁜 감정을 가르지 않고 지금 마음을 짧게 기록해 보세요. 그 기록으로 캐릭터가 자라고, 원할 때 함께 첫 탐험도 연습할 수 있어요.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MongrooTag(label: '마음 일기', icon: Icons.edit_note_rounded),
            MongrooTag(label: '캐릭터 성장', icon: Icons.spa_outlined),
            MongrooTag(label: '탐험은 보조 활동', icon: Icons.route_outlined),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('trial-start'),
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('기기에서 체험 시작'),
        ),
        const SizedBox(height: 9),
        Text(
          '체험 내용은 서버로 전송되지 않으며 앱 또는 브라우저 데이터를 지우면 함께 사라져요.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _TrialDiary extends StatefulWidget {
  const _TrialDiary({
    super.key,
    required this.progress,
    required this.onSubmit,
  });

  final TrialProgress progress;
  final Future<void> Function({
    required String text,
    required String emotionCode,
  }) onSubmit;

  @override
  State<_TrialDiary> createState() => _TrialDiaryState();
}

class _TrialDiaryState extends State<_TrialDiary> {
  late final TextEditingController _text;
  String? _emotion;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.progress.diaryText);
    _emotion = widget.progress.emotionCode;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting && _emotion != null && _text.text.trim().length >= 10;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    await widget.onSubmit(text: _text.text, emotionCode: _emotion!);
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final choices = const [
      ('sunny', '따뜻함', Icons.wb_sunny_outlined),
      ('rainy', '가라앉음', Icons.water_drop_outlined),
      ('ember', '답답함', Icons.local_fire_department_outlined),
    ];
    return MongrooPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('오늘 마음의 날씨는 어떤가요?',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 7),
          Text(
            '정답은 없어요. 지금 가장 가까운 느낌 하나만 골라 보세요.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in choices)
                ChoiceChip(
                  avatar: Icon(choice.$3, size: 18),
                  label: Text(choice.$2),
                  selected: _emotion == choice.$1,
                  onSelected: _submitting
                      ? null
                      : (_) => setState(() => _emotion = choice.$1),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            '체험에서는 서버 분석 없이 바로 모습을 보여 주기 위해 가까운 느낌을 함께 골라요. 실제 기록은 일기 본문에서 마음의 결을 읽어요.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const Key('trial-diary-field'),
            controller: _text,
            enabled: !_submitting,
            minLines: 4,
            maxLines: 7,
            maxLength: 280,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: '짧은 마음 기록',
              alignLabelWithHint: true,
              hintText: '오늘 기억에 남은 순간과 그때의 느낌을 적어 보세요.',
              helperText: '10자 이상이면 캐릭터가 마음의 결을 받아요.',
              // 안내와 글자 수가 한 줄을 나눠 쓴다. 기본 한 줄로 두면
              // `0/280`에 밀려 `…마음의 결을 받…`에서 끊긴다.
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() {}),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('trial-sample'),
              onPressed: _submitting
                  ? null
                  : () {
                      _text.text = '오늘은 조금 바빴지만 따뜻한 차를 마신 순간 마음이 한결 편안해졌다.';
                      _text.selection = TextSelection.collapsed(
                        offset: _text.text.length,
                      );
                      _emotion ??= 'sunny';
                      setState(() {});
                    },
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('예시로 빠르게 체험'),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('trial-save-diary'),
            onPressed: _canSubmit ? _submit : null,
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.spa_outlined),
            label: Text(_submitting ? '마음을 심는 중…' : '이 마음으로 키워 보기'),
          ),
        ],
      ),
    );
  }
}

class _TrialGrowth extends StatelessWidget {
  const _TrialGrowth({
    super.key,
    required this.progress,
    required this.onContinue,
  });

  final TrialProgress progress;
  final Future<void> Function() onContinue;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final formLabel = switch (progress.growthForm) {
      'sunny' => '따뜻한 햇살형',
      'rainy' => '차분한 빗결형',
      'ember' => '단단한 불씨형',
      _ => '여러 빛의 모자이크형',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 300,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/illustrations/cozy-room.webp',
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        MongrooPalette.of(context).night.withAlpha(95),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: TweenAnimationBuilder<double>(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 420),
                    curve: MongrooMotion.enter,
                    tween: Tween(begin: .90, end: 1),
                    builder: (context, value, child) => Transform.scale(
                      scale: value,
                      child: Opacity(
                        opacity: ((value - .90) * 10).clamp(0, 1),
                        child: child,
                      ),
                    ),
                    child: Image.asset(
                      'assets/plants/baby-pot-25d-sprout-${progress.growthForm}.webp',
                      width: 210,
                      height: 260,
                      fit: BoxFit.contain,
                      semanticLabel: '$formLabel으로 자란 아기 몽그루',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('$formLabel 새싹이 마음을 받았어요',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('마음 일기는 가장 큰 성장 보상이고, 탐험은 키운 캐릭터와 추억을 만드는 보조 활동이에요.'),
        const SizedBox(height: 16),
        const _RewardComparison(),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('trial-open-exploration'),
          onPressed: onContinue,
          icon: const Icon(Icons.explore_outlined),
          label: const Text('함께 첫 탐험 연습'),
        ),
      ],
    );
  }
}

class _RewardComparison extends StatelessWidget {
  const _RewardComparison();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget reward({
          required String title,
          required String value,
          required IconData icon,
          required bool primary,
        }) =>
            MongrooPanel(
              color: primary ? scheme.primaryContainer : scheme.surface,
              borderColor: primary ? scheme.primary.withAlpha(90) : null,
              shadowOffset: Offset.zero,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(icon, color: primary ? scheme.primary : scheme.tertiary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: Theme.of(context).textTheme.labelLarge),
                        Text(value,
                            style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                  ),
                ],
              ),
            );
        final diary = reward(
          title: '마음 일기 · 핵심 성장',
          value: '성장 +30 · 씨앗 +12',
          icon: Icons.edit_note_rounded,
          primary: true,
        );
        final explore = reward(
          title: '첫 탐험 · 보조 성장',
          value: '성장 +4 · 씨앗 +2',
          icon: Icons.route_outlined,
          primary: false,
        );
        if (constraints.maxWidth < 560) {
          return Column(children: [diary, const SizedBox(height: 8), explore]);
        }
        return Row(
          children: [
            Expanded(child: diary),
            const SizedBox(width: 10),
            Expanded(child: explore),
          ],
        );
      },
    );
  }
}

class _TrialExploration extends StatelessWidget {
  const _TrialExploration({
    super.key,
    required this.progress,
    required this.onPath,
    required this.onResolve,
  });

  final TrialProgress progress;
  final Future<void> Function(String path) onPath;
  final Future<void> Function(String choice) onResolve;

  @override
  Widget build(BuildContext context) {
    final selectedPath = progress.selectedPath;
    final sceneKey = selectedPath == 'labels'
        ? 'flooded_cave'
        : selectedPath == 'roots'
            ? 'root_tunnel'
            : 'dungeon_gate';
    final scene = expeditionSceneTheme(sceneKey);
    final sceneTitle = selectedPath == 'labels'
        ? '침수 표찰 동굴'
        : selectedPath == 'roots'
            ? '기억 뿌리 땅굴'
            : '기억 던전 입구';
    final sceneDescription = selectedPath == 'labels'
        ? '수정빛 물길 위로 젖은 이름표가 흘러가요.'
        : selectedPath == 'roots'
            ? '목재 지주 사이로 오래된 뿌리와 광차 길이 엉켜 있어요.'
            : '유리온실 아래의 석문이 열려 있어요. 두 갈래 통로를 직접 살펴보세요.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('장면을 살피고 다음 걸음을 직접 골라요',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 7),
        Text(
          progress.explorationStep == 0
              ? '물길은 관찰, 뿌리 통로는 돌봄에 유리해요. 어느 쪽도 정답은 아니에요.'
              : '선택한 장소에서 사건이 생겼어요. 캐릭터의 능력과 예상 결과를 보고 행동을 골라요.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        MongrooPanel(
          padding: EdgeInsets.zero,
          radius: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: MossArchiveScene(
                  semanticLabel: '동굴과 땅굴, 수호자 소굴과 탑이 지형으로 이어진 체험 탐험 지도',
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(18)),
                  child: _TrialMap(progress: progress, onPath: onPath),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 12),
                child: Text(
                  selectedPath == null
                      ? '입구에서 갈라지는 물길과 뿌리길을 지형에서 직접 골라요.'
                      : '선택한 길의 발자국이 소굴과 기억 탑 방향으로 이어져요.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ExpeditionSceneBackdrop(
            scene: scene,
            semanticLabel: '$sceneTitle 탐험 장면. $sceneDescription',
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: MediaQuery.withNoTextScaling(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: MongrooPalette.of(context).night.withAlpha(205),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: scene.accent.withAlpha(145)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(scene.icon, color: scene.accent, size: 18),
                        const SizedBox(width: 7),
                        Text(
                          sceneTitle,
                          style: const TextStyle(
                            color: AppTheme.onNight,
                            fontWeight: FontWeight.w700,
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
        const SizedBox(height: 10),
        Text(sceneTitle, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(sceneDescription),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : MongrooMotion.standard,
          child: progress.explorationStep == 0
              ? _TrialPathDecision(key: const ValueKey('path'), onPath: onPath)
              : _TrialEventDecision(
                  key: const ValueKey('event'),
                  path: progress.selectedPath!,
                  onResolve: onResolve,
                ),
        ),
      ],
    );
  }
}

class _TrialMap extends StatelessWidget {
  const _TrialMap({required this.progress, required this.onPath});

  final TrialProgress progress;
  final Future<void> Function(String path) onPath;

  @override
  Widget build(BuildContext context) {
    final selected = progress.selectedPath;
    return LayoutBuilder(
      builder: (context, constraints) {
        const nodeSize = 44.0;
        Widget node({
          required String label,
          required double x,
          required double y,
          required bool current,
          VoidCallback? onTap,
          Key? key,
        }) =>
            Positioned(
              left: (x * constraints.maxWidth - nodeSize / 2)
                  .clamp(0, constraints.maxWidth - nodeSize),
              top: (y * constraints.maxHeight - nodeSize / 2)
                  .clamp(0, constraints.maxHeight - nodeSize),
              width: nodeSize,
              height: nodeSize,
              child: _TrialMapNode(
                key: key,
                label: label,
                current: current,
                onTap: onTap,
              ),
            );
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TrialPathPainter(
                  selectedPath: selected,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            node(
              label: '입구',
              x: .08,
              y: .50,
              current: selected == null,
            ),
            node(
              key: const Key('trial-path-labels'),
              label: '표찰길',
              x: .28,
              y: .27,
              current: selected == 'labels',
              onTap: selected == null ? () => onPath('labels') : null,
            ),
            node(
              key: const Key('trial-path-roots'),
              label: '뿌리길',
              x: .29,
              y: .72,
              current: selected == 'roots',
              onTap: selected == null ? () => onPath('roots') : null,
            ),
            node(
              label: '장부지기 소굴',
              x: .69,
              y: .50,
              current: false,
            ),
            node(
              label: '기억 탑',
              x: .84,
              y: .34,
              current: false,
            ),
          ],
        );
      },
    );
  }
}

class _TrialMapNode extends StatelessWidget {
  const _TrialMapNode({
    super.key,
    required this.label,
    required this.current,
    required this.onTap,
  });

  final String label;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Semantics(
      button: enabled,
      selected: current,
      label: '$label${current ? ', 현재 위치' : enabled ? ', 이동 가능' : ''}',
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: onTap,
            radius: 22,
            containedInkWell: true,
            child: Center(
              child: Container(
                width: current
                    ? 22
                    : enabled
                        ? 15
                        : 7,
                height: current
                    ? 22
                    : enabled
                        ? 15
                        : 7,
                transform:
                    enabled ? (Matrix4.identity()..rotateZ(.785398)) : null,
                decoration: BoxDecoration(
                  shape: enabled ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: enabled ? BorderRadius.circular(3) : null,
                  color: current
                      ? const Color(0xFFFFE3A0)
                      : enabled
                          ? const Color(0xFFFFD47A)
                          : AppTheme.onNight.withAlpha(90),
                  border: current
                      ? Border.all(color: Colors.white, width: 2)
                      : enabled
                          ? Border.all(color: Colors.white.withAlpha(210))
                          : null,
                  boxShadow: current || enabled
                      ? [
                          BoxShadow(
                            color: (current
                                    ? const Color(0xFFFFE3A0)
                                    : scheme.primary)
                                .withAlpha(120),
                            blurRadius: 13,
                            spreadRadius: 3,
                          ),
                          BoxShadow(
                            color: Colors.black.withAlpha(120),
                            blurRadius: 5,
                          ),
                        ]
                      : null,
                ),
                child: current
                    ? Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: MongrooPalette.of(context).night,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrialPathPainter extends CustomPainter {
  const _TrialPathPainter({required this.selectedPath, required this.color});

  final String? selectedPath;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final entrance = Offset(.08 * size.width, .50 * size.height);
    final labels = Offset(.28 * size.width, .27 * size.height);
    final roots = Offset(.29 * size.width, .72 * size.height);
    final door = Offset(.69 * size.width, .50 * size.height);
    final drawer = Offset(.84 * size.width, .34 * size.height);
    final pairs = [
      (entrance, labels, selectedPath == 'labels'),
      (entrance, roots, selectedPath == 'roots'),
      (labels, door, selectedPath == 'labels'),
      (roots, door, selectedPath == 'roots'),
      (door, drawer, false),
    ];
    for (final pair in pairs) {
      final path = Path()
        ..moveTo(pair.$1.dx, pair.$1.dy)
        ..cubicTo(
          (pair.$1.dx + pair.$2.dx) / 2,
          pair.$1.dy,
          (pair.$1.dx + pair.$2.dx) / 2,
          pair.$2.dy,
          pair.$2.dx,
          pair.$2.dy,
        );
      for (final metric in path.computeMetrics()) {
        for (var distance = 7.0;
            distance < metric.length - 5;
            distance += pair.$3 ? 17 : 21) {
          final tangent = metric.getTangentForOffset(distance);
          if (tangent == null) continue;
          canvas.save();
          canvas.translate(tangent.position.dx, tangent.position.dy);
          canvas.rotate(tangent.angle);
          final paint = Paint()
            ..color =
                pair.$3 ? color.withAlpha(190) : AppTheme.onNight.withAlpha(48);
          canvas.drawOval(
            Rect.fromCenter(
              center: const Offset(-2, -2),
              width: pair.$3 ? 4 : 3,
              height: pair.$3 ? 7 : 5,
            ),
            paint,
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: const Offset(3, 2),
              width: pair.$3 ? 4 : 3,
              height: pair.$3 ? 7 : 5,
            ),
            paint,
          );
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrialPathPainter oldDelegate) =>
      oldDelegate.selectedPath != selectedPath || oldDelegate.color != color;
}

class _TrialPathDecision extends StatelessWidget {
  const _TrialPathDecision({super.key, required this.onPath});

  final Future<void> Function(String path) onPath;

  @override
  Widget build(BuildContext context) => MongrooPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('첫 갈림길', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 5),
            const Text('두 장소를 살펴보고 캐릭터에게 맞는 통로를 고르세요.'),
            const SizedBox(height: 12),
            _TrialPathSceneCard(
              sceneKey: 'flooded_cave',
              title: '침수 표찰 동굴',
              description: '수정빛 물길의 흔적을 관찰해요.',
              statLabel: '관찰 판정',
              onTap: () => onPath('labels'),
            ),
            const SizedBox(height: 8),
            _TrialPathSceneCard(
              sceneKey: 'root_tunnel',
              title: '기억 뿌리 땅굴',
              description: '엉킨 뿌리와 통로를 돌봄으로 풀어요.',
              statLabel: '돌봄 판정',
              onTap: () => onPath('roots'),
            ),
          ],
        ),
      );
}

class _TrialPathSceneCard extends StatelessWidget {
  const _TrialPathSceneCard({
    required this.sceneKey,
    required this.title,
    required this.description,
    required this.statLabel,
    required this.onTap,
  });

  final String sceneKey;
  final String title;
  final String description;
  final String statLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scene = expeditionSceneTheme(sceneKey);
    return Semantics(
      button: true,
      label: '$title. $description. $statLabel.',
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 2.35,
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
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            MongrooPalette.of(context).night.withAlpha(210),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: MediaQuery.withNoTextScaling(
                          child: Row(
                            children: [
                              Icon(scene.icon, color: scene.accent, size: 19),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    color: AppTheme.onNight,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(description),
                          const SizedBox(height: 4),
                          Text(
                            statLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: scene.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded),
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

class _TrialEventDecision extends StatelessWidget {
  const _TrialEventDecision({
    super.key,
    required this.path,
    required this.onResolve,
  });

  final String path;
  final Future<void> Function(String choice) onResolve;

  @override
  Widget build(BuildContext context) {
    final labels = path == 'labels';
    final scheme = Theme.of(context).colorScheme;
    return MongrooPanel(
      borderColor: scheme.secondary.withAlpha(100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(labels ? Icons.visibility_outlined : Icons.eco_outlined,
                  color: scheme.secondary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  labels ? '번진 이름표' : '엉킨 기억의 뿌리',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            labels
                ? '젖은 표찰의 흔적이 흐려졌어요. 아기 몽그루가 천천히 빛의 결을 따라가려 해요.'
                : '오래된 서랍을 뿌리가 감싸고 있어요. 아기 몽그루가 상처 없이 풀 길을 살펴봐요.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MongrooTag(
                label: labels ? '관찰 7 · 기준 6' : '돌봄 7 · 기준 6',
                icon: Icons.auto_graph_outlined,
                backgroundColor: scheme.primaryContainer,
              ),
              const MongrooTag(
                label: '예상: 안정적',
                icon: Icons.check_circle_outline,
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('trial-resolve-event'),
            onPressed: () => onResolve(labels ? 'trace' : 'untangle'),
            icon: const Icon(Icons.bolt_outlined),
            label: Text(labels ? '새싹 감각으로 결을 따라간다' : '새싹 손길로 뿌리를 풀어 준다'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => onResolve('safe'),
            child: const Text('안전한 표식만 남기고 돌아선다'),
          ),
        ],
      ),
    );
  }
}

class _TrialComplete extends StatelessWidget {
  const _TrialComplete({
    super.key,
    required this.progress,
    required this.signedIn,
    required this.onPrimary,
    required this.onReset,
  });

  final TrialProgress progress;
  final bool signedIn;
  final VoidCallback onPrimary;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ExpeditionSceneBackdrop(
            scene: expeditionSceneTheme('treasure_vault'),
            semanticLabel: '첫 탐험을 마치고 도착한 압화 보물고와 빛나는 보물상자',
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: MediaQuery.withNoTextScaling(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(
                      color: MongrooPalette.of(context).night.withAlpha(210),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFFFD166).withAlpha(150),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.key_rounded,
                            color: Color(0xFFFFD166), size: 19),
                        SizedBox(width: 7),
                        Text(
                          '획득 · 이끼 열쇠 조각',
                          style: TextStyle(
                            color: AppTheme.onNight,
                            fontWeight: FontWeight.w800,
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
        const SizedBox(height: 20),
        Text('첫 마음 탐험을 마쳤어요', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          progress.selectedChoice == 'safe'
              ? '무리하지 않고 돌아오는 판단도 탐험 기록에 남았어요.'
              : '직접 고른 길과 캐릭터의 행동이 하나의 탐험 기록이 됐어요.',
        ),
        const SizedBox(height: 16),
        MongrooPanel(
          color: scheme.primaryContainer,
          borderColor: scheme.primary.withAlpha(90),
          child: const Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 30),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('체험 발견물 · 이끼 열쇠 조각'),
                    SizedBox(height: 3),
                    Text('탐험 성장 +4 · 씨앗 +2'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          signedIn
              ? '이 가이드는 언제든 다시 열 수 있어요. 실제 기록과 보상은 계정의 홈에서 이어집니다.'
              : '이 체험 기록은 이 기기에만 남고 정식 계정으로 자동 전송되지 않아요. 가입 후에는 실제 마음 기록과 성장을 새로 시작해요.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('trial-primary-complete'),
          onPressed: onPrimary,
          icon: Icon(
              signedIn ? Icons.home_outlined : Icons.person_add_alt_1_outlined),
          label: Text(signedIn ? '홈에서 실제로 시작하기' : '계정 만들고 실제로 시작하기'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('체험 다시 하기'),
        ),
      ],
    );
  }
}
