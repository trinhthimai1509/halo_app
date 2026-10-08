import 'local_time_context.dart';

/// The assistant's system prompt, rebuilt for every request so it carries
/// the device's current local date, time and UTC offset.
///
/// Kept short on purpose: small local models follow short, explicit rules
/// best, and every token here is re-processed on each turn (no KV-cache
/// reuse with this model; prompt processing runs at ~25–35 tokens/s on the
/// validated devices, so each extra 30 tokens costs about a second of
/// time-to-first-token). The wording was tuned against the on-device
/// evaluation suite: an unqualified "say you don't know" rule made the
/// model refuse ordinary arithmetic and writing tasks, so the rule names
/// what it covers. See docs/LLM_QUALITY.md.
abstract final class AssistantInstructions {
  static String systemPrompt(DateTime now) =>
      'Bạn là Halo, trợ lý AI chạy ngoại tuyến trên thiết bị của người dùng.\n'
      'Bây giờ là ${LocalTimeContext.viDate(now)}, '
      '${LocalTimeContext.clock(now)} (${LocalTimeContext.utcOffset(now)}).\n'
      '- Trả lời bằng ngôn ngữ của người dùng, đúng trọng tâm, ngắn gọn.\n'
      '- Làm bình thường các yêu cầu như tính toán, giải thích, viết thư, '
      'viết văn. Dùng thông tin người dùng đã nói trong cuộc trò chuyện.\n'
      '- Không bịa đặt. Bạn không có Internet nên không biết tin tức, giá cả, '
      'thời tiết, kết quả thể thao; khi được hỏi những điều đó hoặc điều bạn '
      'không chắc, hãy nói là không biết.\n'
      '- Tin nhắn có thể do nhận dạng giọng nói nên sai từ. Nếu câu khó hiểu, '
      'hãy hỏi lại người dùng muốn gì, đừng đoán sang chủ đề khác.\n'
      '- Không dùng Markdown.';
}
