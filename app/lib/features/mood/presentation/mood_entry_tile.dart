import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../domain/mood_entry.dart';
import 'mood_style.dart';

/// 일자 목록과 리포트에서 함께 쓰는 기록 행.
class MoodEntryTile extends StatelessWidget {
  const MoodEntryTile({super.key, required this.entry, this.showDate = false});

  final MoodEntry entry;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusLabel = analysisStatusLabel(entry.analysisStatus);
    final snippet = (entry.content ?? '').replaceAll('\n', ' ');
    final recordTime = showDate
        ? formatKoreanApiDate(entry.localDate)
        : formatLocalTime(entry.recordedAt);
    final displayLabel = entry.moodLevelExplicit
        ? moodLevelName(entry.moodLevel)
        : diaryAnalysisDisplayLabel(
            status: entry.analysisStatus,
            emotion: entry.effectiveAiLabel,
            hidden: entry.aiLabelHidden,
          );
    final title = '$recordTime · $displayLabel';
    final showsAnalyzedEmotion = !entry.moodLevelExplicit &&
        !entry.aiLabelHidden &&
        entry.analysisStatus == 'succeeded' &&
        entry.effectiveAiLabel != null;
    final brightness = Theme.of(context).brightness;
    final markerColor = entry.moodLevelExplicit
        ? moodLevelColor(entry.moodLevel, brightness: brightness)
        : showsAnalyzedEmotion
            ? diaryEmotionColor(entry.effectiveAiLabel, brightness: brightness)
            : scheme.primary;
    final markerIcon = entry.moodLevelExplicit
        ? moodLevelIcon(entry.moodLevel)
        : showsAnalyzedEmotion
            ? diaryEmotionIcon(entry.effectiveAiLabel)
            : diaryAnalysisIcon(
                entry.analysisStatus,
                hidden: entry.aiLabelHidden,
              );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MongrooPressable(
        onTap: () => context.push('/moods/${entry.id}'),
        semanticLabel: '$title 기록 보기',
        child: MongrooPanel(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          shadowOffset: const Offset(2, 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: markerColor.withAlpha(35),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: markerColor),
                ),
                child: Icon(
                  markerIcon,
                  color: markerColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: AppTheme.pixelFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (entry.emotionTags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.emotionTags.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                    if (snippet.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    if (entry.moodLevelExplicit && statusLabel != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        statusLabel,
                        style: TextStyle(fontSize: 11, color: scheme.tertiary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
