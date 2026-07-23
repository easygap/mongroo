/// intl 없이 쓰는 간단한 날짜/시간 표기 도우미.
/// 데모는 기기 시간을 KST로 가정한다(design.md 시간 기준 참조).
library;

String formatApiDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// "7월 10일" 형태.
String formatKoreanMonthDay(DateTime d) => '${d.month}월 ${d.day}일';

/// "2026년 7월" 형태.
String formatKoreanYearMonth(DateTime d) => '${d.year}년 ${d.month}월';

/// "2026.05.01" 형태.
String formatDotDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}.$m.$day';
}

/// UTC ISO 문자열을 로컬 "HH:mm"으로.
String formatLocalTime(DateTime utc) {
  final local = utc.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$h:$min';
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 해당 날짜가 속한 주의 월요일(주 시작=월요일 계약).
DateTime mondayOf(DateTime d) =>
    dateOnly(d).subtract(Duration(days: d.weekday - DateTime.monday));
