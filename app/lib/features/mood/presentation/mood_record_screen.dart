import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../garden/presentation/garden_controller.dart';
import '../../home/data/plant_repository.dart';
import '../../home/domain/plant.dart';
import '../../home/presentation/home_controller.dart';
import '../../home/presentation/plant_view.dart';
import '../../quest/presentation/quest_controller.dart';
import '../../report/presentation/report_controller.dart';
import '../data/mood_repository.dart';
import '../domain/mood_entry.dart';
import 'mood_providers.dart';

/// 일기 본문을 남기는 화면. 감정은 사용자에게 선택을 요구하지 않고
/// 저장된 글을 분석해 식물 성장에 반영한다.
class MoodEditLoader extends ConsumerWidget {
  const MoodEditLoader({super.key, required this.moodId});

  final int moodId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(moodDetailProvider(moodId));
    return entry.when(
      data: (value) => MoodRecordScreen(
        key: ValueKey('mood-edit-$moodId-${value.editVersion}'),
        existing: value,
      ),
      loading: () => Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/home'),
          ),
          title: const Text('기록 불러오기'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/home'),
          ),
          title: const Text('기록 불러오기'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 42),
                const SizedBox(height: 12),
                Text(
                  ApiException.from(error).message,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(moodDetailProvider(moodId)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('다시 불러오기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MoodRecordScreen extends ConsumerStatefulWidget {
  const MoodRecordScreen({super.key, this.existing});

  final MoodEntry? existing;

  @override
  ConsumerState<MoodRecordScreen> createState() => _MoodRecordScreenState();
}

class _MoodRecordScreenState extends ConsumerState<MoodRecordScreen> {
  static const _uuid = Uuid();

  final _contentController = TextEditingController();
  bool _saving = false;
  bool _dirty = false;
  MoodEntry? _baseEntry;

  /// 같은 작성 건의 재시도에는 같은 키를 쓴다.
  String? _idempotencyKey;
  String? _idempotencyContent;

  bool get _isEdit => _baseEntry != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _baseEntry = existing;
    if (existing != null) {
      _contentController.text = existing.content ?? '';
    }
    _contentController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _contentController.removeListener(_markDirty);
    _contentController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (mounted) setState(() => _dirty = true);
  }

  Future<void> _requestPop() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('작성 중인 기록을 닫을까요?'),
        content: const Text('아직 저장하지 않은 내용은 사라져요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('계속 작성'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _dirty = false);
      _closeOrHome();
    }
  }

  void _closeOrHome() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _attemptLeave() async {
    if (_saving) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일기를 저장하고 있어요.')),
      );
      return;
    }
    if (_dirty) {
      await _requestPop();
      return;
    }
    _closeOrHome();
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    if (content.isEmpty || _saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);

