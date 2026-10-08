/// Repeatable LLM benchmark prompt set (Vietnamese + English).
///
/// Each case is a list of user turns sent in order within one conversation;
/// multi-turn cases check that history reaches the model.
class BenchmarkCase {
  const BenchmarkCase(this.id, this.turns);

  final String id;
  final List<String> turns;
}

const List<BenchmarkCase> benchmarkCases = [
  BenchmarkCase('vi_greeting', ['Xin chào. Bạn có thể làm gì?']),
  BenchmarkCase('vi_explain_ai', [
    'Giải thích trí tuệ nhân tạo cho một học sinh 12 tuổi bằng ngôn ngữ đơn giản.',
  ]),
  BenchmarkCase('vi_email', ['Viết một email ngắn xin nghỉ phép ngày mai.']),
  BenchmarkCase('vi_memory', ['Tôi tên là Mai.', 'Tên tôi là gì?']),
  BenchmarkCase('vi_breakfast', ['Hãy đưa ra 5 ý tưởng cho bữa sáng đơn giản.']),
  BenchmarkCase('en_ram_storage', [
    'What is the difference between RAM and storage?',
  ]),
  BenchmarkCase('en_clean_arch', [
    'Explain Clean Architecture in three short paragraphs.',
  ]),
];

/// Long-answer prompt used to test Stop mid-generation.
const String cancellationPrompt =
    'Write a detailed, 20-step guide to learning to cook at home.';
