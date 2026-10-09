/// Deterministic Gregorian calendar facts: month length, year length, leap
/// years, and the fact that the Gregorian calendar has no leap months.
///
/// The 2B model gets these wrong in confident ways (on device it called
/// October 2026 a "tháng nhuận" and claimed it needed the Internet to know
/// month lengths; docs/LLM_QUALITY.md). These answers are computed, stored
/// in the conversation like any reply, and so are visible to the model on
/// follow-up questions.
///
/// Matching: the question must *end* the message ("… tháng mười có bao
/// nhiêu ngày à?"), so a longer sentence may lead into it, but nothing may
/// follow except particles; "tháng này có bao nhiêu ngày nghỉ" is left to
/// the model.
abstract final class GregorianAnswers {
  static final RegExp _punctuation = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
  static final RegExp _spaces = RegExp(r'\s+');

  static const String _tail =
      r'(?:\s+(?:vậy|à|ạ|nhỉ|thế|hả|không|chưa|nhé|bạn|vậy bạn|ha))*$';

  static const Map<String, int> _monthWords = {
    'mười một': 11,
    'mười hai': 12,
    'một': 1,
    'hai': 2,
    'ba': 3,
    'tư': 4,
    'bốn': 4,
    'năm': 5,
    'sáu': 6,
    'bảy': 7,
    'tám': 8,
    'chín': 9,
    'mười': 10,
  };

  static final String _month =
      '(này|nay|sau|tới|trước|\\d{1,2}|${_monthWords.keys.join('|')})';
  static const String _year = r'(?:\s+năm\s+(nay|sau|tới|ngoái|trước|\d{4}))?';

  static final RegExp _monthLength = RegExp(
    'tháng $_month$_year\\s+(?:có\\s+)?(?:bao nhiêu|mấy)\\s+ngày$_tail',
  );
  static final RegExp _leapMonth = RegExp(
    'tháng $_month$_year\\s+(?:có\\s+)?(?:phải\\s+)?(?:là\\s+)?tháng nhuận$_tail',
  );
  static final RegExp _yearLength = RegExp(
    r'năm\s+(nay|sau|tới|ngoái|trước|\d{4})\s+(?:có\s+)?(?:bao nhiêu|mấy)\s+ngày'
    '$_tail',
  );
  static final RegExp _leapYear = RegExp(
    r'năm\s+(nay|sau|tới|ngoái|trước|\d{4})\s+(?:có\s+)?(?:phải\s+)?'
    r'(?:là\s+)?năm nhuận'
    '$_tail',
  );

  static const String _noLeapMonths =
      'Dương lịch không có tháng nhuận; tháng nhuận chỉ có trong âm lịch.';

  /// The reply for [message] at local time [now], or null.
  static String? answer(String message, DateTime now) {
    final text = message
        .toLowerCase()
        .replaceAll(_punctuation, ' ')
        .replaceAll(_spaces, ' ')
        .trim();

    final leapMonth = _leapMonth.firstMatch(text);
    if (leapMonth != null) {
      final (month, year) =
          _resolve(leapMonth[1]!, leapMonth[2], now) ?? (0, 0);
      if (month == 0) return null;
      return 'Không. Tháng $month năm $year không phải tháng nhuận. '
          '$_noLeapMonths ${_leapYearSentence(year)}';
    }

    final monthLength = _monthLength.firstMatch(text);
    if (monthLength != null) {
      final resolved = _resolve(monthLength[1]!, monthLength[2], now);
      if (resolved == null) return null;
      final (month, year) = resolved;
      final days = daysInMonth(year, month);
      final why = month == 2
          ? (isLeapYear(year)
                ? ' vì $year là năm nhuận'
                : ' vì $year không phải năm nhuận')
          : '';
      return 'Tháng $month năm $year có $days ngày (dương lịch)$why.';
    }

    final yearLength = _yearLength.firstMatch(text);
    if (yearLength != null) {
      final year = _resolveYear(yearLength[1]!, now);
      if (year == null) return null;
      return 'Năm $year có ${isLeapYear(year) ? 366 : 365} ngày '
          '(dương lịch). ${_leapYearSentence(year)}';
    }

    final leapYear = _leapYear.firstMatch(text);
    if (leapYear != null) {
      final year = _resolveYear(leapYear[1]!, now);
      if (year == null) return null;
      return _leapYearSentence(year);
    }
    return null;
  }

  static bool isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  static String _leapYearSentence(int year) => isLeapYear(year)
      ? 'Năm $year là năm nhuận: tháng 2 có 29 ngày, cả năm có 366 ngày.'
      : 'Năm $year không phải năm nhuận: tháng 2 có 28 ngày, cả năm có 365 ngày.';

  /// (month, year) or null when the month is not valid.
  static (int, int)? _resolve(
    String monthToken,
    String? yearToken,
    DateTime now,
  ) {
    final DateTime base;
    switch (monthToken) {
      case 'này' || 'nay':
        base = DateTime(now.year, now.month);
      case 'sau' || 'tới':
        base = DateTime(now.year, now.month + 1);
      case 'trước':
        base = DateTime(now.year, now.month - 1);
      default:
        final month = int.tryParse(monthToken) ?? _monthWords[monthToken];
        if (month == null || month < 1 || month > 12) return null;
        final year = yearToken == null
            ? now.year
            : _resolveYear(yearToken, now);
        if (year == null) return null;
        return (month, year);
    }
    if (yearToken != null) {
      final year = _resolveYear(yearToken, now);
      if (year == null) return null;
      return (base.month, year);
    }
    return (base.month, base.year);
  }

  static int? _resolveYear(String token, DateTime now) => switch (token) {
    'nay' => now.year,
    'sau' || 'tới' => now.year + 1,
    'ngoái' || 'trước' => now.year - 1,
    _ => (int.tryParse(token) ?? 0) >= 1583 ? int.parse(token) : null,
  };
}