    final repository = ref.read(moodRepositoryProvider);
    try {
      final MoodSaveResult result;
      if (_isEdit) {
        final baseEntry = _baseEntry!;
        result = await repository.patch(baseEntry.id, {
          if (baseEntry.editVersion != null)
            'expected_version': baseEntry.editVersion,
          'content': content,
        });
      } else {
        if (_idempotencyKey == null || _idempotencyContent != content) {
          _idempotencyKey = _uuid.v4();
          _idempotencyContent = content;
        }
        result = await repository.createDiary(
          content: content,
          idempotencyKey: _idempotencyKey!,
        );
      }
      if (!mounted) return;
      _invalidateMoodData(result);
      await _handleSaved(result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e.code == 'MOOD_VERSION_CONFLICT' && _isEdit) {
        await _showEditConflict();
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _showEditConflict() async {
    final keepDraft = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('다른 곳에서 기록이 바뀌었어요'),
        content: const Text(
          '작성 중인 내용은 그대로 두었어요. 내 초안을 유지하면 최신 변경 버전에 이어서 '
          '저장하고, 최신 기록을 불러오면 현재 초안이 바뀝니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('내 초안 유지'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('최신 기록 불러오기'),
          ),
        ],
      ),
    );
    if (!mounted || keepDraft == null) return;
    if (keepDraft) {
      await _refreshBaseVersionKeepingDraft();
    } else {
      await _reloadLatestEntry();
    }
  }

  Future<void> _refreshBaseVersionKeepingDraft() async {
    final entry = _baseEntry;
    if (entry == null) return;
    setState(() => _saving = true);
    try {
      final latest = await ref.read(moodRepositoryProvider).getById(entry.id);
      if (!mounted) return;
      setState(() {
        // 화면의 초안은 건드리지 않고 다음 PATCH 기준 버전만 최신으로 올린다.
        _baseEntry = latest;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('초안을 유지했어요. 검토한 뒤 다시 저장해 주세요.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _reloadLatestEntry() async {
    final entry = _baseEntry;
    if (entry == null) return;
    setState(() => _saving = true);
    try {
      final latest = await ref.read(moodRepositoryProvider).getById(entry.id);
      if (!mounted) return;
      _contentController.removeListener(_markDirty);
      setState(() {
        _baseEntry = latest;
        _contentController.text = latest.content ?? '';
        _dirty = false;
        _saving = false;
      });
      _contentController.addListener(_markDirty);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최신 기록을 불러왔어요. 다시 편집해 주세요.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _invalidateMoodData(MoodSaveResult result) {
    final mood = result.mood;
    ref.invalidate(homeControllerProvider);
    ref.invalidate(moodCalendarProvider);
    ref.invalidate(dayEntriesProvider);
    ref.invalidate(moodDetailProvider(mood.id));
    // 회고 탭은 indexed stack에 남아 있으므로 기록 변경 때 명시적으로 갱신한다.
    ref.invalidate(reportControllerProvider);
    // 안전 분기에서는 서버가 오늘 퀘스트를 억제한다. 일반 기록에서도 새 진행
    // 상태를 받을 수 있도록 캐시를 버려 다음 화면이 서버 상태와 일치하게 한다.
    ref.invalidate(questControllerProvider);
    final reward = result.reward;
    if (reward != null) {
      // 7일 연속 기록 등 씨앗 보상은 전역 잔액과 이미 열린 상점/도감에
      // 동시에 반영해야 실제 구매 가능 상태가 즉시 바뀐다.
      ref
          .read(authControllerProvider.notifier)
          .updateSeedBalance(reward.seedBalance);
      ref.invalidate(shopControllerProvider);
      ref.invalidate(collectionControllerProvider);
    }
  }

  Future<void> _handleSaved(MoodSaveResult result) async {
    setState(() {
      _saving = false;
      _dirty = false;
    });
    final outfitKey = ref.read(equippedWardrobeLayerKeyProvider);
    final safety = result.safetyAction;
    if (safety != null) {
      // 안전 경로: 축하 연출 없이 지원 화면으로 바로 이동한다.
      context.pushReplacement('/safety', extra: safety);
      return;
    }

    // 감정 점수와 무관하게 새 일기가 반영됐음만 잠시 알린다.
    ref.read(plantReactionProvider.notifier).acknowledgeAnalysis();

    final reward = result.reward;
    final plantNote = result.mood.analysisInProgress
        ? ' · 식물이 일기의 마음을 읽는 중'
        : ' · 식물 성장에 반영됐어요';
    final rewardParts = <String>[
      if (reward != null && reward.totalExp > 0) '경험치 +${reward.totalExp}',
      if (reward != null && reward.totalSeeds > 0) '씨앗 +${reward.totalSeeds}',
    ];
    final rewardNote = rewardParts.isEmpty
        ? (_isEdit ? '기록을 수정했어요.' : '기록을 저장했어요.')
        : '${rewardParts.join(' · ')} 획득!';
    final stageAfter = reward?.plant?.stage;
    final stageChanged = reward?.stageChanged ?? false;
    // 단계 상승은 드물고, 품종 외형은 보상 축약 응답에 없으므로 성공 시트가
    // 열려 있는 동안 최신 활성 식물을 한 번 받아 올바른 씨앗/용기를 보여 준다.
    final stagePlantFuture = stageChanged ? _loadStagePlant() : null;
    final destination = await showModalBottomSheet<_RecordSaveDestination>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => _RecordSavedSheet(
        message: '$rewardNote$plantNote',
        stageAfter: stageChanged ? stageAfter : null,
        isEdit: _isEdit,
      ),
    );
    if (!mounted) return;
    final stagePlant = await stagePlantFuture;
    if (!mounted) return;

    if (destination == _RecordSaveDestination.plant) {
      context.go('/home');
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
    if (stageChanged && stageAfter != null) {
      // 이동 이후 프레임에서 전역 navigator로 성장 연출을 띄운다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final rootContext = rootNavigatorKey.currentContext;
        if (rootContext == null) return;
        showDialog<void>(
          context: rootContext,
          builder: (context) => _StageUpDialog(
            stage: stageAfter,
            form: reward?.plant?.growthForm,
            speciesCode: stagePlant?.species.code ?? 'basic_sprout',
            speciesName: stagePlant?.species.name,
            growthVisual: stagePlant?.growthVisual,
            outfitKey: outfitKey,
          ),
        );
      });
    }
  }

  Future<ActivePlant?> _loadStagePlant() async {
    try {
      return await ref.read(plantRepositoryProvider).getActivePlant();
    } on Object {
      return ref.read(homeControllerProvider).valueOrNull;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 저장 직후 성장 다이얼로그가 열릴 때 처음 팜 상태를 읽으면 로드 전 null을
    // 캡처한다. 작성 화면이 열려 있는 동안 미리 구독해 장착 의상을 준비한다.
    ref.watch(equippedWardrobeLayerKeyProvider);
    final palette = MongrooPalette.of(context);
    final hasContent = _contentController.text.trim().isNotEmpty;
    return PopScope<void>(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_saving) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('일기를 저장하고 있어요.')),
          );
          return;
        }
        _requestPop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _attemptLeave),
          title: Text(_isEdit ? '기록 수정' : '오늘 기록'),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              padding: EdgeInsets.fromLTRB(
                constraints.maxWidth > 760
                    ? (constraints.maxWidth - 720) / 2
                    : constraints.maxWidth < 360
                        ? 12
                        : 20,
                20,
                constraints.maxWidth > 760
                    ? (constraints.maxWidth - 720) / 2
                    : constraints.maxWidth < 360
                        ? 12
                        : 20,
                32,
              ),
              children: [
                _ObservationIntro(isEdit: _isEdit),
                const SizedBox(height: 18),
                _ObservationSection(
                  indexLabel: '01',
                  title: '오늘의 일기',
                  helper: '감정을 고르지 않아도 돼요. 식물이 이 글을 읽고 자신만의 결로 자라요.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('mood-diary-field'),
                        controller: _contentController,
                        readOnly: _saving,
                        minLines: 5,
                        maxLines: 16,
                        maxLength: 5000,
                        decoration: InputDecoration(
                          labelText: '일기 본문',
                          alignLabelWithHint: true,
                          hintText: '오늘 가장 기억나는 장면은…\n그때 몸이나 마음에는…',
                          fillColor: palette.paperDeep.withAlpha(82),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _NotebookHint(
                        icon: Icons.eco_outlined,
                        text: '저장한 뒤 일기 본문에서 읽힌 마음이 현재 식물의 외형과 성격에 차곡차곡 반영돼요.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  button: true,
                  label: _isEdit ? '일기 수정 저장' : '일기 저장',
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: !hasContent || _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isEdit ? '수정하기' : '저장하기'),
                  ),
                ),
                if (!hasContent)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '일기 본문을 적으면 저장할 수 있어요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: palette.inkMuted),
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

enum _RecordSaveDestination { back, plant }

class _RecordSavedSheet extends StatelessWidget {
  const _RecordSavedSheet({
    required this.message,
    required this.isEdit,
    this.stageAfter,
  });

  final String message;
  final bool isEdit;
  final int? stageAfter;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: MongrooTag(
              label: isEdit ? '기록 갱신' : '오늘의 첫 장면',
              icon: Icons.auto_awesome_rounded,
              backgroundColor: palette.butter,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '이야기가 화분에 닿았어요',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
          ),
          if (stageAfter case final stage?) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_florist_rounded,
                      color: scheme.onPrimaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${plantStageName(stage)} 단계가 열렸어요. 새로운 모습과 이야기를 확인해 보세요.',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(
              _RecordSaveDestination.plant,
            ),
            icon: const Icon(Icons.spa_rounded),
            label: const Text('식물 변화 보기'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              _RecordSaveDestination.back,
            ),
            child: Text(isEdit ? '기록으로 돌아가기' : '목록으로 돌아가기'),
          ),
        ],
      ),
    );
  }
}

