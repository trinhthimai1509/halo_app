import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/core/utils/relative_date.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/conversation.dart';

void main() {
  group('Conversation.titleFromPrompt', () {
    test('uses the first line with whitespace collapsed', () {
      expect(
        Conversation.titleFromPrompt('  Plan   a trip\nwith details'),
        'Plan a trip',
      );
    });

    test('cuts long prompts at a word boundary', () {
      final title = Conversation.titleFromPrompt(
        'Can you suggest a simple itinerary for a relaxing weekend in the mountains',
      );
      expect(title.length, lessThanOrEqualTo(Conversation.maxTitleLength + 1));
      expect(title, endsWith('…'));
      expect(title, isNot(contains(' …')));
      expect(title, startsWith('Can you suggest a simple itinerary'));
    });
  });

  group('formatRelativeDay', () {
    final now = DateTime(2026, 9, 23, 10); // Wednesday

    test('today, yesterday, weekday, date', () {
      expect(formatRelativeDay(DateTime(2026, 9, 23, 1), now: now), 'Today');
      expect(formatRelativeDay(DateTime(2026, 9, 22, 23), now: now), 'Yesterday');
      expect(formatRelativeDay(DateTime(2026, 9, 18), now: now), 'Friday');
      expect(formatRelativeDay(DateTime(2026, 3, 4), now: now), 'Mar 4');
      expect(formatRelativeDay(DateTime(2025, 3, 4), now: now), 'Mar 4, 2025');
    });
  });
}
