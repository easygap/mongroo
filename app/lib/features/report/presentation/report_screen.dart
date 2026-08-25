import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_formats.dart';
import '../../../core/error/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../mood/presentation/mood_entries_by_ids_screen.dart';
import '../../mood/presentation/mood_style.dart';
import '../domain/report.dart';
import 'report_charts.dart';
import 'report_controller.dart';

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  void _openEntries(BuildContext context, String title, List<int> ids) {
    if (ids.isEmpty) return;
    context.push(
      '/moods/entries',
      extra: MoodEntriesByIdsArgs(title: title, entryIds: ids),
    );
  }

  String _periodLabel(ReportState state) {
    final start = state.periodStart;
    if (state.periodType == 'monthly') {
      return formatKoreanYearMonth(start);
    }
    final end = start.add(const Duration(days: 6));
    return '${formatKoreanMonthDay(start)} ~ ${formatKoreanMonthDay(end)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportControllerProvider);
    final controller = ref.read(reportControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('마음 회고')),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth > 880 ? (constraints.maxWidth - 840) / 2 : 16,
            16,
            constraints.maxWidth > 880 ? (constraints.maxWidth - 840) / 2 : 16,
            32,
          ),
          children: [
            _ReportPeriodToolbar(
              periodType: state.periodType,
              label: _periodLabel(state),
              onPeriodTypeChanged: controller.setPeriodType,
              onPrevious: controller.previousPeriod,
              onNext: controller.canGoNext ? controller.nextPeriod : null,
            ),
            const SizedBox(height: 16),
            ...state.report.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (error, _) => [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Text(ApiException.from(error).message,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: controller.load,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              ],
              data: (report) => _buildReport(context, ref, report, state),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildReport(
      BuildContext context, WidgetRef ref, Report report, ReportState state) {
    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    final stats = report.stats;
    if (stats == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('통계를 계산 중입니다.')),
        ),
      ];
    }
    if (stats.totalEntries == 0) {
      return [
        _EmptyReportView(onRecord: () => context.push('/record')),
      ];
    }

    final maxTag =
        stats.tagDistribution.fold<int>(0, (m, t) => t.count > m ? t.count : m);
    final maxAi = stats.aiEmotionDistribution
        .fold<int>(0, (m, t) => t.count > m ? t.count : m);

    return [
      MongrooPanel(
        key: const ValueKey('report-ai-ledger'),
        padding: EdgeInsets.zero,
        color: palette.paper,
        borderColor: palette.inkMuted.withAlpha(120),
        shadowOffset: Offset.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReportLedgerHeader(
              tag: '이번 기간',
              tagIcon: Icons.auto_awesome_rounded,
              tagColor: palette.butter,
              title: '마음 이야기',
              description: '일기에서 되풀이된 마음과 돌아볼 질문을 함께 보여 줄게요.',
            ),
            const Divider(height: 1),
            _ReportSection(
              title: '이번 기간 한 문장 회고',
              child: _AiSummaryBlock(
                report: report,
                summaryTimedOut: state.summaryTimedOut,
                onRefresh: () => ref
                    .read(reportControllerProvider.notifier)
                    .refreshSummary(),
              ),
            ),
            const Divider(height: 1),
            _ReportSection(
              key: const ValueKey('report-ai-emotions'),
              title: '일기에서 자주 읽힌 마음',
              subtitle: '어느 마음도 좋고 나쁨으로 채점하지 않아요.',
              child: stats.aiEmotionDistribution.isEmpty
                  ? Text(
                      '아직 일기에서 읽은 감정이 없습니다.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    )
                  : Column(
                      children: [
                        for (final emotion in stats.aiEmotionDistribution)
                          DistributionBarRow(
                            label: diaryEmotionName(emotion.emotion),
                            count: emotion.count,
                            maxCount: maxAi,
                            // 달력이 가르쳐 준 마음별 색을 회고에서도 그대로
                            // 쓴다. 전부 같은 초록이면 어느 마음이 얼마나
                            // 쌓였는지 막대 길이로만 읽어야 했다.
                            color: diaryEmotionColor(
                              emotion.emotion,
                              brightness: Theme.of(context).brightness,
                            ),
                            semanticContext: '일기에서 읽은 감정',
                            onTap: () => _openEntries(
                              context,
                              '읽힌 감정: ${diaryEmotionName(emotion.emotion)}',
                              emotion.entryIds,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _StatsOverview(
        entries: '${stats.totalEntries}건',
        coverage: report.analysisCoverage == null
            ? '-'
            : '${(report.analysisCoverage! * 100).round()}%',
        streak: '${stats.streak.current}일',
        coverageDetail:
            '일기 ${stats.entriesWithText}편 중 ${stats.analyzedEntries}편의 마음 읽기 완료',
      ),
      const SizedBox(height: 16),
      MongrooPanel(
        key: const ValueKey('report-user-ledger'),
        padding: EdgeInsets.zero,
        shadowOffset: const Offset(2, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReportLedgerHeader(
              tag: '세부 기록',
              tagIcon: Icons.edit_note_rounded,
              tagColor: palette.butter,
              title: '기록 더 살펴보기',
              description: '항목을 누르면 근거가 된 일기로 돌아갈 수 있어요.',
            ),
            const Divider(height: 1),
            if (stats.hasExplicitMoodEntries) ...[
              _ReportSection(
                title: '예전 기록의 마음 날씨',
                child: MoodTrendChart(
                  points: stats.moodDaily,
                  onPointTap: (point) => _openEntries(
                    context,
                    '${point.date} 기록',
                    point.entryIds,
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
            if (stats.tagDistribution.isNotEmpty) ...[
              _ReportSection(
                key: const ValueKey('report-user-emotions'),
                title: '예전 기록에서 직접 고른 감정',
                child: Column(
                  children: [
                    for (final tag in stats.tagDistribution)
                      DistributionBarRow(
                        label: tag.tag,
                        count: tag.count,
                        maxCount: maxTag,
                        color: scheme.primary,
                        semanticContext: '직접 선택한 감정',
                        onTap: () => _openEntries(
                          context,
                          '태그: ${tag.tag}',
                          tag.entryIds,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
            _ReportSection(
              title: '기록 시간대',
              child: TimeOfDayChart(
                buckets: stats.timeOfDay,
                onBucketTap: (bucket) => _openEntries(
                  context,
                  '${bucket.label} 기록',
                  bucket.entryIds,
                ),
              ),
            ),
            const Divider(height: 1),
            _ReportSection(
              title: '일기 키워드',
              child: stats.keywords.isEmpty
                  ? Text(
                      '아직 모인 키워드가 없어요.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final keyword in stats.keywords)
                          ActionChip(
                            avatar: const Icon(Icons.search_rounded, size: 16),
                            label: Text(keyword.keyword),
                            tooltip: '${keyword.keyword} 기록 보기',
                            onPressed: () => _openEntries(
                              context,
                              '키워드: ${keyword.keyword}',
                              keyword.entryIds,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ];
  }
}

class _EmptyReportView extends StatelessWidget {
  const _EmptyReportView({required this.onRecord});

  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 52),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              children: [
                const Icon(Icons.mark_as_unread_outlined, size: 44),
                const SizedBox(height: 14),
                const Text(
                  '아직 모인 마음 이야기가 없어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                const Text(
                  '일기를 남기면 되풀이된 마음과 돌아볼 질문을 여기에 모아 줄게요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.5),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRecord,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('오늘 이야기 남기기'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ReportPeriodToolbar extends StatelessWidget {
  const _ReportPeriodToolbar({
    required this.periodType,
    required this.label,
    required this.onPeriodTypeChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final String periodType;
  final String label;
  final ValueChanged<String> onPeriodTypeChanged;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final periodSelector = SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'weekly', label: Text('주간')),
        ButtonSegment(value: 'monthly', label: Text('월간')),
      ],
      selected: {periodType},
      onSelectionChanged: (selection) => onPeriodTypeChanged(selection.first),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(68, 44)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );

    return MongrooPanel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      shadowOffset: const Offset(2, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 360 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final tag = MongrooTag(
                label: '기록 범위',
                icon: Icons.calendar_today_outlined,
                backgroundColor: palette.butter,
              );
              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tag,
                    const SizedBox(height: 10),
                    Align(
                        alignment: Alignment.centerLeft, child: periodSelector),
                  ],
                );
              }
              return Row(
                children: [
                  tag,
                  const Spacer(),
                  periodSelector,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 4),
          _ReportPeriodSwitcher(
            label: label,
            onPrevious: onPrevious,
            onNext: onNext,
          ),
        ],
      ),
    );
  }
}

class _ReportPeriodSwitcher extends StatelessWidget {
  const _ReportPeriodSwitcher({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: AppTheme.pixelFont,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    final previous = TextButton.icon(
      onPressed: onPrevious,
      icon: const Icon(Icons.chevron_left),
      label: const Text('이전'),
    );
    final next = TextButton.icon(
      onPressed: onNext,
      icon: const Icon(Icons.chevron_right),
      iconAlignment: IconAlignment.end,
      label: const Text('다음'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 390 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: title,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [previous, next],
              ),
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [previous, title, next],
        );
      },
    );
  }
}

class _StatsOverview extends StatelessWidget {
  const _StatsOverview({
    required this.entries,
    required this.coverage,
    required this.streak,
    required this.coverageDetail,
  });

  final String entries;
  final String coverage;
  final String streak;
  final String coverageDetail;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final tiles = [
      _StatTile(label: '기록', value: entries),
      _StatTile(label: '마음 읽기', value: coverage),
      _StatTile(label: '최근 이어 쓴 날', value: streak),
    ];
    return MongrooPanel(
      padding: EdgeInsets.zero,
      shadowOffset: const Offset(2, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: MongrooTag(
                label: '기간 기록표',
                icon: Icons.assignment_outlined,
                backgroundColor: palette.butter,
              ),
            ),
          ),
          const Divider(height: 1),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 420 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < tiles.length; index++) ...[
                      _StatTile(
                        label: tiles[index].label,
                        value: tiles[index].value,
                        horizontal: true,
                      ),
                      if (index != tiles.length - 1)
                        const Divider(height: 1, indent: 14, endIndent: 14),
                    ],
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < tiles.length; index++) ...[
                      Expanded(child: tiles[index]),
                      if (index != tiles.length - 1)
                        const VerticalDivider(width: 1),
                    ],
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  size: 16,
                  color: palette.inkMuted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '마음 읽기 상태 · $coverageDetail',
                    style: TextStyle(fontSize: 12, color: palette.inkMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.horizontal = false,
  });

  final String label;
  final String value;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final valueText = Text(
      value,
      style: TextStyle(
        color: palette.ink,
        fontFamily: AppTheme.pixelFont,
        fontSize: 19,
        fontWeight: FontWeight.w700,
      ),
    );
    final labelText = Text(
      label,
      style: TextStyle(fontSize: 12, color: palette.inkMuted),
    );
    return Semantics(
      label: '$label $value',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: horizontal
              ? Row(
                  children: [
                    Expanded(child: labelText),
                    const SizedBox(width: 12),
                    valueText,
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    valueText,
                    const SizedBox(height: 3),
                    labelText,
                  ],
                ),
        ),
      ),
    );
  }
}

class _ReportLedgerHeader extends StatelessWidget {
  const _ReportLedgerHeader({
    required this.tag,
    required this.tagIcon,
    required this.tagColor,
    required this.title,
    required this.description,
  });

  final String tag;
  final IconData tagIcon;
  final Color tagColor;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MongrooTag(
            label: tag,
            icon: tagIcon,
            backgroundColor: tagColor,
            foregroundColor: palette.ink,
          ),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            description,
            style: TextStyle(fontSize: 12, color: palette.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 12, color: palette.inkMuted),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// AI 참고 패널 안에서 상태와 면책을 함께 보여 주는 요약 블록.
class _AiSummaryBlock extends StatelessWidget {
  const _AiSummaryBlock({
    required this.report,
    required this.summaryTimedOut,
    required this.onRefresh,
  });

  final Report report;
  final bool summaryTimedOut;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBody(context),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: palette.inkMuted),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '생성형 AI가 위 통계로 만든 참고 문장입니다. '
                '의료 진단이나 치료 권고가 아닙니다.'
                '${report.summaryModelVersion != null ? '\n생성 모델 · ${report.summaryModelVersion}' : ''}',
                style: TextStyle(fontSize: 11, color: palette.inkMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = report.summary;

    if (report.summaryFailed) {
      return Text(
        'AI 요약 생성에 실패했습니다. 통계 데이터는 정상입니다.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }
    if (summary == null) {
      if (summaryTimedOut) {
        return Semantics(
          liveRegion: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final message = Text(
                'AI 요약 생성이 지연되고 있습니다.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              );
              final retry = OutlinedButton(
                onPressed: onRefresh,
                child: const Text('다시 확인'),
              );
              if (constraints.maxWidth < 380 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    message,
                    const SizedBox(height: 10),
                    retry,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: message),
                  const SizedBox(width: 12),
                  retry,
                ],
              );
            },
          ),
        );
      }
      return Semantics(
        liveRegion: true,
        label: 'AI 요약 생성 중',
        child: ExcludeSemantics(
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI 요약 생성 중',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary.overview.isNotEmpty)
          Text(summary.overview, style: const TextStyle(height: 1.5)),
        if (summary.patterns.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('확인된 패턴',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final pattern in summary.patterns)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('· $pattern'),
            ),
        ],
        if (summary.reflectionQuestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('돌아볼 질문',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final question in summary.reflectionQuestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('· $question'),
            ),
        ],
      ],
    );
  }
}
