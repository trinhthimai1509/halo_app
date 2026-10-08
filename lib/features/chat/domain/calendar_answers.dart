import 'local_time_context.dart';

/// Answers simple calendar questions ("hôm nay là thứ mấy?") from the device
/// clock instead of the language model, which cannot know the date and
/// otherwise guesses.
///
/// Matching is deliberately strict: after removing punctuation, a leading
/// greeting / politeness phrase and trailing particles, the *whole* message
/// must be one of the supported questions. Anything more ("hôm nay là thứ
/// mấy và trời có mưa không?") goes to the model, which also receives the
/// date in its system prompt.
abstract final class CalendarAnswers {
  static final RegExp _punctuation = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
  static final RegExp _spaces = RegExp(r'\s+');

  static final RegExp _leading = RegExp(
    r'^(?:(?:xin chào|chào bạn|chào halo|chào|hello|hi|halo|bạn ơi|halo ơi|ơi'
    r'|cho (?:tôi|mình|em|anh|chị) hỏi|(?:bạn )?cho (?:tôi|mình) biết'
    r'|bạn có biết|bạn biết|vậy|thế)\s+)+',
  );
  static final RegExp _trailing = RegExp(
    r'(?:\s+(?:vậy|nhỉ|ạ|thế|đấy|hả|nhé|nhờ|vậy bạn|bạn|rồi|không|ha))+$',
  );

  static const String _today = r'(?:hôm nay|nay|bữa nay)';
  static const String _tomorrow = r'(?:ngày mai|mai)';
  static const String _yesterday = r'(?:hôm qua)';
  static const String _weekdayQ = r'(?:là )?(?:ngày )?thứ mấy';
  static const String _dateQ =
      r'(?:là )?(?:ngày )?(?:bao nhiêu|mấy|mùng mấy)'
      r'(?: tháng (?:mấy|bao nhiêu))?(?: năm (?:nào|mấy|bao nhiêu))?';

  static final Map<RegExp, _Kind> _patterns = {
    RegExp('^$_today $_weekdayQ\$'): _Kind.today,
    RegExp('^$_today $_dateQ\$'): _Kind.today,
    RegExp('^$_tomorrow $_weekdayQ\$'): _Kind.tomorrow,
    RegExp('^$_tomorrow $_dateQ\$'): _Kind.tomorrow,
    RegExp('^$_yesterday $_weekdayQ\$'): _Kind.yesterday,
    RegExp('^$_yesterday $_dateQ\$'): _Kind.yesterday,
    RegExp(r'^(?:bây giờ|giờ|hiện tại|hiện giờ)(?: là)? mấy giờ$'):
        _Kind.time,
    RegExp(
        r'^(?:what day is (?:it )?today|what is today s date'
        r'|what s the date today|what is the date today|what day is it)$'):
        _Kind.todayEnglish,
    RegExp(r'^what time is it(?: now)?$'): _Kind.timeEnglish,
  };

  /// The reply for [message] at local time [now], or null when the message
  /// is not a plain calendar question.
  static String? answer(String message, DateTime now) {
    final normalized = message
        .toLowerCase()
        .replaceAll("'", ' ')
        .replaceAll(_punctuation, ' ')
        .replaceAll(_spaces, ' ')
        .trim();
    final greeted = normalized.startsWith(RegExp(r'(?:xin chào|chào|hello|hi)\b'));
    final core = normalized.replaceFirst(_leading, '').replaceFirst(_trailing, '');

    for (final entry in _patterns.entries) {
      if (!entry.key.hasMatch(core)) continue;
      final text = _reply(entry.value, now);
      final english = entry.value == _Kind.todayEnglish ||
          entry.value == _Kind.timeEnglish;
      if (!greeted) return text;
      return english ? 'Hello! $text' : 'Xin chào! $text';
    }
    return null;
  }

  static String _reply(_Kind kind, DateTime now) => switch (kind) {
        _Kind.today => 'Hôm nay là ${LocalTimeContext.viDate(now)}.',
        _Kind.tomorrow =>
          'Ngày mai là ${LocalTimeContext.viDate(LocalTimeContext.shiftDays(now, 1))}.',
        _Kind.yesterday =>
          'Hôm qua là ${LocalTimeContext.viDate(LocalTimeContext.shiftDays(now, -1))}.',
        _Kind.time => 'Bây giờ là ${LocalTimeContext.clock(now)} '
            '(giờ địa phương, ${LocalTimeContext.utcOffset(now)}).',
        _Kind.todayEnglish => 'Today is ${LocalTimeContext.enDate(now)}.',
        _Kind.timeEnglish => 'It is ${LocalTimeContext.clock(now)} '
            '(local time, ${LocalTimeContext.utcOffset(now)}).',
      };
}

enum _Kind { today, tomorrow, yesterday, time, todayEnglish, timeEnglish }
