import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../domain/report.dart';

/// 기분 추세 라인차트. 점을 누르면 그날 기록으로 내려갈 수 있다.
class MoodTrendChart extends StatelessWidget {
  const MoodTrendChart({
    super.key,
    required this.points,
    required this.onPointTap,
  });

  final List<MoodDailyPoint> points;
  final void Function(MoodDailyPoint point) onPointTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    if (points.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text('표시할 기분 기록이 없습니다.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      );
    }
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].avgMood),
    ];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: '기분 변화 차트, ${points.length}일. 아래 날짜 버튼에서 기록을 열 수 있습니다.',
          child: ExcludeSemantics(
            child: SizedBox(
              height: 190,
              child: LineChart(
                LineChartData(
                  minY: 1,
                  maxY: 5,
                  minX: -0.3,
                  maxX: (points.length - 1) + 0.3,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: scheme.outlineVariant.withAlpha(120),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            fontFamily: AppTheme.pixelFont,
                            fontSize: 11,
                            color: palette.inkMuted,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: points.length > 10 ? 2 : 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 ||
                              index >= points.length ||
                              value != index.toDouble()) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _shortDate(points[index].date),
                              style: TextStyle(
                                fontFamily: AppTheme.pixelFont,
                                fontSize: 10,
                                color: palette.inkMuted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) => [
                        for (final spot in touchedSpots)
                          LineTooltipItem(
                            '평균 ${spot.y.toStringAsFixed(1)} · ${points[spot.x.toInt()].count}건\n탭해서 기록 보기',
                            TextStyle(
                              color: scheme.onInverseSurface,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) return;
                      final spot = response?.lineBarSpots?.firstOrNull;
                      if (spot == null) return;
                      final index = spot.x.toInt();
                      if (index >= 0 && index < points.length) {
                        onPointTap(points[index]);
                      }
                    },
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      color: palette.coral,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                          radius: 4,
                          color: palette.butter,
                          strokeColor: palette.coral,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ],
                ),
                duration: reduceMotion ? Duration.zero : MongrooMotion.standard,
                curve: MongrooMotion.enter,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < points.length; index++) ...[
                _ChartStamp(
                  label: _shortDate(points[index].date),
                  value:
                      '${points[index].avgMood.toStringAsFixed(1)} · ${points[index].count}건',
                  semanticLabel:
                      '${_spokenDate(points[index].date)}, 평균 기분 ${points[index].avgMood.toStringAsFixed(1)}, 기록 ${points[index].count}건, 기록 보기',
                  onTap: points[index].entryIds.isEmpty
                      ? null
                      : () => onPointTap(points[index]),
                ),
                if (index != points.length - 1) const SizedBox(width: 7),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 시간대 패턴 바차트.
class TimeOfDayChart extends StatelessWidget {
  const TimeOfDayChart({
    super.key,
    required this.buckets,
    required this.onBucketTap,
  });

  final List<TimeOfDayCount> buckets;
  final void Function(TimeOfDayCount bucket) onBucketTap;

  static const _order = ['morning', 'afternoon', 'evening', 'night'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    // 4개 시간대를 고정 순서로 정렬하고 빈 구간은 0으로 채운다.
    final ordered = [
      for (final key in _order)
        buckets.firstWhere(
          (b) => b.bucket == key,
          orElse: () =>
              TimeOfDayCount(bucket: key, count: 0, entryIds: const []),
        ),
    ];
    final maxCount = ordered.fold<int>(0, (m, b) => b.count > m ? b.count : m);
    if (maxCount == 0) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text('표시할 시간대 기록이 없습니다.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      );
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: '기록 시간대 차트. 아래 시간대 버튼에서 기록을 열 수 있습니다.',
          child: ExcludeSemantics(
            child: SizedBox(
              height: 170,
              child: BarChart(
                BarChartData(
                  maxY: (maxCount + 1).toDouble(),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= ordered.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              ordered[index].label,
                              style: TextStyle(
                                fontFamily: AppTheme.pixelFont,
                                fontSize: 11,
                                color: palette.inkMuted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                          BarTooltipItem(
                        '${ordered[group.x].count}건\n탭해서 기록 보기',
                        TextStyle(
                          color: scheme.onInverseSurface,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) return;
                      final group = response?.spot?.touchedBarGroup;
                      if (group == null) return;
                      final bucket = ordered[group.x];
                      if (bucket.count > 0) onBucketTap(bucket);
                    },
                  ),
                  barGroups: [
                    for (var i = 0; i < ordered.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: ordered[i].count.toDouble(),
                            width: 24,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                            color: palette.leaf,
                          ),
                        ],
                      ),
                  ],
                ),
                duration: reduceMotion ? Duration.zero : MongrooMotion.standard,
                curve: MongrooMotion.enter,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final bucket in ordered)
              _ChartStamp(
                label: bucket.label,
                value: '${bucket.count}건',
                semanticLabel: bucket.count > 0
                    ? '${bucket.label}, 기록 ${bucket.count}건, 기록 보기'
                    : '${bucket.label}, 기록 없음',
                onTap: bucket.count > 0 ? () => onBucketTap(bucket) : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// 태그·AI 라벨 분포에 함께 쓰는 가로 막대 행.
class DistributionBarRow extends StatelessWidget {
  const DistributionBarRow({
    super.key,
    required this.label,
    required this.count,
    required this.maxCount,
    required this.color,
    required this.onTap,
    this.semanticContext,
  });

  final String label;
  final int count;
  final int maxCount;
  final Color color;
  final VoidCallback onTap;
  final String? semanticContext;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final fraction = maxCount == 0 ? 0.0 : count / maxCount;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    return MongrooPressable(
      onTap: onTap,
      semanticLabel: [
        if (semanticContext != null) semanticContext!,
        label,
        '기록 $count건',
        '기록 보기',
      ].join(', '),
      borderRadius: BorderRadius.circular(6),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: largeText ? 112 : 84,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 8,
                      color: color,
                      backgroundColor: palette.paperDeep,
                    ),
                  ),
                ),
                SizedBox(
                  width: largeText ? 62 : 44,
                  child: Text(
                    '$count건',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontFamily: AppTheme.pixelFont,
                      fontSize: 11,
                      color: palette.inkMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: palette.inkMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartStamp extends StatelessWidget {
  const _ChartStamp({
    required this.label,
    required this.value,
    required this.semanticLabel,
    required this.onTap,
  });

  final String label;
  final String value;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final enabled = onTap != null;
    return MongrooPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      borderRadius: BorderRadius.circular(6),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 74),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: enabled ? palette.paper : palette.paperDeep,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: palette.inkMuted.withAlpha(90)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: enabled ? palette.ink : palette.inkMuted,
                      fontFamily: AppTheme.pixelFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: palette.inkMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _shortDate(String raw) {
  final date = DateTime.tryParse(raw);
  return date == null ? raw : '${date.month}/${date.day}';
}

String _spokenDate(String raw) {
  final date = DateTime.tryParse(raw);
  return date == null ? raw : '${date.month}월 ${date.day}일';
}
