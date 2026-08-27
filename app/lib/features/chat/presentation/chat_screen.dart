import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/text/korean_particles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../garden/presentation/garden_controller.dart';
import '../../home/domain/plant.dart';
import '../../home/presentation/home_controller.dart';
import '../../home/presentation/plant_view.dart';
import '../domain/chat_models.dart';
import 'chat_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    final canSend = _inputController.text.trim().isNotEmpty;
    if (canSend != _canSend && mounted) setState(() => _canSend = canSend);
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    _inputController.clear();
    ref.read(chatControllerProvider.notifier).send(text);
  }

  void _useStarter(String starter) {
    _inputController
      ..text = starter
      ..selection = TextSelection.collapsed(offset: starter.length);
    _inputFocusNode.requestFocus();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final activePlant = ref.watch(homeControllerProvider).valueOrNull;
    final outfitKey = ref.watch(equippedWardrobeLayerKeyProvider);
    final character = state.character;
    final displayName = character?.name ?? activePlant?.name;
    final availableWidth = MediaQuery.sizeOf(context).width;
    final chatInset = availableWidth > 820 ? (availableWidth - 760) / 2 : 16.0;
    final canCompose = !state.thinking &&
        state.failedContent == null &&
        state.remainingTurns > 0;

    ref.listen(chatControllerProvider.select((s) => s.pendingSafety),
        (previous, next) {
      if (next != null) {
        ref.read(chatControllerProvider.notifier).clearSafety();
        context.push('/safety', extra: next);
      }
    });
    ref.listen(chatControllerProvider.select((s) => s.sessionReward),
        (previous, next) {
      if (next != null && next.totalExp > 0) {
        ref.read(chatControllerProvider.notifier).clearSessionReward();
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('대화 시작! 경험치 +${next.totalExp}')),
        );
      }
    });
    ref.listen(chatControllerProvider.select((s) => s.bubbles.length),
        (previous, next) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: Text(
          displayName == null ? '식물과 대화' : '${koreanWith(displayName)} 대화',
        ),
        actions: [
          if (state.hasSession)
            TextButton(
              onPressed: () =>
                  ref.read(chatControllerProvider.notifier).endSession(),
              child: const Text('대화 마치기'),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: scheme.surface,
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '식물 답변은 AI가 만들며 의료 상담이 아닙니다.',
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          if (state.hasSession)
            Padding(
              padding: EdgeInsets.fromLTRB(chatInset, 10, chatInset, 0),
              child: _SessionCharacterBar(
                character: character,
                userTurns: state.userTurns,
                maxUserTurns: state.maxUserTurns,
                remainingTurns: state.remainingTurns,
                progress: state.turnProgress,
              ),
            ),
          Expanded(
            child: !state.hasSession
                ? _SessionIntro(
                    plant: activePlant,
                    outfitKey: outfitKey,
                    maxUserTurns: state.maxUserTurns,
                    starting: state.starting,
                    errorMessage: state.errorMessage,
                    onStart: () => ref
                        .read(chatControllerProvider.notifier)
                        .startSession(plant: activePlant),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      chatInset,
                      16,
                      chatInset,
                      16,
                    ),
                    itemCount: state.bubbles.length + (state.thinking ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == state.bubbles.length) {
                        return _ThinkingBubble(character: character);
                      }
                      return _MessageBubble(
                        bubble: state.bubbles[index],
                        character: character,
                      );
                    },
                  ),
          ),
          if (state.hasSession && state.errorMessage != null)
            Semantics(
              liveRegion: true,
              label: '대화 오류: ${state.errorMessage}',
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                // 면을 흐리게 깔았으면 글자도 그 면에 맞춰야 한다.
                // `onErrorContainer`(흰색)는 진한 빨강 면을 위한 짝이라
                // 흐린 분홍 위에서는 2.1:1이 된다.
                color: scheme.errorContainer.withAlpha(90),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 18, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurface),
                      ),
                    ),
                    if (state.failedContent != null)
                      TextButton(
                        onPressed: () => ref
                            .read(chatControllerProvider.notifier)
                            .retryFailed(),
                        child: const Text('다시 시도'),
                      ),
                  ],
                ),
              ),
            ),
          if (state.hasSession)
            state.closed
                ? _ClosedSessionPanel(
                    message: state.closureMessage,
                    onRestart: () => ref
                        .read(chatControllerProvider.notifier)
                        .startSession(plant: activePlant),
                  )
                : SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        chatInset,
                        8,
                        chatInset,
                        12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (state.suggestedStarters.isNotEmpty)
                            _ConversationStarters(
                              starters: state.suggestedStarters,
                              onSelected: _useStarter,
                            ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _inputController,
                                  focusNode: _inputFocusNode,
                                  maxLength: 2000,
                                  maxLines: 4,
                                  minLines: 1,
                                  textInputAction: TextInputAction.send,
                                  enabled: canCompose,
                                  decoration: InputDecoration(
                                    hintText: '지금 떠오르는 말을 적어 주세요',
                                    counterText: '',
                                    helperText: state.remainingTurns > 0
                                        ? '${state.remainingTurns}번 남았어요'
                                        : '마지막 답변은 위의 다시 시도에서 이어갈 수 있어요',
                                    // 입력 칸이 보내기 버튼과 폭을 나눠 써서
                                    // 302px밖에 안 된다. 한 줄로 두면 대화를
                                    // 다 쓴 뒤의 안내가 잘려 어디서 이어가는지
                                    // 못 읽는다.
                                    helperMaxLines: 2,
                                    helperStyle: const TextStyle(
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  onSubmitted:
                                      canCompose ? (_) => _send() : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Semantics(
                                button: true,
                                enabled: canCompose && _canSend,
                                label: '메시지 보내기, ${state.remainingTurns}번 남음',
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(52, 52),
                                    padding: EdgeInsets.zero,
                                  ),
                                  onPressed:
                                      !canCompose || !_canSend ? null : _send,
                                  child: const Icon(Icons.arrow_upward_rounded),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}

class _SessionCharacterBar extends StatelessWidget {
  const _SessionCharacterBar({
    required this.character,
    required this.userTurns,
    required this.maxUserTurns,
    required this.remainingTurns,
    required this.progress,
  });

  final ChatCharacterSnapshot? character;
  final int userTurns;
  final int maxUserTurns;
  final int remainingTurns;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    final name = character?.name ?? '마음씨앗';
    final stageName = character?.stageName ?? '씨앗';
    final dominant = character?.dominantLabel ?? '마음빛 관찰 중';
    final secondary = character?.secondaryLabel;
    final temperament =
        character?.temperamentSummary ?? '일기를 들으며 말투와 성격을 알아 가는 중';
    final personalityName = character?.personalityName.trim() ?? '';
    final characterSummary =
        (character?.stage ?? 0) >= 3 && personalityName.isNotEmpty
            ? '$personalityName · $temperament'
            : temperament;
    final semantic = character?.semanticDescription ??
        '$name, $stageName 단계, $dominant, $temperament';
    return Semantics(
      container: true,
      label: '$semantic. 10번 중 $userTurns번 대화함, $remainingTurns번 남음.',
      child: MongrooPanel(
        padding: const EdgeInsets.all(12),
        radius: 18,
        shadowOffset: const Offset(0, 2),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PlantAvatar(character: character, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$userTurns / $maxUserTurns',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          MongrooTag(
                            label: '$stageName 단계',
                            backgroundColor: palette.paperDeep,
                          ),
                          MongrooTag(
                            label: '주결 · $dominant',
                            backgroundColor: scheme.primaryContainer,
                          ),
                          if (secondary != null)
                            MongrooTag(
                              label: '보조결 · $secondary',
                              backgroundColor: palette.sky,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: palette.paperDeep,
              color: remainingTurns <= 2 ? palette.coral : palette.leaf,
              semanticsLabel: '대화 진행률',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                characterSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationStarters extends StatelessWidget {
  const _ConversationStarters({
    required this.starters,
    required this.onSelected,
  });

  final List<String> starters;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '이렇게 시작해도 좋아요',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final starter in starters)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Semantics(
                    button: true,
                    label: '시작 문장 입력: $starter',
                    onTap: () => onSelected(starter),
                    child: ExcludeSemantics(
                      child: ActionChip(
                        avatar: const Icon(Icons.edit_outlined, size: 16),
                        label: Text(
                          starter,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () => onSelected(starter),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClosedSessionPanel extends StatelessWidget {
  const _ClosedSessionPanel({
    required this.message,
    required this.onRestart,
  });

  final String? message;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Semantics(
              container: true,
              liveRegion: true,
              child: MongrooPanel(
                padding: const EdgeInsets.all(14),
                color: palette.paperDeep,
                shadowOffset: Offset.zero,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final status = Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: palette.leaf.withAlpha(32),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.check_rounded, color: palette.leaf),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '오늘 대화를 잘 마쳤어요',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                message ?? '새 대화를 열면 처음부터 다시 이야기할 수 있어요.',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    final restart = FilledButton.tonal(
                      onPressed: onRestart,
                      child: const Text('새 대화'),
                    );
                    if (constraints.maxWidth < 420) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          status,
                          const SizedBox(height: 12),
                          restart,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: status),
                        const SizedBox(width: 10),
                        restart,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionIntro extends StatelessWidget {
  const _SessionIntro({
    required this.plant,
    required this.outfitKey,
    required this.maxUserTurns,
    required this.starting,
    required this.errorMessage,
    required this.onStart,
  });

  final ActivePlant? plant;
  final String? outfitKey;
  final int maxUserTurns;
  final bool starting;
  final String? errorMessage;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: MongrooPanel(
                color: palette.night,
                borderColor: palette.night,
                shadowOffset: const Offset(5, 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PlantView(
                      stage: plant?.stage ?? 1,
                      expression: PlantExpression.happy,
                      form: plant?.visualForm,
                      secondaryForm: plant?.secondaryForm,
                      speciesCode: plant?.species.code ?? 'basic_sprout',
                      speciesName: plant?.species.name,
                      growthVisual: plant?.growthVisual,
                      outfitKey: outfitKey,
                      size: 140,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      plant == null
                          ? '식물 대화'
                          : '${koreanWith(plant!.name)} 잠깐 이야기',
                      style: TextStyle(
                        color: AppTheme.onNight,
                        fontFamily: AppTheme.pixelFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      plant == null
                          ? '최대 $maxUserTurns번 주고받아요. 언제든 끝낼 수 있어요.'
                          : '성격 단서 · ${plant!.personalityName} · '
                              '최대 $maxUserTurns번 주고받아요.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.onNightMuted,
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      // 이 패널은 테마와 무관하게 늘 밤색이라 주변 글자도
                      // onNight 계열을 쓴다. 오류 문구만 밝은 테마에서
                      // 진한 빨강으로 갈라져 2.3:1까지 떨어져 있었다.
                      Text(errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.onNightError,
                          )),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.butter,
                          foregroundColor: palette.night,
                        ),
                        onPressed: starting ? null : onStart,
                        child: starting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('대화 시작'),
                      ),
                    ),
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.bubble,
    required this.character,
  });

  final ChatBubble bubble;
  final ChatCharacterSnapshot? character;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    final isUser = bubble.role == 'user';
    final failed = bubble.status == BubbleStatus.failed;
    final background = isUser ? scheme.primary : palette.paper;
    final foreground = isUser ? scheme.onPrimary : palette.ink;
    final speaker = isUser ? '내 메시지' : '${character?.name ?? '식물'}의 답변';
    final failure = failed ? ', 전송 실패' : '';

    return Semantics(
      container: true,
      label: '$speaker: ${bubble.content}$failure',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                _PlantAvatar(character: character, decorative: true),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: failed
                          ? scheme.error
                          : isUser
                              ? scheme.primary
                              : scheme.outlineVariant,
                    ),
                    boxShadow: isUser
                        ? null
                        : [
                            BoxShadow(
                              color: palette.night.withAlpha(22),
                              offset: const Offset(0, 2),
                              blurRadius: 8,
                              spreadRadius: -4,
                            ),
                          ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bubble.content, style: TextStyle(color: foreground)),
                      if (failed)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '전송 실패',
                            style: TextStyle(fontSize: 11, color: scheme.error),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlantAvatar extends StatelessWidget {
  const _PlantAvatar({
    required this.character,
    this.size = 44,
    this.decorative = false,
  });

  final ChatCharacterSnapshot? character;
  final double size;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final preview = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.paperDeep,
        borderRadius: BorderRadius.circular(size >= 52 ? 14 : 11),
        border: Border.all(color: palette.wood.withAlpha(42)),
      ),
      child: PlantStagePreview(
        stage: character?.stage ?? 1,
        form: character?.visualForm,
        secondaryForm: character?.secondaryForm,
        speciesCode: character?.speciesCode ?? 'basic_sprout',
        speciesName: character?.speciesName,
        growthVisual: character?.growthVisual,
        size: size - 6,
      ),
    );
    if (decorative) return ExcludeSemantics(child: preview);
    return Semantics(
      image: true,
      label: character?.semanticDescription ?? '대화 중인 작은 마음씨앗',
      child: ExcludeSemantics(child: preview),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble({required this.character});

  final ChatCharacterSnapshot? character;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    final name = character?.name ?? '식물';
    return Semantics(
      liveRegion: true,
      label: '${koreanSubject(name)} 답변을 생각하고 있어요',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              _PlantAvatar(character: character, decorative: true),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.paper,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${koreanSubject(name)} 생각 중이에요',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant),
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
