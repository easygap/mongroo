import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_formats.dart';
import '../../../core/error/api_exception.dart';
import '../data/report_repository.dart';
import '../domain/report.dart';

class ReportState {
  const ReportState({
    required this.periodType,
    required this.periodStart,
    required this.report,
    this.summaryTimedOut = false,
  });

  final String periodType; // weekly | monthly
  final DateTime periodStart;
  final AsyncValue<Report> report;

  /// 30초 폴링 후에도 요약이 pending이면 true.
  final bool summaryTimedOut;

  ReportState copyWith({
    String? periodType,
    DateTime? periodStart,
    AsyncValue<Report>? report,
    bool? summaryTimedOut,
  }) =>
      ReportState(
        periodType: periodType ?? this.periodType,
        periodStart: periodStart ?? this.periodStart,
        report: report ?? this.report,
        summaryTimedOut: summaryTimedOut ?? this.summaryTimedOut,
      );
}

/// 리포트 생성(POST) 후 요약 완료까지 2초 간격 최대 30초 폴링한다.
/// 통계는 POST 응답에 바로 포함되므로 폴링 중에도 화면에 보여준다.
class ReportController extends Notifier<ReportState> {
  static const _uuid = Uuid();
  static const pollInterval = Duration(seconds: 2);
  static const maxPolls = 15;

  /// 실패한 요청의 재시도에만 같은 키를 재사용한다.
  /// 성공하면 지워서 다음 조회가 오래된 응답 재생에 걸리지 않게 한다.
  final Map<String, String> _idempotencyKeys = {};
  int _generation = 0;

  @override
  ReportState build() {
    final now = DateTime.now();
    Future.microtask(load);
    return ReportState(
      periodType: 'weekly',
      periodStart: mondayOf(now),
      report: const AsyncLoading(),
    );
  }

  bool get canGoNext {
    final today = dateOnly(DateTime.now());
    return _shiftedStart(1).compareTo(today) <= 0;
  }

  void setPeriodType(String type) {
    if (type == state.periodType) return;
    final now = DateTime.now();
    final start =
        type == 'weekly' ? mondayOf(now) : DateTime(now.year, now.month, 1);
    state = ReportState(
      periodType: type,
      periodStart: start,
      report: const AsyncLoading(),
    );
    load();
  }

  void previousPeriod() => _moveTo(_shiftedStart(-1));

  void nextPeriod() {
    if (!canGoNext) return;
    _moveTo(_shiftedStart(1));
  }

  DateTime _shiftedStart(int delta) {
    final start = state.periodStart;
    if (state.periodType == 'weekly') {
      return start.add(Duration(days: 7 * delta));
    }
    return DateTime(start.year, start.month + delta, 1);
  }

  void _moveTo(DateTime start) {
    state = state.copyWith(
      periodStart: start,
      report: const AsyncLoading(),
      summaryTimedOut: false,
    );
    load();
  }

  Future<void> load() async {
    final generation = ++_generation;
    final periodType = state.periodType;
    final periodStart = formatApiDate(state.periodStart);
    final keyId = '$periodType:$periodStart';
    state =
        state.copyWith(report: const AsyncLoading(), summaryTimedOut: false);
    try {
      final key = _idempotencyKeys.putIfAbsent(keyId, () => _uuid.v4());
      var report = await ref.read(reportRepositoryProvider).create(
            periodType: periodType,
            periodStart: periodStart,
            idempotencyKey: key,
          );
      _idempotencyKeys.remove(keyId);
      if (generation != _generation) return;
      state = state.copyWith(report: AsyncData(report));
      await _pollSummary(report, generation);
    } on ApiException catch (e, stack) {
      if (generation != _generation) return;
      state = state.copyWith(report: AsyncError(e, stack));
    }
  }

  /// 요약이 늦어졌을 때 "다시 확인" 동작. POST 대신 GET으로만 조회한다.
  Future<void> refreshSummary() async {
    final current = state.report.valueOrNull;
    if (current == null) {
      await load();
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(summaryTimedOut: false);
    try {
      final report =
          await ref.read(reportRepositoryProvider).getById(current.id);
      if (generation != _generation) return;
      state = state.copyWith(report: AsyncData(report));
      await _pollSummary(report, generation);
    } on ApiException {
      if (generation != _generation) return;
      state = state.copyWith(summaryTimedOut: true);
    }
  }

  Future<void> _pollSummary(Report initial, int generation) async {
    var report = initial;
    var polls = 0;
    while (report.summaryPending && polls < maxPolls) {
      await Future<void>.delayed(pollInterval);
      if (generation != _generation) return;
      polls++;
      try {
        report = await ref.read(reportRepositoryProvider).getById(report.id);
      } on ApiException {
        continue;
      }
      if (generation != _generation) return;
      state = state.copyWith(report: AsyncData(report));
    }
    if (report.summaryPending && generation == _generation) {
      state = state.copyWith(summaryTimedOut: true);
    }
  }
}

final reportControllerProvider =
    NotifierProvider<ReportController, ReportState>(ReportController.new);
