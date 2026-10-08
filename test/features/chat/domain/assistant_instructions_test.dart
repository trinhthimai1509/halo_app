import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/chat/domain/assistant_instructions.dart';

void main() {
  test('carries the date, weekday, time and offset of the given clock', () {
    final prompt = AssistantInstructions.systemPrompt(DateTime(2026, 10, 8, 22, 5));
    expect(prompt, contains('Thứ Năm, ngày 8 tháng 10 năm 2026'));
    expect(prompt, contains('22:05'));
    expect(prompt, contains('UTC'));
  });

  test('is computed from the clock, never a fixed date', () {
    final prompt = AssistantInstructions.systemPrompt(DateTime(2027, 2, 14, 7, 30));
    expect(prompt, contains('Chủ Nhật, ngày 14 tháng 2 năm 2027'));
    expect(prompt, isNot(contains('2026')));
  });

  test('states the behaviour rules', () {
    final prompt = AssistantInstructions.systemPrompt(DateTime(2026));
    expect(prompt, contains('ngôn ngữ của người dùng'));
    expect(prompt, contains('Không bịa đặt'));
    expect(prompt, contains('hỏi lại'));
  });
}
