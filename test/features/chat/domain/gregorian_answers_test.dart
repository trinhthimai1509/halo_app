import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/chat/domain/gregorian_answers.dart';

void main() {
  final now = DateTime(2026, 10, 9, 20, 13);
  String? answer(String message) => GregorianAnswers.answer(message, now);

  group('month length', () {
    test('the questions from the reported conversation', () {
      expect(
        answer('Tháng này có bao nhiêu ngày'),
        'Tháng 10 năm 2026 có 31 ngày (dương lịch).',
      );
      expect(
        answer(
          'Biết là tháng mười mà không biết tháng mười có bao nhiêu ngày à',
        ),
        'Tháng 10 năm 2026 có 31 ngày (dương lịch).',
      );
    });

    test('every month of a common and a leap year', () {
      const common = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
      for (var m = 1; m <= 12; m++) {
        expect(GregorianAnswers.daysInMonth(2026, m), common[m - 1]);
        expect(
          GregorianAnswers.daysInMonth(2028, m),
          m == 2 ? 29 : common[m - 1],
        );
      }
    });

    test('February explains the leap-year rule', () {
      expect(
        answer('Tháng 2 năm 2028 có bao nhiêu ngày?'),
        'Tháng 2 năm 2028 có 29 ngày (dương lịch) vì 2028 là năm nhuận.',
      );
      expect(
        answer('tháng hai có mấy ngày vậy'),
        'Tháng 2 năm 2026 có 28 ngày (dương lịch) vì 2026 không phải năm nhuận.',
      );
      expect(answer('Tháng 2 năm 2100 có bao nhiêu ngày'), contains('28 ngày'));
      expect(answer('Tháng 2 năm 2000 có bao nhiêu ngày'), contains('29 ngày'));
    });

    test('relative months cross year boundaries', () {
      final dec = DateTime(2026, 12, 31);
      expect(
        GregorianAnswers.answer('tháng sau có bao nhiêu ngày', dec),
        'Tháng 1 năm 2027 có 31 ngày (dương lịch).',
      );
      expect(
        GregorianAnswers.answer(
          'Tháng trước có mấy ngày',
          DateTime(2027, 3, 2),
        ),
        'Tháng 2 năm 2027 có 28 ngày (dương lịch) vì 2027 không phải năm nhuận.',
      );
      expect(
        answer('Tháng mười một có bao nhiêu ngày'),
        contains('Tháng 11 năm 2026 có 30 ngày'),
      );
    });
  });

  group('leap months and years', () {
    test('the Gregorian calendar has no leap months', () {
      final reply = answer('Tháng 10 năm 2026 có phải tháng nhuận không?')!;
      expect(
        reply,
        startsWith('Không. Tháng 10 năm 2026 không phải tháng nhuận.'),
      );
      expect(reply, contains('Dương lịch không có tháng nhuận'));
      expect(answer('tháng này là tháng nhuận à'), startsWith('Không.'));
    });

    test('leap years and year length', () {
      expect(
        answer('Năm nay có phải năm nhuận không'),
        'Năm 2026 không phải năm nhuận: tháng 2 có 28 ngày, cả năm có 365 ngày.',
      );
      expect(
        answer('năm 2028 là năm nhuận à'),
        startsWith('Năm 2028 là năm nhuận'),
      );
      expect(
        answer('Năm 1900 có phải năm nhuận không'),
        startsWith('Năm 1900 không phải'),
      );
      expect(
        answer('Năm 2000 có bao nhiêu ngày'),
        startsWith('Năm 2000 có 366 ngày'),
      );
      expect(answer('năm sau có mấy ngày'), startsWith('Năm 2027 có 365 ngày'));
    });
  });

  test('anything else is left to the model', () {
    for (final message in [
      'Tháng này có bao nhiêu ngày nghỉ',
      'Tháng mười làm gì có tháng nhuận với tháng không nhượng trời',
      'Tôi không nói lịch âm',
      'Nay có bao nhiêu ngày',
      'Bạn chắc không?',
      'Sao lúc nãy nói khác?',
      'Tháng 13 có bao nhiêu ngày',
      'Năm 2026 âm lịch có tháng nhuận không',
      'Còn bao nhiêu ngày nữa đến Tết',
    ]) {
      expect(answer(message), isNull, reason: message);
    }
  });
}
