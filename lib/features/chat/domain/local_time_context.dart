/// Human-readable local date and time, computed from the device clock.
///
/// The model has no clock and no knowledge of "today"; every value here is
/// derived from the `DateTime` passed in (the injected app clock), at request
/// time. Nothing is hard-coded.
abstract final class LocalTimeContext {
  static const List<String> viWeekdays = [
    'Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật',
  ];

  static const List<String> enWeekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];

  static const List<String> enMonths = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];

  /// `Thứ Năm, ngày 8 tháng 10 năm 2026`
  static String viDate(DateTime t) =>
      '${viWeekdays[t.weekday - 1]}, ngày ${t.day} tháng ${t.month} năm ${t.year}';

  /// `Thursday, 8 October 2026`
  static String enDate(DateTime t) =>
      '${enWeekdays[t.weekday - 1]}, ${t.day} ${enMonths[t.month - 1]} ${t.year}';

  /// `22:05`
  static String clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  /// `UTC+07:00`
  static String utcOffset(DateTime t) {
    final offset = t.timeZoneOffset;
    final minutes = offset.inMinutes.abs();
    final sign = offset.isNegative ? '-' : '+';
    return 'UTC$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
  }

  /// `2026-10-08`
  static String isoDate(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';

  /// The same calendar day shifted by [days] (DST-safe: built from fields,
  /// not by adding 24-hour durations).
  static DateTime shiftDays(DateTime t, int days) =>
      DateTime(t.year, t.month, t.day + days, t.hour, t.minute);

  static String _two(int n) => n.toString().padLeft(2, '0');
}
