import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/chat/domain/arithmetic_answers.dart';

void main() {
  group('answers explicit simple calculations exactly', () {
    final cases = {
      '17 cộng 25 bằng bao nhiêu?': '17 + 25 = 42.',
      '17 + 25 = ?': '17 + 25 = 42.',
      '17+25': '17 + 25 = 42.',
      'Tính giúp tôi 12.000 nhân 3': '12.000 × 3 = 36.000.',
      '12.000 x 3 bằng mấy': '12.000 × 3 = 36.000.',
      '100 chia 8 bằng bao nhiêu': '100 : 8 = 12,5.',
      '1 chia 3': '1 : 3 ≈ 0,3333.',
      '5 trừ 2 cộng 4 bằng mấy?': '5 − 2 + 4 = 7.',
      '2 + 3 × 4': '2 + 3 × 4 = 14.',
      '2,5 nhân 4': '2,5 × 4 = 10.',
      '3 trừ 10': '3 − 10 = −7.',
      '1.000.000 chia cho 4 là bao nhiêu ạ': '1.000.000 : 4 = 250.000.',
      'Xin chào, 17 cộng 25 bằng bao nhiêu': 'Xin chào! 17 + 25 = 42.',
    };
    cases.forEach((q, a) {
      test(q, () => expect(ArithmeticAnswers.answer(q), a));
    });

    test('division by zero', () {
      expect(ArithmeticAnswers.answer('5 chia 0'), 'Không thể chia cho 0.');
    });
  });

  group('leaves everything else to the model', () {
    for (final q in [
      'Một quyển vở giá 12.000 đồng. Mua 3 quyển thì hết bao nhiêu tiền?',
      'An có 5 quả táo, cho Bình 2 quả rồi mua thêm 4 quả.',
      'Năm 2026 có bao nhiêu ngày?',
      '17 cộng 25 và thời tiết hôm nay thế nào?',
      'Hôm nay là thứ mấy?',
      '1.5 + 2',
      '17',
      '17 +',
      '1 + 2 + 3 + 4 + 5',
      'Tôi có 2 con mèo',
      'x + 2 = 5',
      '2 ** 3',
      'print(1+1)',
    ]) {
      test(q, () => expect(ArithmeticAnswers.answer(q), isNull));
    }
  });
}
