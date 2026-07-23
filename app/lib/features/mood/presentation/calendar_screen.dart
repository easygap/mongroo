import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_formats.dart';
import '../../../core/error/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../domain/calendar_month.dart';
import '../domain/mood_entry.dart';
import 'mood_providers.dart';
import 'mood_style.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late CalendarMonth _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = CalendarMonth(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final calendarAsync = ref
        .watch(moodCalendarProvider((year: _month.year, month: _month.month)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('기록 달력'),
        actions: [
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              setState(() => _month = CalendarMonth(now.year, now.month));
            },
            child: const Text('오늘'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/record'),
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('오늘 이야기 남기기'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth > 760
                ? (constraints.maxWidth - 720) / 2
                : constraints.maxWidth < 400
                    ? 8
                    : 16,
            16,
            constraints.maxWidth > 760
                ? (constraints.maxWidth - 720) / 2
                : constraints.maxWidth < 400
                    ? 8
                    : 16,
            32,
          ),
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: MongrooTag(
                label: '월간 기록',
                icon: Icons.calendar_month_outlined,
              ),
            ),
            const SizedBox(height: 10),
            _MonthSwitcher(
              label: formatKoreanYearMonth(
                DateTime(_month.year, _month.month),
              ),
              onPrevious: () => setState(() => _month = _month.previous),
              onNext: () => setState(() => _month = _month.next),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, boardConstraints) {
                // 7열 달력은 320px 화면 안에 억지로 줄이면 날짜별 터치 영역이
                // 44px 아래로 작아진다. 최소 336px을 확보하고 아주 좁은 화면에서만
                // 짧게 가로 스크롤되도록 해 각 날짜가 48px 이상을 유지하게 한다.
                final boardWidth = boardConstraints.maxWidth < 336
                    ? 336.0
                    : boardConstraints.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: boardWidth,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (final label in CalendarMonth.weekdayLabels)
                              Expanded(
                                child: Center(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        calendarAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 60),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (error, _) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              children: [
                                Text(
                                  ApiException.from(error).message,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: () => ref.invalidate(
                                    moodCalendarProvider((
                                      year: _month.year,
                                      month: _month.month,
                                    )),
                                  ),
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                          data: (calendar) =>
                              _MonthGrid(month: _month, calendar: calendar),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            const Wrap(
              spacing: 14,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _CalendarLegend(
                  icon: Icons.auto_awesome_rounded,
                  label: '일기에서 읽음',
                ),
                _CalendarLegend(
                  icon: Icons.hourglass_top_rounded,
                  label: '읽는 중',
                ),
                _CalendarLegend(
                  icon: Icons.wb_sunny_outlined,
                  label: '이전 직접 선택',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '표시는 그날 마지막 일기에서 읽은 마음이에요.\n'
              '날짜를 누르면 기록을 볼 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: AppTheme.pixelFont,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
    final previous = TextButton.icon(
      onPressed: onPrevious,
      icon: const Icon(Icons.chevron_left),
      label: const Text('이전 달'),
    );
    final next = TextButton.icon(
      onPressed: onNext,
      icon: const Icon(Icons.chevron_right),
      iconAlignment: IconAlignment.end,
      label: const Text('다음 달'),
    );
    if (MediaQuery.textScalerOf(context).scale(1) > 1.4) {
      return Column(
        children: [
          title,
          const SizedBox(height: 4),
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
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.calendar});

  final CalendarMonth month;
  final MoodCalendar calendar;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final cells = month.cells;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        // 200% 글자에서는 날짜·날씨 아이콘·기록 수가 세로로 겹치지 않도록
        // 셀 높이도 함께 키운다. 바깥 ListView가 세로 스크롤을 맡는다.
        mainAxisExtent: textScale > 1.4 ? 140 : 64,
      ),
      itemCount: cells.length,
      itemBuilder: (context, index) {
        final date = cells[index];
        if (date == null) return const SizedBox.shrink();
        final key = formatApiDate(date);
        final day = calendar.days[key];
        final isToday = date == today;
        return _DayCell(date: date, day: day, isToday: isToday, dateKey: key);
      },
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: scheme.primary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.day,
    required this.isToday,
    required this.dateKey,
  });

  final DateTime date;
  final CalendarDay? day;
  final bool isToday;
  final String dateKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasEntries = (day?.entryCount ?? 0) > 0;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final explicitMood =
        day?.lastMoodLevelExplicit == true && day?.lastMoodLevel != null;
    final displayLabel = explicitMood
        ? moodLevelName(day!.lastMoodLevel!)
        : diaryAnalysisDisplayLabel(
            status: day?.lastAnalysisStatus ?? 'not_requested',
            emotion: day?.lastAiEmotion,
          );
    final showsAnalyzedEmotion = !explicitMood &&
        day?.lastAnalysisStatus == 'succeeded' &&
        day?.lastAiEmotion != null;
    final markerColor = explicitMood
        ? moodLevelColor(day!.lastMoodLevel!)
        : showsAnalyzedEmotion
            ? diaryEmotionColor(day?.lastAiEmotion)
            : scheme.primary;
    final markerIcon = explicitMood
        ? moodLevelIcon(day!.lastMoodLevel!)
        : showsAnalyzedEmotion
            ? diaryEmotionIcon(day?.lastAiEmotion)
            : diaryAnalysisIcon(day?.lastAnalysisStatus ?? 'not_requested');
    return Semantics(
      excludeSemantics: true,
      button: hasEntries,
      label: hasEntries
          ? '${date.month}월 ${date.day}일, 기록 ${day!.entryCount}건, '
              '$displayLabel'
              '${day!.pendingCount > 0 ? ', 분석 중' : ''}'
          : '${date.month}월 ${date.day}일',
      child: InkWell(
        key: ValueKey('mood-day-$dateKey'),
        onTap: hasEntries ? () => context.push('/moods/day/$dateKey') : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: hasEntries ? markerColor.withAlpha(12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border:
                isToday ? Border.all(color: scheme.primary, width: 1.5) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 3),
              if (day != null) ...[
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: markerColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: markerColor,
                    ),
                  ),
                  child: Icon(
                    markerIcon,
                    size: 14,
                    color: markerColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  largeText
                      ? '${day!.entryCount}건'
                      : day!.pendingCount > 0
                          ? '${day!.entryCount}건 분석중'
                          : '${day!.entryCount}건',
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
