/// 외부 캘린더 패키지 없이 쓰는 월 그리드 계산.
/// 주 시작은 월요일(서버 주간 리포트 경계와 동일).
class CalendarMonth {
  CalendarMonth(this.year, this.month)
      : assert(month >= 1 && month <= 12, 'month는 1~12');

  final int year;
  final int month;

  /// DateTime(year, month + 1, 0)은 해당 월의 마지막 날이 된다.
  int get daysInMonth => DateTime(year, month + 1, 0).day;

  /// 1일이 시작하기 전 채워야 할 빈 칸 수(월요일 시작).
  int get leadingEmptyCells =>
      (DateTime(year, month, 1).weekday - DateTime.monday) % 7;

  /// 7의 배수 길이로 채운 셀 목록. 빈 칸은 null.
  List<DateTime?> get cells {
    final result = <DateTime?>[
      for (var i = 0; i < leadingEmptyCells; i++) null,
      for (var day = 1; day <= daysInMonth; day++) DateTime(year, month, day),
    ];
    while (result.length % 7 != 0) {
      result.add(null);
    }
    return result;
  }

  int get weekCount => cells.length ~/ 7;

  CalendarMonth get previous =>
      month == 1 ? CalendarMonth(year - 1, 12) : CalendarMonth(year, month - 1);

  CalendarMonth get next =>
      month == 12 ? CalendarMonth(year + 1, 1) : CalendarMonth(year, month + 1);

  static const List<String> weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];
}
