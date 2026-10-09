import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/chat/presentation/widgets/markdown_lite.dart';

void main() {
  test('the reply from the reported conversation shows no raw markers', () {
    const reply =
        'Đúng rồi. Trong lịch dương, tháng 10 năm 2026 có **31 ngày**.';
    expect(
      MarkdownLite.plain(reply),
      'Đúng rồi. Trong lịch dương, tháng 10 năm 2026 có 31 ngày.',
    );
    final bold = MarkdownLite.spans(reply)
        .whereType<TextSpan>()
        .singleWhere((s) => s.text == '31 ngày');
    expect(bold.style?.fontWeight, FontWeight.w600);
  });

  test('headings, bullets, italic, code and rules', () {
    expect(
      MarkdownLite.plain('## Gợi ý\n- *một*\n* `hai`\n---\nHết'),
      'Gợi ý\n• một\n• hai\nHết',
    );
  });

  test('plain text, arithmetic and unclosed markers stay literal', () {
    for (final text in [
      'Không dùng Markdown.',
      '2 * 3 = 6 và 4 * 5 = 20',
      'Đang viết **31 ng',
      'a__b__c',
      '',
    ]) {
      expect(MarkdownLite.plain(text), text, reason: text);
    }
  });
}
