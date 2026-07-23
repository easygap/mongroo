import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/mood/data/mood_repository.dart';
import 'package:mongroo/features/mood/domain/mood_entry.dart';
import 'package:mongroo/features/mood/presentation/calendar_screen.dart';

class _CalendarRepository implements MoodRepository {
  @override
  Future<MoodCalendar> getCalendar(
      {required int year, required int month}) async {
    return MoodCalendar(
      year: year,
      month: month,
      days: {
        '$year-${month.toString().padLeft(2, '0')}-01': CalendarDay(
          date: '$year-${month.toString().padLeft(2, '0')}-01',
          entryCount: 2,
          lastMoodLevel: 3,
          pendingCount: 1,
        ),
      },
    );
  }

  @override
  Future<MoodSaveResult> create({
    required int moodLevel,
    required List<String> emotionTags,
    required String? content,
    required String idempotencyKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(int id) => throw UnimplementedError();

  @override
  Future<List<MoodEntry>> getByDate(String date) => throw UnimplementedError();

  @override
  Future<List<MoodEntry>> getByIds(List<int> ids) => throw UnimplementedError();

  @override
  Future<MoodEntry> getById(int id) => throw UnimplementedError();

  @override
  Future<MoodSaveResult> patch(int id, Map<String, dynamic> changes) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('320px 화면과 200% 글자 크기에서도 날짜 터치 영역을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moodRepositoryProvider.overrideWithValue(_CalendarRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const CalendarScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('기록 달력'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final recordedDay = find.byWidgetPredicate(
      (widget) =>
          widget is InkWell &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('mood-day-') &&
          widget.onTap != null,
    );
    expect(recordedDay, findsOneWidget);
    expect(tester.getSize(recordedDay).width, greaterThanOrEqualTo(48));
  });
}
