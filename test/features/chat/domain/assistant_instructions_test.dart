import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/chat/domain/assistant_instructions.dart';

void main() {
  test('carries the weekday and date of the given clock', () {
    final prompt = AssistantInstructions.systemPrompt(DateTime(2026, 10, 8, 22, 5));
    expect(prompt, contains('Hôm nay là Thứ Năm, ngày 8 tháng 10 năm 2026.'));
  });

  test('is computed from the clock, never a fixed date', () {
    final prompt = AssistantInstructions.systemPrompt(DateTime(2027, 2, 14, 7, 30));
    expect(prompt, contains('Chủ Nhật, ngày 14 tháng 2 năm 2027'));
    expect(prompt, isNot(contains('2026')));
  });

  test('is identical all day, so the processed prompt can be reused', () {
    expect(
      AssistantInstructions.systemPrompt(DateTime(2026, 10, 8, 0, 1)),
      AssistantInstructions.systemPrompt(DateTime(2026, 10, 8, 23, 59)),
    );
    expect(
      AssistantInstructions.systemPrompt(DateTime(2026, 10, 8, 23, 59)),
      isNot(AssistantInstructions.systemPrompt(DateTime(2026, 10, 9))),
    );
  });

  test('states the behaviour rules', () {
    final prompt = AssistantInstructions.systemPrompt(DateTime(2026));
    expect(prompt, contains('ngôn ngữ của người dùng'));
    expect(prompt, contains('Không bịa đặt'));
    expect(prompt, contains('hỏi lại'));
    expect(prompt, contains('"tôi"'));
    expect(prompt, contains('hãy thừa nhận'));
    expect(prompt, contains('Không nói rằng bạn cần Internet'));
  });
}