class _ObservationIntro extends StatelessWidget {
  const _ObservationIntro({required this.isEdit});

  final bool isEdit;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      color: palette.blush,
      borderColor: palette.ink.withAlpha(32),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.seed,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.eco_outlined, color: palette.ink, size: 24),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEdit ? '남긴 일기를 고쳐요' : '오늘을 글로 남겨요',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.ink,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '가장 기억나는 장면 하나부터 적어도 충분해요.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.inkMuted,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ObservationSection extends StatelessWidget {
  const _ObservationSection({
    required this.indexLabel,
    required this.title,
    required this.helper,
    required this.child,
  });

  final String indexLabel;
  final String title;
  final String helper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MongrooTag(label: indexLabel),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: palette.ink,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            helper,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.inkMuted,
                ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _NotebookHint extends StatelessWidget {
  const _NotebookHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: palette.leaf),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.inkMuted,
                  height: 1.45,
                ),
          ),
        ),
      ],
    );
  }
}

class _StageUpDialog extends StatelessWidget {
  const _StageUpDialog({
    required this.stage,
    required this.speciesCode,
    required this.outfitKey,
    this.form,
    this.speciesName,
    this.growthVisual,
  });

  final int stage;
  final PlantGrowthForm? form;
  final String speciesCode;
  final String? outfitKey;
  final String? speciesName;
  final PlantGrowthVisual? growthVisual;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final previousStage = (stage - 1).clamp(1, 5);
    final title = switch (stage) {
      2 => '첫 잎이 고개를 내밀었어요',
      3 => '마음빛 갈래가 모습을 드러냈어요',
      4 => '꽃봉오리가 열리기 시작했어요',
      5 => '한 그루의 이야기가 만개했어요',
      _ => '식물의 다음 장면이 열렸어요',
    };
    final note = stage >= 3 && form != null
        ? '쌓인 ${form!.emotionLabel} 단서가 ${form!.label}의 외형과 '
            '성격으로 이어지고 있어요.'
        : '아직 어느 갈래도 확정되지 않았어요. 앞으로 쌓일 '
            '마음이 잎의 빛과 말투를 천천히 바꿔요.';

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: MongrooPanel(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: MongrooTag(
                    label:
                        '${plantStageName(previousStage)} → ${plantStageName(stage)}',
                    icon: Icons.auto_awesome_rounded,
                    backgroundColor: palette.butter,
                  ),
                ),
                const SizedBox(height: 14),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  '일기의 한 장면이 식물의 다음 모습이 됐어요.',
                  style: TextStyle(color: palette.inkMuted, height: 1.45),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StageMoment(
                        label: '이전',
                        stage: previousStage,
                        form: form,
                        speciesCode: speciesCode,
                        speciesName: speciesName,
                        growthVisual: growthVisual,
                        outfitKey: outfitKey,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: palette.leaf,
                      ),
                    ),
                    Expanded(
                      child: _StageMoment(
                        label: '지금',
                        stage: stage,
                        form: form,
                        speciesCode: speciesCode,
                        speciesName: speciesName,
                        growthVisual: growthVisual,
                        outfitKey: outfitKey,
                        highlighted: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.leaf.withAlpha(34),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.eco_rounded, color: palette.leaf, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            note,
                            style: TextStyle(
                              color: palette.ink,
                              height: 1.45,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.spa_rounded),
                  label: const Text('새 모습으로 계속하기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StageMoment extends StatelessWidget {
  const _StageMoment({
    required this.label,
    required this.stage,
    required this.speciesCode,
    required this.outfitKey,
    this.form,
    this.speciesName,
    this.growthVisual,
    this.highlighted = false,
  });

  final String label;
  final int stage;
  final PlantGrowthForm? form;
  final String speciesCode;
  final String? outfitKey;
  final String? speciesName;
  final PlantGrowthVisual? growthVisual;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? palette.sky.withAlpha(92) : palette.paperDeep,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? palette.leaf.withAlpha(110) : Colors.transparent,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: highlighted ? palette.leaf : palette.inkMuted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            PlantView(
              stage: stage,
              expression: PlantExpression.acknowledged,
              form: form,
              speciesCode: speciesCode,
              speciesName: speciesName,
              growthVisual: growthVisual,
              outfitKey: outfitKey,
              size: 94,
            ),
            Text(
              plantStageName(stage),
              style: TextStyle(
                color: palette.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
