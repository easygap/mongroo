import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/mood/domain/calendar_month.dart';

void main() {
  group('CalendarMonth', () {
    test('2026년 7월: 수요일 시작, 31일', () {
      final month = CalendarMonth(2026, 7);

      expect(month.daysInMonth, 31);
      // 2026-07-01은 수요일 → 월요일 시작 그리드에서 빈 칸 2개.
      expect(month.leadingEmptyCells, 2);

      final cells = month.cells;
      expect(cells.length % 7, 0);
      expect(cells.length, 35);
      expect(cells[0], isNull);
      expect(cells[1], isNull);
      expect(cells[2], DateTime(2026, 7, 1));
      expect(cells[2 + 30], DateTime(2026, 7, 31));
      expect(cells.last, isNull);
    });

    test('2024년 2월: 윤년 29일, 목요일 시작', () {
      final month = CalendarMonth(2024, 2);

      expect(month.daysInMonth, 29);
      expect(month.leadingEmptyCells, 3);
      expect(month.cells.length, 35);
      expect(month.cells[3], DateTime(2024, 2, 1));
    });

    test('2025년 6월: 일요일 시작이라 빈 칸 6개, 6주 그리드', () {
      final month = CalendarMonth(2025, 6);

      expect(month.daysInMonth, 30);
      expect(month.leadingEmptyCells, 6);
      expect(month.cells.length, 42);
      expect(month.weekCount, 6);
      expect(month.cells[6], DateTime(2025, 6, 1));
      expect(month.cells[6 + 29], DateTime(2025, 6, 30));
    });

    test('월요일에 시작하는 달은 빈 칸이 없다', () {
      // 2025-09-01은 월요일.
      final month = CalendarMonth(2025, 9);

      expect(month.leadingEmptyCells, 0);
      expect(month.cells.first, DateTime(2025, 9, 1));
    });

    test('연 경계를 넘는 이전/다음 달 이동', () {
      expect(CalendarMonth(2026, 1).previous.year, 2025);
      expect(CalendarMonth(2026, 1).previous.month, 12);
      expect(CalendarMonth(2026, 12).next.year, 2027);
      expect(CalendarMonth(2026, 12).next.month, 1);
    });
  });
}
