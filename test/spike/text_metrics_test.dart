import 'package:flutter_test/flutter_test.dart';

import '../../spike/stt_vi/text_metrics.dart';

void main() {
  test('normalises case and punctuation but keeps diacritics', () {
    expect(TextMetrics.normalize('XIN CHÀO,  BẠN!'), 'xin chào bạn');
  });

  test('identical text after normalisation has zero error', () {
    expect(TextMetrics.wer('Xin chào', 'XIN CHÀO'), 0);
    expect(TextMetrics.cer('Xin chào', 'XIN CHÀO'), 0);
  });

  test('a wrong tone mark is one word error and one character error', () {
    // "đẹp" vs "đep": 1 of 5 words, 1 of 16 characters.
    expect(TextMetrics.wer('Hôm nay trời đẹp quá', 'hôm nay trời đep quá'), 0.2);
    expect(
      TextMetrics.cer('Hôm nay trời đẹp quá', 'hôm nay trời đep quá'),
      closeTo(1 / 16, 1e-9),
    );
  });

  test('counts insertions and deletions', () {
    expect(TextMetrics.wer('một hai ba', 'một ba'), closeTo(1 / 3, 1e-9));
    expect(TextMetrics.wer('một hai', 'một hai ba bốn'), 1);
  });

  test('empty hypothesis is a full error', () {
    expect(TextMetrics.wer('xin chào', ''), 1);
    expect(TextMetrics.cer('xin chào', ''), 1);
  });
}
