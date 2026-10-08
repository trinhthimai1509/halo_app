import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/chat/domain/calendar_answers.dart';

void main() {
  // Thursday 8 Oct 2026, 22:05 (local test time zone).
  final now = DateTime(2026, 10, 8, 22, 5);

  group('answers plain calendar questions from the clock', () {
    for (final q in [
      'Hôm nay là thứ mấy?',
      'hôm nay thứ mấy',
      'Hôm nay là ngày bao nhiêu?',
      'Hôm nay là ngày mấy tháng mấy năm nào?',
      'Cho tôi hỏi hôm nay là thứ mấy vậy?',
      'Bạn có biết hôm nay là thứ mấy không',
    ]) {
      test(q, () {
        expect(
          CalendarAnswers.answer(q, now),
          'Hôm nay là Thứ Năm, ngày 8 tháng 10 năm 2026.',
        );
      });
    }

    test('greeting first, as in the real voice transcript', () {
      expect(
        CalendarAnswers.answer('Xin chào hôm nay là thứ mấy', now),
        'Xin chào! Hôm nay là Thứ Năm, ngày 8 tháng 10 năm 2026.',
      );
    });

    test('tomorrow and yesterday, across a month boundary', () {
      final endOfMonth = DateTime(2026, 10, 31, 9);
      expect(
        CalendarAnswers.answer('Ngày mai là thứ mấy?', endOfMonth),
        'Ngày mai là Chủ Nhật, ngày 1 tháng 11 năm 2026.',
      );
      expect(
        CalendarAnswers.answer('Hôm qua là ngày bao nhiêu?', now),
        'Hôm qua là Thứ Tư, ngày 7 tháng 10 năm 2026.',
      );
    });

    test('current time with UTC offset', () {
      final answer = CalendarAnswers.answer('Bây giờ là mấy giờ?', now)!;
      expect(answer, startsWith('Bây giờ là 22:05 (giờ địa phương, UTC'));
    });

    test('English', () {
      expect(
        CalendarAnswers.answer('What day is it today?', now),
        'Today is Thursday, 8 October 2026.',
      );
    });
  });

  group('leaves everything else to the model', () {
    for (final q in [
      'Hôm nay là thứ mấy và thời tiết thế nào?',
      'Còn bao nhiêu ngày nữa đến Tết?',
      'Thứ mấy tôi nên đi khám bệnh?',
      'Hôm nay là ngày gì đặc biệt?',
      'Viết một bài thơ về hôm nay',
      'Mai bạn rảnh không',
    ]) {
      test(q, () => expect(CalendarAnswers.answer(q, now), isNull));
    }
  });
}
