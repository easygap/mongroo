import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mood_repository.dart';
import '../domain/mood_entry.dart';

/// 월별 캘린더 집계.
final moodCalendarProvider = FutureProvider.autoDispose
    .family<MoodCalendar, ({int year, int month})>((ref, arg) {
  return ref
      .watch(moodRepositoryProvider)
      .getCalendar(year: arg.year, month: arg.month);
});

/// 특정 일자의 기록 목록.
final dayEntriesProvider =
    FutureProvider.autoDispose.family<List<MoodEntry>, String>((ref, date) {
  return ref.watch(moodRepositoryProvider).getByDate(date);
});

/// 기록 상세.
final moodDetailProvider =
    FutureProvider.autoDispose.family<MoodEntry, int>((ref, id) {
  return ref.watch(moodRepositoryProvider).getById(id);
});
