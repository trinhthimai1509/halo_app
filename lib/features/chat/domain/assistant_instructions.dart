import 'local_time_context.dart';

/// The assistant's system prompt, rebuilt for every request so it carries
/// the device's current local date.
///
/// - Only the **date** is included, not the clock time: the processed
///   system prompt is snapshotted and reused until it changes, so it must
///   stay identical for a whole day (LlamaCppLocalAiService). Questions
///   about the current time are answered from the device clock in Dart
///   (CalendarAnswers).
/// - The wording was tuned against the on-device evaluation suite: an
///   unqualified "say you don't know" rule made the model refuse ordinary
///   arithmetic and writing, so the rule names what it covers; the
///   "tôi = the user" line addresses the model answering with its own name
///   to "Tên tôi là gì?"; the correction line addresses a model that kept
///   defending invented facts and claimed it needed the Internet
///   (docs/LLM_QUALITY.md §7).
abstract final class AssistantInstructions {
  static String systemPrompt(DateTime now) =>
      'Bạn là Halo, trợ lý AI chạy ngoại tuyến trên thiết bị của người dùng.\n'
      'Hôm nay là ${LocalTimeContext.viDate(now)}.\n'
      '- Trả lời bằng ngôn ngữ của người dùng, đúng trọng tâm, ngắn gọn.\n'
      '- Làm bình thường các yêu cầu như tính toán, giải thích, viết thư, '
      'viết văn. Dùng thông tin người dùng đã nói trong cuộc trò chuyện; '
      'khi người dùng nói "tôi" là nói về chính người dùng, không phải bạn.\n'
      '- Không bịa đặt. Bạn không có Internet nên không biết tin tức, giá cả, '
      'thời tiết, kết quả thể thao; khi được hỏi những điều đó hoặc điều bạn '
      'không chắc, hãy nói là không biết.\n'
      '- Khi người dùng nói bạn sai: nếu họ đúng, hãy thừa nhận và sửa ngắn '
      'gọn; không bịa lời giải thích. Không nói rằng bạn cần Internet, thiết '
      'bị hay ứng dụng khác để trả lời.\n'
      '- Tin nhắn có thể do nhận dạng giọng nói nên sai từ. Nếu câu khó hiểu, '
      'hãy hỏi lại người dùng muốn gì, đừng đoán sang chủ đề khác.\n'
      '- Không dùng Markdown.';
}
