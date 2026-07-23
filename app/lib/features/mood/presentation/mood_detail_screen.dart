import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_formats.dart';
import '../../../core/error/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../report/presentation/report_controller.dart';
import '../data/mood_repository.dart';
import '../domain/mood_entry.dart';
import 'mood_providers.dart';
import 'mood_style.dart';

/// 감정 분류 6대 라벨. AI 라벨 수정 다이얼로그 선택지로 쓴다.
const List<String> aiEmotionChoices = ['기쁨', '슬픔', '분노', '불안', '상처', '당황'];

class MoodDetailScreen extends ConsumerStatefulWidget {
  const MoodDetailScreen({super.key, required this.moodId});

  final int moodId;

  @override
  ConsumerState<MoodDetailScreen> createState() => _MoodDetailScreenState();
}

class _MoodDetailScreenState extends ConsumerState<MoodDetailScreen> {
  bool _mutating = false;

  Future<void> _patchLabel(
    MoodEntry entry,
    Map<String, dynamic> changes,
  ) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      await ref.read(moodRepositoryProvider).patch(widget.moodId, {
        if (entry.editVersion != null) 'expected_version': entry.editVersion,
        ...changes,
      });
      ref.invalidate(moodDetailProvider(widget.moodId));
      ref.invalidate(dayEntriesProvider);
      ref.invalidate(reportControllerProvider);
    } on ApiException catch (e) {
      if (mounted) {
        if (e.code == 'MOOD_VERSION_CONFLICT') {
          ref.invalidate(moodDetailProvider(widget.moodId));
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.code == 'MOOD_VERSION_CONFLICT'
              ? '다른 곳에서 기록이 바뀌어 최신 내용을 불러왔어요. 다시 시도해 주세요.'
              : e.message),
        ));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _editAiLabel(MoodEntry entry) async {
    final selected = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('읽힌 감정 수정'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Text(
              '내가 느낀 감정과 다르면 직접 바꿔 주세요. 원래 분석 결과는 보관돼요.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          for (final emotion in aiEmotionChoices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(emotion),
              child: Text(
                emotion,
                style: TextStyle(
                  fontWeight: entry.effectiveAiLabel == emotion
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
          if (entry.aiEmotionOverride != null)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('__reset__'),
              child: const Text('수정 취소하고 원래 라벨로'),
            ),
        ],
      ),
    );
    if (selected == null) return;
    await _patchLabel(entry, {
      'ai_emotion_override': selected == '__reset__' ? null : selected,
    });
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기록 삭제'),
        content: const Text('이 기록을 삭제할까요? 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || _mutating) return;
    setState(() => _mutating = true);
    try {
      await ref.read(moodRepositoryProvider).delete(widget.moodId);
      ref.invalidate(moodCalendarProvider);
      ref.invalidate(dayEntriesProvider);
      ref.invalidate(reportControllerProvider);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _mutating = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(moodDetailProvider(widget.moodId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('기록 상세'),
        actions: [
          if (detailAsync.hasValue) ...[
            TextButton(
              onPressed: _mutating
                  ? null
                  : () => context.push('/moods/${widget.moodId}/edit'),
              child: const Text('수정'),
            ),
            TextButton(
              onPressed: _mutating ? null : _delete,
              child: Text(
                '삭제',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ApiException.from(error).message),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    ref.invalidate(moodDetailProvider(widget.moodId)),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (entry) => LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth > 760
                  ? (constraints.maxWidth - 720) / 2
                  : 20,
              20,
              constraints.maxWidth > 760
                  ? (constraints.maxWidth - 720) / 2
                  : 20,
              32,
            ),
            children: [
              _MoodHeader(entry: entry),
              const SizedBox(height: 16),
              _UserTagsCard(entry: entry),
              const SizedBox(height: 12),
              _ContentCard(entry: entry),
              const SizedBox(height: 12),
              _AiLabelCard(
                entry: entry,
                mutating: _mutating,
                onEdit: () => _editAiLabel(entry),
                onToggleHidden: () => _patchLabel(
                  entry,
                  {'ai_label_hidden': !entry.aiLabelHidden},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoodHeader extends StatelessWidget {
  const _MoodHeader({required this.entry});

  final MoodEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final displayLabel = entry.moodLevelExplicit
        ? moodLevelName(entry.moodLevel)
        : diaryAnalysisDisplayLabel(
            status: entry.analysisStatus,
            emotion: entry.effectiveAiLabel,
            hidden: entry.aiLabelHidden,
          );
    final showsAnalyzedEmotion = !entry.moodLevelExplicit &&
        !entry.aiLabelHidden &&
        entry.analysisStatus == 'succeeded' &&
        entry.effectiveAiLabel != null;
    final markerColor = entry.moodLevelExplicit
        ? moodLevelColor(entry.moodLevel)
        : showsAnalyzedEmotion
            ? diaryEmotionColor(entry.effectiveAiLabel)
            : palette.butter;
    final markerIcon = entry.moodLevelExplicit
        ? moodLevelIcon(entry.moodLevel)
        : showsAnalyzedEmotion
            ? diaryEmotionIcon(entry.effectiveAiLabel)
            : diaryAnalysisIcon(
                entry.analysisStatus,
                hidden: entry.aiLabelHidden,
              );
    return MongrooPanel(
      color: palette.night,
      borderColor: palette.night,
      shadowOffset: const Offset(4, 4),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: markerColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              markerIcon,
              color: palette.night,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayLabel,
                  style: TextStyle(
                    color: AppTheme.onNight,
                    fontFamily: AppTheme.pixelFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${entry.localDate} ${formatLocalTime(entry.recordedAt)}',
                  style: const TextStyle(color: AppTheme.onNightMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserTagsCard extends StatelessWidget {
  const _UserTagsCard({required this.entry});

  final MoodEntry entry;

  @override
  Widget build(BuildContext context) {
    return MongrooPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MongrooTag(label: '내 태그'),
          const SizedBox(height: 10),
          if (entry.emotionTags.isEmpty)
            Text(
              '고른 태그가 없어요.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in entry.emotionTags) Chip(label: Text(tag)),
              ],
            ),
        ],
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.entry});

  final MoodEntry entry;

  @override
  Widget build(BuildContext context) {
    final content = entry.content;
    return MongrooPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MongrooTag(label: '메모'),
          const SizedBox(height: 10),
          Text(
            (content == null || content.isEmpty) ? '남긴 메모가 없어요.' : content,
            style: (content == null || content.isEmpty)
                ? TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)
                : null,
          ),
        ],
      ),
    );
  }
}

/// 일기 본문에서 읽힌 감정과 수정·숨김 동작.
class _AiLabelCard extends StatelessWidget {
  const _AiLabelCard({
    required this.entry,
    required this.mutating,
    required this.onEdit,
    required this.onToggleHidden,
  });

  final MoodEntry entry;
  final bool mutating;
  final VoidCallback onEdit;
  final VoidCallback onToggleHidden;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      color: palette.paperDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MongrooTag(
            label: '일기에서 읽은 감정',
            icon: Icons.auto_awesome,
            backgroundColor: scheme.primaryContainer,
          ),
          const SizedBox(height: 8),
          Text(
            '글에서 읽힌 마음이에요. 다르게 느껴지면 직접 바꿀 수 있어요. '
            '수정·숨김은 표시와 리포트에만 반영되고, 식물은 원문 분석 기록으로 자라요.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _buildBody(context),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (entry.aiLabelHidden) {
      return Row(
        children: [
          Expanded(
            child: Text('읽힌 감정을 숨겨둔 상태예요. 리포트 집계에서도 빠져요.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          OutlinedButton(
            onPressed: mutating ? null : onToggleHidden,
            child: const Text('다시 표시'),
          ),
        ],
      );
    }

    switch (entry.analysisStatus) {
      case 'not_requested':
        return Text('텍스트가 없거나 분석 대상이 아니어서 라벨이 없어요.',
            style: TextStyle(color: scheme.onSurfaceVariant));
      case 'pending':
      case 'running':
      case 'waiting_dependency':
        return Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('감정 분석 중이에요. 잠시 후 다시 확인해 주세요.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          ],
        );
      case 'failed':
        return Text('감정 분석에 실패했어요. 기록에는 영향이 없어요.',
            style: TextStyle(color: scheme.onSurfaceVariant));
      case 'succeeded':
        final label = entry.effectiveAiLabel;
        if (label == null) {
          return Text('분석 결과가 없어요.',
              style: TextStyle(color: scheme.onSurfaceVariant));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: Icon(Icons.auto_awesome,
                      size: 14, color: scheme.secondary),
                  label: Text(diaryEmotionName(label)),
                ),
                if (entry.aiEmotionOverride != null && entry.aiEmotion != null)
                  Text(
                    '내가 수정함 (원래: ${diaryEmotionName(entry.aiEmotion)})',
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: mutating ? null : onEdit,
                  child: const Text('라벨 수정'),
                ),
                OutlinedButton(
                  onPressed: mutating ? null : onToggleHidden,
                  child: const Text('숨기기'),
                ),
              ],
            ),
          ],
        );
      default:
        return Text('알 수 없는 분석 상태예요.',
            style: TextStyle(color: scheme.onSurfaceVariant));
    }
  }
}
