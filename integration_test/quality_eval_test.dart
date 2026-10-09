// LLM answer-quality acceptance suite (real model, real device).
//
//   flutter test integration_test/quality_eval_test.dart -d <serial> --no-uninstall
//     [--dart-define=QE_BEFORE=all|K|none]   (default: none)
//     [--dart-define=QE_PARTS=after,consistency,recovery,seeds,calendar,ff857ff]
//       (default: after,consistency,recovery)
//
// 1. Prints the exact prompt llama.cpp receives (chat template rendered by
//    the GGUF's own Jinja template, thinking disabled), before and after.
// 2. `before`: the pre-fix pipeline, reproduced exactly: fixed English
//    system prompt without a date, sampling temp 1.0 / top_p 1.0 /
//    presence 2.0, no calendar shortcut.
// 3. `after`: the production pipeline (SendMessage → calendar shortcut or
//    AssistantInstructions + LlmModelConfig.qwen35_2b), seed fixed.
// Results: one JSON file per run in <external files>/qe/ and `[QE]` lines.
// Grading is automatic per case and reviewed by hand (docs/LLM_QUALITY.md).
//
// Expected dates are computed here independently of the app's own
// calendar code, so the suite does not grade the app against itself.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:offline_ai_chat/core/utils/id_generator.dart';
import 'package:offline_ai_chat/features/chat/domain/arithmetic_answers.dart';
import 'package:offline_ai_chat/features/chat/domain/assistant_instructions.dart';
import 'package:offline_ai_chat/features/chat/domain/calendar_answers.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/chat_message.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/conversation.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/message_role.dart';
import 'package:offline_ai_chat/features/chat/domain/local_time_context.dart';
import 'package:offline_ai_chat/features/chat/domain/usecases/send_message.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/llama_cpp_local_ai_service.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/llm_model_config.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/model_file_locator.dart';
import 'package:offline_ai_chat/features/local_ai/domain/local_ai_service.dart';
import 'package:path_provider/path_provider.dart';

import '../test/helpers/in_memory_chat_repository.dart';

// ---------------------------------------------------------------- dates --

const _viWeekdays = [
  'Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật',
];

String _two(int n) => n.toString().padLeft(2, '0');

String _utcOffset(DateTime t) {
  final o = t.timeZoneOffset;
  final sign = o.isNegative ? '-' : '+';
  final m = o.inMinutes.abs();
  return 'UTC$sign${_two(m ~/ 60)}:${_two(m % 60)}';
}

/// The 366ae73 system prompt (verbatim): date plus clock time, so it
/// changed every minute. Baseline for the performance work.
String baselineSystemPrompt(DateTime now) =>
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

/// The system prompt shipped before the quality fix (verbatim).
const String legacySystemPrompt =
    'You are a helpful assistant. Respond in the same language as the user.';

/// The ff857ff system prompt (verbatim): no correction rule. Baseline for
/// the calendar-hallucination fix, used with ff857ff's Dart answers
/// (calendar and arithmetic, no Gregorian facts).
String ff857ffSystemPrompt(DateTime now) =>
    'Bạn là Halo, trợ lý AI chạy ngoại tuyến trên thiết bị của người dùng.\n'
    'Hôm nay là ${LocalTimeContext.viDate(now)}.\n'
    '- Trả lời bằng ngôn ngữ của người dùng, đúng trọng tâm, ngắn gọn.\n'
    '- Làm bình thường các yêu cầu như tính toán, giải thích, viết thư, '
    'viết văn. Dùng thông tin người dùng đã nói trong cuộc trò chuyện; '
    'khi người dùng nói "tôi" là nói về chính người dùng, không phải bạn.\n'
    '- Không bịa đặt. Bạn không có Internet nên không biết tin tức, giá cả, '
    'thời tiết, kết quả thể thao; khi được hỏi những điều đó hoặc điều bạn '
    'không chắc, hãy nói là không biết.\n'
    '- Tin nhắn có thể do nhận dạng giọng nói nên sai từ. Nếu câu khó hiểu, '
    'hãy hỏi lại người dùng muốn gì, đừng đoán sang chủ đề khác.\n'
    '- Không dùng Markdown.';

/// ff857ff's SendMessage, reproduced: its Dart answers, else its prompt.
Future<void> _ff857ffGenerate(
  LocalAiService ai,
  List<AiMessage> history,
  String input,
  DateTime now,
  void Function(String delta) onDelta,
) async {
  final dart =
      CalendarAnswers.answer(input, now) ?? ArithmeticAnswers.answer(input);
  if (dart != null) return onDelta(dart);
  await ai
      .generate(GenerationRequest(messages: [
        AiMessage(role: AiRole.system, content: ff857ffSystemPrompt(now)),
        ...history,
        _u(input),
      ]))
      .forEach(onDelta);
}

// ------------------------------------------------- calendar regression --

/// The device conversation of 2026-10-09 20:13 that exposed the
/// hallucinations, followed by the challenges a user makes next.
const calendarConversation = [
  'Xin chào hôm nay là thứ mấy',
  'Tháng này có bao nhiêu ngày',
  'Biết là tháng mười mà không biết tháng mười có bao nhiêu ngày à',
  'Tháng mười làm gì có tháng nhuận với tháng không nhượng trời',
  'Tôi không nói lịch âm',
  'Bạn chắc không?',
  'Sao lúc nãy nói khác?',
];
final calendarClock = DateTime(2026, 10, 9, 20, 13);

/// Automatic flags for one reply (reviewed by hand). Null = no flag.
String? calendarCheck(String out) {
  final t = _norm(out);
  if (t.trim().isEmpty) return 'empty';
  if (RegExp('internet|kết nối mạng|tra cứu|truy cập').hasMatch(t)) {
    return 'claims-internet';
  }
  if (RegExp('(là|có) (một )?tháng nhuận').hasMatch(t) &&
      !RegExp('không (có |phải )?(là )?(một )?tháng nhuận').hasMatch(t)) {
    return 'leap-month';
  }
  if (RegExp(r'tháng (10|mười)[^.]*\b(30|29|28) ngày').hasMatch(t)) {
    return 'wrong-days';
  }
  if (RegExp(r'\*\*|^#{1,6} ', multiLine: true).hasMatch(out)) {
    return 'markdown';
  }
  return null;
}

// ---------------------------------------------------------------- cases --

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
bool _has(String out, List<String> any) =>
    any.any((w) => _norm(out).contains(_norm(w)));
final _cjk = RegExp(r'[぀-ヿ㐀-鿿가-힯]');
final _vietnameseMarks = RegExp(
  r'[ăâđêôơưàáảãạằắẳẵặầấẩẫậèéẻẽẹềếểễệìíỉĩịòóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ]',
  caseSensitive: false,
);
final _declines = [
  'không biết', 'không có thông tin', 'không thể', 'không có quyền truy cập',
  'không có khả năng', 'không được cập nhật', 'không có dữ liệu',
  'chưa có thông tin', 'không nắm được', 'không rõ', 'không truy cập',
  'thời gian thực', 'kiểm tra', 'tra cứu',
];
final _clarifies = [
  'rõ', 'ý bạn', 'bạn muốn', 'nói lại', 'cụ thể', 'giải thích thêm',
  'có phải bạn', 'chưa hiểu', 'không hiểu', 'thêm thông tin',
  'bạn có thể cho', 'bạn cần', '?',
];

class Case {
  Case(this.id, this.category, this.input, this.expected, this.check,
      {this.history = const [], this.maxTokens = 192});

  final String id;
  final String category;
  final String input;
  final String expected;
  final List<AiMessage> history;
  final int maxTokens;

  /// Returns null on PASS, else the error category.
  final String? Function(String out) check;
}

AiMessage _u(String t) => AiMessage(role: AiRole.user, content: t);
AiMessage _a(String t) => AiMessage(role: AiRole.assistant, content: t);

/// Language gate applied to every Vietnamese-answer case.
String? _vietnamese(String out) {
  if (out.trim().isEmpty) return 'empty';
  if (_cjk.hasMatch(out)) return 'language-mixing';
  if (!_vietnameseMarks.hasMatch(out)) return 'wrong-language';
  return null;
}

String? Function(String) _vi(String? Function(String) inner) =>
    (out) => _vietnamese(out) ?? inner(out);

/// Ambiguous input: PASS when the reply asks for clarification and stays
/// short instead of inventing a topic.
String? _clarification(String out) {
  if (_has(out, ['ransomware', 'filevault', 'lockscreen', 'secure boot'])) {
    return 'invented-topic';
  }
  if (!_has(out, _clarifies)) return 'no-clarification';
  if (out.length > 700) return 'over-long guess';
  return null;
}

const _filler =
    'Phở là món ăn truyền thống nổi tiếng của Việt Nam, gồm bánh phở, nước '
    'dùng hầm từ xương bò hoặc gà trong nhiều giờ, thêm thịt, hành lá, rau '
    'thơm và gia vị như quế, hồi, gừng nướng. Mỗi vùng miền có cách nấu riêng: '
    'phở Hà Nội thường thanh, ít rau; phở miền Nam ăn kèm giá, húng quế và '
    'tương. Người Việt ăn phở vào bữa sáng nhưng cũng có thể ăn bất cứ lúc '
    'nào trong ngày. Khi nấu tại nhà, nên chần xương để nước dùng trong, hớt '
    'bọt thường xuyên và nêm nếm vừa phải để giữ vị ngọt tự nhiên.';

List<AiMessage> _longHistory(int turns, {bool withFact = true}) => [
      if (withFact) ...[
        _u('Mã đơn hàng của tôi là HX-4821, bạn ghi nhớ giúp tôi nhé.'),
        _a('Vâng, mình đã ghi nhớ: mã đơn hàng của bạn là HX-4821.'),
      ],
      for (var i = 1; i <= turns; i++) ...[
        _u('Kể cho tôi thêm về món ăn Việt Nam, phần $i.'),
        _a('Phần $i. $_filler'),
      ],
    ];

List<Case> buildCases(DateTime now) {
  final today = _viWeekdays[now.weekday - 1];
  final tomorrowDate = DateTime(now.year, now.month, now.day + 1);
  final tomorrow = _viWeekdays[tomorrowDate.weekday - 1];
  List<String> weekdayForms(String w) => [
        w,
        w
            .replaceAll('Năm', '5')
            .replaceAll('Sáu', '6')
            .replaceAll('Tư', '4')
            .replaceAll('Ba', '3')
            .replaceAll('Hai', '2')
            .replaceAll('Bảy', '7'),
      ];
  String? date(String out, List<String> correct) {
    if (_has(out, correct)) return null;
    if (_has(out, _declines)) return 'missing-context (declined)';
    return 'hallucination (wrong date)';
  }

  return [
    // A. Current date and weekday.
    Case('A1', 'A', 'Hôm nay là thứ mấy?', today,
        _vi((o) => date(o, weekdayForms(today)))),
    Case('A2', 'A', 'Hôm nay là ngày bao nhiêu, tháng mấy, năm nào?',
        '${now.day}/${now.month}/${now.year}',
        _vi((o) => date(o, [
              'ngày ${now.day} tháng ${now.month} năm ${now.year}',
              '${now.day}/${now.month}/${now.year}',
              '${_two(now.day)}/${_two(now.month)}/${now.year}',
            ]))),
    Case('A3', 'A', 'Ngày mai là thứ mấy?', tomorrow,
        _vi((o) => date(o, weekdayForms(tomorrow)))),
    // B. Basic conversation.
    Case('B1', 'B', 'Xin chào, bạn là ai?', 'Vietnamese greeting, introduces itself as an assistant',
        _vi((o) => _has(o, ['trợ lý', 'halo', 'hỗ trợ', 'giúp']) ? null : 'off-topic')),
    Case('B2', 'B', 'Cảm ơn bạn nhiều nhé!', 'Short polite Vietnamese reply',
        _vi((o) => o.length < 400 ? null : 'too-verbose')),
    Case('B3', 'B', 'Bạn có nói được tiếng Việt không?', 'Yes, answered in Vietnamese',
        _vi((o) => _has(o, ['có', 'được']) ? null : 'off-topic')),
    // C. General facts.
    Case('C1', 'C', 'Thủ đô của Việt Nam là thành phố nào?', 'Hà Nội',
        _vi((o) => _has(o, ['hà nội']) ? null : 'factual-error')),
    Case('C2', 'C', 'Nước sôi ở bao nhiêu độ C ở áp suất khí quyển tiêu chuẩn?', '100 °C',
        _vi((o) => _has(o, ['100']) ? null : 'factual-error')),
    Case('C3', 'C', 'Việt Nam có bao nhiêu tỉnh thành sau khi sáp nhập năm 2025?', '34 (post-2025 merger)',
        _vi((o) => _has(o, ['34']) ? null : 'factual-error (knowledge)')),
    // D. Arithmetic and reasoning.
    Case('D1', 'D', '17 cộng 25 bằng bao nhiêu?', '42',
        (o) => _has(o, ['42']) ? null : 'arithmetic-error'),
    Case('D2', 'D', 'Một quyển vở giá 12.000 đồng. Mua 3 quyển thì hết bao nhiêu tiền?', '36.000 đồng',
        _vi((o) => _has(o, ['36.000', '36000', '36 000', '36 nghìn', 'ba mươi sáu nghìn']) ? null : 'arithmetic-error')),
    Case('D3', 'D', 'An có 5 quả táo, cho Bình 2 quả rồi mua thêm 4 quả. Hỏi An còn bao nhiêu quả táo?', '7',
        _vi((o) => RegExp(r'\b7\b|bảy quả').hasMatch(_norm(o)) ? null : 'reasoning-error')),
    // E. Explicit instructions.
    Case('E1', 'E', 'Liệt kê đúng 3 loại trái cây, mỗi loại một dòng, không giải thích gì thêm.', 'Exactly 3 lines',
        (o) {
          final lines = o.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
          return lines.length == 3 ? null : 'instruction-violation (${lines.length} lines)';
        }),
    Case('E2', 'E', 'Chỉ trả lời "có" hoặc "không": Hà Nội có phải là thủ đô của Việt Nam không?', '"Có" only',
        (o) {
          final t = _norm(o).replaceAll(RegExp(r'[^\p{L}\s]', unicode: true), '').trim();
          return t == 'có' ? null : 'instruction-violation';
        }),
    Case('E3', 'E', 'Hãy trả lời bằng tiếng Anh: "Xin chào" nghĩa là gì?', 'English answer containing "hello"',
        (o) => _has(o, ['hello']) && !_cjk.hasMatch(o) ? null : 'instruction-violation'),
    // F. Short Vietnamese writing.
    Case('F1', 'F', 'Viết một câu chúc mừng sinh nhật ngắn gọn dành cho mẹ.', 'One short birthday wish',
        _vi((o) => _has(o, ['sinh nhật', 'mẹ']) && o.length < 600 ? null : 'off-topic/too-long'),
        maxTokens: 160),
    Case('F2', 'F', 'Viết một email ngắn gửi quản lý để xin nghỉ phép một ngày vì bị ốm.', 'Short leave-request email',
        _vi((o) => _has(o, ['nghỉ']) && _has(o, ['kính gửi', 'chào', 'thưa']) ? null : 'off-topic'),
        maxTokens: 256),
    Case('F3', 'F', 'Tóm tắt trong một câu: "Hôm nay trời mưa to nên tôi ở nhà đọc sách và nấu canh chua cho cả gia đình."', 'One-sentence summary',
        _vi((o) {
          final sentences = o.trim().split(RegExp(r'[.!?]+\s')).where((s) => s.trim().isNotEmpty).length;
          return sentences <= 2 && _has(o, ['mưa']) ? null : 'instruction-violation';
        })),
    // G. Multi-turn consistency (scripted history).
    Case('G1', 'G', 'Tên tôi là gì?', 'Minh',
        _vi((o) => _has(o, ['minh']) ? null : 'context-loss'),
        history: [_u('Tên tôi là Minh.'), _a('Chào Minh! Rất vui được làm quen với bạn.')]),
    Case('G2', 'G', 'Vậy tôi nuôi tổng cộng bao nhiêu con vật?', '3',
        _vi((o) => RegExp(r'\b3\b|ba con').hasMatch(_norm(o)) ? null : 'context-loss/reasoning'),
        history: [_u('Nhà tôi nuôi 2 con mèo và 1 con chó.'), _a('Thật tuyệt! Mèo và chó đều là những người bạn đáng yêu.')]),
    Case('G3', 'G', 'Bạn đang gọi tôi là gì?', 'anh Tuấn',
        _vi((o) => _has(o, ['tuấn']) ? null : 'context-loss'),
        history: [
          _u('Từ giờ hãy gọi tôi là anh Tuấn nhé.'), _a('Vâng, em sẽ gọi anh là anh Tuấn ạ.'),
          _u('Hôm nay trời đẹp quá.'), _a('Dạ, trời đẹp thế này đi dạo thì thích lắm anh Tuấn ạ.'),
        ]),
    // H. Unknown information / hallucination.
    Case('H1', 'H', 'Giá vàng SJC hôm nay là bao nhiêu một lượng?', 'Says it has no live data',
        _vi((o) => _has(o, _declines) ? null : 'hallucination')),
    Case('H2', 'H', 'Tối qua trận bóng đá Việt Nam gặp Thái Lan kết thúc với tỉ số bao nhiêu?', 'Says it has no live data',
        _vi((o) => _has(o, _declines) ? null : 'hallucination')),
    Case('H3', 'H', 'Ai là tác giả cuốn tiểu thuyết "Những ngọn đèn trên đồi Mây Xanh" xuất bản năm 2019?', 'Fictional book: says it does not know',
        _vi((o) => _has(o, _declines) ? null : 'hallucination')),
    // I. Real STT transcripts (formatted exactly as the app inserts them).
    Case('I1', 'I', 'Xin chào hôm nay là thứ mấy', today,
        _vi((o) => date(o, weekdayForms(today)))),
    Case('I2', 'I', 'Giải thích cho tôi trí tuệ nhân tạo là gì bằng ngôn ngữ đơn giản', 'Simple Vietnamese explanation of AI',
        _vi((o) => _has(o, ['máy tính', 'máy', 'học', 'con người']) ? null : 'off-topic'),
        maxTokens: 256),
    Case('I3', 'I', 'Tôi muốn nấu một bữa sáng nhanh và lành mạnh cho gia đình bốn người bạn gợi ý giúp tôi một vài món được không', 'A few breakfast suggestions in Vietnamese',
        _vi((o) => _has(o, ['bánh', 'cháo', 'trứng', 'xôi', 'phở', 'yến mạch', 'sữa']) ? null : 'off-topic'),
        maxTokens: 256),
    // J. Long history.
    Case('J1', 'J', 'Mã đơn hàng của tôi là gì?', 'HX-4821 (fact still inside the window)',
        _vi((o) => _has(o, ['hx-4821', 'hx4821', 'hx 4821']) ? null : 'context-loss'),
        history: _longHistory(6)),
    Case('J2', 'J', 'Mã đơn hàng của tôi là gì?', 'Fact trimmed by the context policy: should say it does not know',
        _vi((o) {
          if (_has(o, ['hx-4821'])) return null; // still in window: acceptable
          if (RegExp(r'[a-z]{1,3}-?\d{3,}', caseSensitive: false).hasMatch(o)) return 'hallucination (invented code)';
          return _has(o, _declines) ? null : 'unclear';
        }),
        history: _longHistory(16)),
    Case('J3', 'J', '17 cộng 25 bằng bao nhiêu?', '42 with a long unrelated history',
        (o) => _has(o, ['42']) ? null : 'context-contamination',
        history: _longHistory(12, withFact: false)),
    // K. Ambiguous / corrupted input (K1 is the real tablet transcript).
    Case('K1', 'K', 'Sau khi hoàn thành tắt e mốt và gửi đăng cho clo để nó đọc lớp usb đối chiếu kết quả',
        'Ask what the user means; no invented topic', _vi(_clarification),
        maxTokens: 256),
    Case('K2', 'K', 'Ừ cái đó thì sao', 'Ask what "cái đó" refers to',
        _vi(_clarification)),
    Case('K3', 'K', 'Bật cái lớp cho tôi với', 'Ask what "lớp" means (likely misrecognised)',
        _vi(_clarification)),
  ];
}

// --------------------------------------------------------------- runner --

const int _seed = 42;

/// Sampling used before the fix (model card "non-thinking, text").
LlmModelConfig get _legacyConfig => LlmModelConfig(
      displayName: LlmModelConfig.qwen35_2b.displayName,
      fileName: LlmModelConfig.qwen35_2b.fileName,
      quantization: LlmModelConfig.qwen35_2b.quantization,
      contextSize: LlmModelConfig.qwen35_2b.contextSize,
      maxNewTokens: LlmModelConfig.qwen35_2b.maxNewTokens,
      temperature: 1.0,
      topK: 20,
      topP: 1.0,
      minP: 0.0,
      presencePenalty: 2.0,
      seed: _seed,
    );

final List<String> _captured = [];

Map<String, String> _metricsSince(int index) {
  final line = _captured
      .skip(index)
      .lastWhere((l) => l.contains('[LLM] generation_'), orElse: () => '');
  return {
    for (final m in RegExp(r'(\w+)=(\S+)').allMatches(line)) m[1]!: m[2]!,
  };
}

Future<Map<String, Object?>> _record(
  Case c,
  Future<void> Function(void Function(String delta) onDelta) generate,
) async {
  final before = _captured.length;
  final text = StringBuffer();
  final clock = Stopwatch()..start();
  int? ttft;
  var status = 'ok';
  try {
    await generate((d) {
      ttft ??= clock.elapsedMilliseconds;
      text.write(d);
    }).timeout(const Duration(seconds: 240));
  } catch (e) {
    status = 'error: $e';
  }
  // The service logs `generation_*` asynchronously after the stream
  // closes; wait for that specific line (other lines, e.g. a lazy
  // `model_loaded`, must not end the wait). A calendar answer never
  // reaches the model and logs nothing.
  bool logged() =>
      _captured.skip(before).any((l) => l.contains('[LLM] generation_'));
  for (var i = 0; i < 40 && !logged(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final m = _metricsSince(before);
  final out = text.toString();
  final error = status == 'ok' ? c.check(out) : 'runtime-error';
  return {
    'id': c.id,
    'category': c.category,
    'input': c.input,
    'history_turns': c.history.length,
    'expected': c.expected,
    'output': out,
    'verdict': error == null ? 'PASS' : 'FAIL',
    'error': error,
    'status': status,
    'answered_by': m.isEmpty ? 'dart (no model call)' : 'model',
    'ttft_ms': ttft,
    'total_ms': clock.elapsedMilliseconds,
    'tok_s': m['tok_s'],
    'gen_tokens': m['gen_tokens'],
    'prompt_tokens': m['prompt_tokens'],
    'prompt_msgs': m['prompt_msgs'],
    'markdown': RegExp(r'\*\*|^#{1,6} ', multiLine: true).hasMatch(out),
  };
}

/// Pre-fix pipeline: legacy prompt straight into the service.
Future<Map<String, Object?>> _before(LocalAiService ai, Case c) =>
    _record(c, (onDelta) => ai
        .generate(GenerationRequest(
          messages: [
            const AiMessage(role: AiRole.system, content: legacySystemPrompt),
            ...c.history,
            _u(c.input),
          ],
          maxTokens: c.maxTokens,
        ))
        .forEach(onDelta));

/// Production pipeline: exactly what the chat screen calls. (Production
/// requests carry no per-call token cap; `maxNewTokens` applies.)
Future<Map<String, Object?>> _after(SendMessage send, Case c) {
  var n = 0;
  final history = [
    for (final m in c.history)
      ChatMessage(
        id: 'h${n++}',
        conversationId: 'qe',
        role: m.role == AiRole.user ? MessageRole.user : MessageRole.assistant,
        content: m.content,
        createdAt: DateTime.now(),
      ),
  ];
  return _record(c, (onDelta) async {
    await for (final event in send(text: c.input, history: history)) {
      if (event is ReplyChunk) onDelta(event.delta);
    }
  });
}

Future<void> _save(String name, Object data) async {
  final dir = Directory('${(await getExternalStorageDirectory())!.path}/qe');
  await dir.create(recursive: true);
  await File('${dir.path}/$name.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}

void _print(String run, Map<String, Object?> r) {
  // ignore: avoid_print
  print('[QE] $run ${r['id']} ${r['verdict']} by=${r['answered_by']} '
      'ttft=${r['ttft_ms']} tok_s=${r['tok_s']} '
      'prompt_tokens=${r['prompt_tokens']} err=${r['error']}');
}

const String _beforeScope =
    String.fromEnvironment('QE_BEFORE', defaultValue: 'none');

/// Which of the later parts to run: after, consistency, recovery.
const String _parts = String.fromEnvironment(
  'QE_PARTS',
  defaultValue: 'after,consistency,recovery',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final original = debugPrint;
  setUpAll(() {
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) _captured.add(message);
      original(message, wrapWidth: wrapWidth);
    };
  });
  tearDownAll(() => debugPrint = original);

  testWidgets('1. exact prompt sent to llama.cpp', (tester) async {
    await tester.runAsync(() async {
      final path = await const ModelFileLocator()
          .find(LlmModelConfig.qwen35_2b.fileName);
      expect(path, isNotNull, reason: 'model not installed');
      final engine = LlamaEngine(LlamaBackend());
      // Default ModelParams: n_ctx 4096, as in production.
      await engine.loadModel(path!);
      try {
        Future<Map<String, Object?>> render(String system, String user) async {
          final r = await engine.chatTemplate([
            LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: user),
          ], enableThinking: false);
          return {
            'prompt': r.prompt,
            'tokens': await engine.getTokenCount(r.prompt),
            'thinking_forced_open': r.thinkingForcedOpen,
          };
        }

        final now = DateTime.now();
        final report = {
          'before': await render(legacySystemPrompt, 'Hôm nay trời đẹp quá'),
          'after': await render(
            AssistantInstructions.systemPrompt(now),
            'Hôm nay trời đẹp quá',
          ),
          'device_now': now.toIso8601String(),
          'device_tz': '${now.timeZoneName} ${_utcOffset(now)}',
        };
        await _save('prompt_inspection_v2', report);
        // ignore: avoid_print
        print('[QE] PROMPT ${jsonEncode(report)}');
      } finally {
        await engine.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('2. before (pre-fix pipeline)', (tester) async {
    await tester.runAsync(() async {
      final cases = buildCases(DateTime.now())
          .where((c) => _beforeScope == 'all' || c.category == _beforeScope)
          .toList();
      final ai = LlamaCppLocalAiService(config: _legacyConfig);
      await ai.initialize();
      final results = <Map<String, Object?>>[];
      try {
        for (final c in cases) {
          final r = await _before(ai, c);
          results.add(r);
          _print('before', r);
        }
      } finally {
        await _save('before_$_beforeScope', results);
        await ai.dispose();
      }
    });
  },
      skip: _beforeScope == 'none',
      timeout: const Timeout(Duration(minutes: 20)));

  testWidgets('3. after (production pipeline)', (tester) async {
    await tester.runAsync(() async {
      final ai = LlamaCppLocalAiService(
        config: LlmModelConfig.qwen35_2b.copyWith(seed: _seed),
      );
      final send = SendMessage(
        repository: InMemoryChatRepository(),
        ai: ai,
        ids: IdGenerator(),
        clock: DateTime.now,
      );
      final results = <Map<String, Object?>>[];
      try {
        for (final c in buildCases(DateTime.now())) {
          final r = await _after(send, c);
          results.add(r);
          _print('after', r);
        }
      } finally {
        await _save('after', results);
        await ai.dispose();
      }
    });
  }, skip: !_parts.contains('after'),
      timeout: const Timeout(Duration(minutes: 75)));

  // ------------------------------------------------------------------
  // 4. Run-to-run consistency: the same model-answered cases with three
  //    seeds, under the 366ae73 baseline and the production candidate.
  // ------------------------------------------------------------------
  testWidgets('4. consistency (3 seeds, baseline vs candidate)', (tester) async {
    await tester.runAsync(() async {
      final ids = {'D1', 'D2', 'G1', 'G2', 'K1', 'K3'};
      final cases =
          buildCases(DateTime.now()).where((c) => ids.contains(c.id)).toList();
      final results = <Map<String, Object?>>[];
      for (final seed in [1, 2, 3]) {
        // Baseline (366ae73): dated prompt with clock time, 2 prompt
        // threads, 3008-token budget, no snapshot, no arithmetic handler.
        final base = LlamaCppLocalAiService(
          config: LlmModelConfig.qwen35_2b.copyWith(
            batchThreads: 2,
            maxPromptTokens: 100000,
            systemPromptSnapshot: false,
            seed: seed,
          ),
        );
        await base.initialize();
        try {
          for (final c in cases) {
            final r = await _record(
              c,
              (onDelta) => base
                  .generate(GenerationRequest(messages: [
                    AiMessage(
                      role: AiRole.system,
                      content: baselineSystemPrompt(DateTime.now()),
                    ),
                    ...c.history,
                    _u(c.input),
                  ]))
                  .forEach(onDelta),
            );
            results.add({'pipeline': 'baseline', 'seed': seed, ...r});
            _print('consistency baseline seed=$seed', r);
          }
        } finally {
          await base.dispose();
        }

        final ai = LlamaCppLocalAiService(
          config: LlmModelConfig.qwen35_2b.copyWith(seed: seed),
        );
        final send = SendMessage(
          repository: InMemoryChatRepository(),
          ai: ai,
          ids: IdGenerator(),
          clock: DateTime.now,
        );
        try {
          for (final c in cases) {
            final r = await _after(send, c);
            results.add({'pipeline': 'candidate', 'seed': seed, ...r});
            _print('consistency candidate seed=$seed', r);
          }
        } finally {
          await ai.dispose();
        }
      }
      await _save('consistency', results);
    });
  }, skip: !_parts.contains('consistency'),
      timeout: const Timeout(Duration(minutes: 40)));

  // ------------------------------------------------------------------
  // 5. Stop / recovery with the snapshot: cancel mid-reply, ask again
  //    immediately (must work, without the snapshot), then once more
  //    (snapshot back in use). Metrics lines carry `snapshot=`.
  // ------------------------------------------------------------------
  testWidgets('5. stop and recovery', (tester) async {
    await tester.runAsync(() async {
      final ai = LlamaCppLocalAiService(
        config: LlmModelConfig.qwen35_2b.copyWith(seed: _seed),
      );
      await ai.initialize();
      final steps = <Map<String, Object?>>[];
      GenerationRequest ask(String q) => GenerationRequest(messages: [
            AiMessage(
              role: AiRole.system,
              content: AssistantInstructions.systemPrompt(DateTime.now()),
            ),
            _u(q),
          ]);
      Future<Map<String, Object?>> step(String name, String q,
          {int? stopAfterChunks}) async {
        final before = _captured.length;
        final text = StringBuffer();
        final clock = Stopwatch()..start();
        int? ttft;
        var chunks = 0;
        var status = 'ok';
        final done = Completer<void>();
        late final StreamSubscription<String> sub;
        sub = ai.generate(ask(q)).listen(
          (d) {
            ttft ??= clock.elapsedMilliseconds;
            text.write(d);
            chunks++;
            if (stopAfterChunks != null && chunks >= stopAfterChunks) {
              sub.cancel().whenComplete(() {
                status = 'stopped';
                if (!done.isCompleted) done.complete();
              });
            }
          },
          onError: (Object e) {
            status = 'error: $e';
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );
        await done.future.timeout(const Duration(seconds: 120));
        for (var i = 0; i < 30; i++) {
          if (_captured.skip(before).any((l) => l.contains('[LLM] generation_'))) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final line = _captured.skip(before).lastWhere(
            (l) => l.contains('[LLM] generation_'), orElse: () => '');
        final r = {
          'step': name,
          'status': status,
          'ttft_ms': ttft,
          'output': text.toString(),
          'metrics': line,
        };
        // ignore: avoid_print
        print('[QE] recovery $name status=$status ttft=$ttft '
            'snapshot=${RegExp(r'snapshot=(\w+)').firstMatch(line)?.group(1)}');
        return r;
      }

      try {
        steps
          ..add(await step('warm', 'Xin chào, bạn là ai?'))
          ..add(await step('long_then_stop', 'Viết một bài văn dài về mùa thu Hà Nội.', stopAfterChunks: 5))
          ..add(await step('right_after_stop', 'Thủ đô của Việt Nam là thành phố nào?'))
          ..add(await step('next', 'Viết một câu chúc mừng sinh nhật ngắn gọn dành cho mẹ.'))
          ..add(await step('stop_again', 'Kể chi tiết về lịch sử Việt Nam.', stopAfterChunks: 3))
          ..add(await step('after_second_stop', 'Nước sôi ở bao nhiêu độ C?'));
      } finally {
        await _save('recovery', steps);
        await ai.dispose();
      }
    });
  }, skip: !_parts.contains('recovery'),
      timeout: const Timeout(Duration(minutes: 10)));

  // ------------------------------------------------------------------
  // 6. Full suite on extra seeds for both pipelines (quality variance).
  //    Baseline = 366ae73 logic: calendar shortcut, then the model with the
  //    dated+timed prompt, no arithmetic handler, 3008-token budget. It
  //    runs with 4 prompt threads only to save time (speed setting).
  // ------------------------------------------------------------------
  testWidgets('6. full suite on extra seeds', (tester) async {
    await tester.runAsync(() async {
      final results = <Map<String, Object?>>[];
      for (final seed in [1, 2]) {
        final base = LlamaCppLocalAiService(
          config: LlmModelConfig.qwen35_2b.copyWith(
            maxPromptTokens: 100000,
            systemPromptSnapshot: false,
            seed: seed,
          ),
        );
        await base.initialize();
        try {
          for (final c in buildCases(DateTime.now())) {
            final calendar = CalendarAnswers.answer(c.input, DateTime.now());
            final r = await _record(c, (onDelta) async {
              if (calendar != null) return onDelta(calendar);
              await base
                  .generate(GenerationRequest(messages: [
                    AiMessage(
                      role: AiRole.system,
                      content: baselineSystemPrompt(DateTime.now()),
                    ),
                    ...c.history,
                    _u(c.input),
                  ]))
                  .forEach(onDelta);
            });
            results.add({'pipeline': 'baseline', 'seed': seed, ...r});
            _print('seeds baseline seed=$seed', r);
          }
        } finally {
          await base.dispose();
        }

        final ai = LlamaCppLocalAiService(
          config: LlmModelConfig.qwen35_2b.copyWith(seed: seed),
        );
        final send = SendMessage(
          repository: InMemoryChatRepository(),
          ai: ai,
          ids: IdGenerator(),
          clock: DateTime.now,
        );
        try {
          for (final c in buildCases(DateTime.now())) {
            final r = await _after(send, c);
            results.add({'pipeline': 'candidate', 'seed': seed, ...r});
            _print('seeds candidate seed=$seed', r);
          }
        } finally {
          await ai.dispose();
        }
      }
      await _save('seeds', results);
    });
  }, skip: !_parts.contains('seeds'),
      timeout: const Timeout(Duration(minutes: 60)));

  // ------------------------------------------------------------------
  // 7. The reported calendar conversation, multi-turn with accumulated
  //    history, ff857ff pipeline vs the current production pipeline.
  // ------------------------------------------------------------------
  testWidgets('7. calendar conversation regression', (tester) async {
    await tester.runAsync(() async {
      final results = <Map<String, Object?>>[];
      for (final seed in [42, 1, 2]) {
        final config = LlmModelConfig.qwen35_2b.copyWith(seed: seed);

        final base = LlamaCppLocalAiService(config: config);
        await base.initialize();
        final history = <AiMessage>[];
        try {
          for (final (i, input) in calendarConversation.indexed) {
            final c = Case('CAL${i + 1}', 'calendar', input, '', calendarCheck,
                history: [...history]);
            final r = await _record(c, (onDelta) => _ff857ffGenerate(
                base, c.history, input, calendarClock, onDelta));
            history
              ..add(_u(input))
              ..add(_a(r['output']! as String));
            results.add({'pipeline': 'ff857ff', 'seed': seed, ...r});
            _print('calendar ff857ff seed=$seed', r);
          }
        } finally {
          await base.dispose();
        }

        final ai = LlamaCppLocalAiService(config: config);
        final repository = InMemoryChatRepository();
        final send = SendMessage(
          repository: repository,
          ai: ai,
          ids: IdGenerator(),
          clock: () => calendarClock,
        );
        Conversation? conversation;
        try {
          for (final (i, input) in calendarConversation.indexed) {
            final past = conversation == null
                ? <ChatMessage>[]
                : [...repository.messages[conversation!.id]!];
            final c = Case('CAL${i + 1}', 'calendar', input, '', calendarCheck,
                history: [
                  for (final m in past)
                    m.role == MessageRole.user ? _u(m.content) : _a(m.content),
                ]);
            final r = await _record(c, (onDelta) async {
              await for (final event in send(
                text: input,
                conversation: conversation,
                history: past,
              )) {
                if (event is UserMessageSaved) conversation = event.conversation;
                if (event is ReplyChunk) onDelta(event.delta);
              }
            });
            results.add({'pipeline': 'current', 'seed': seed, ...r});
            _print('calendar current seed=$seed', r);
          }
        } finally {
          await ai.dispose();
        }
      }
      await _save('calendar', results);
    });
  }, skip: !_parts.contains('calendar'),
      timeout: const Timeout(Duration(minutes: 40)));

  // ------------------------------------------------------------------
  // 8. The 33-case suite, ff857ff pipeline vs current, seeds 42/1/2.
  // ------------------------------------------------------------------
  testWidgets('8. suite vs ff857ff', (tester) async {
    await tester.runAsync(() async {
      final results = <Map<String, Object?>>[];
      for (final seed in [42, 1, 2]) {
        final config = LlmModelConfig.qwen35_2b.copyWith(seed: seed);
        final base = LlamaCppLocalAiService(config: config);
        await base.initialize();
        try {
          for (final c in buildCases(DateTime.now())) {
            final r = await _record(c, (onDelta) => _ff857ffGenerate(
                base, c.history, c.input, DateTime.now(), onDelta));
            results.add({'pipeline': 'ff857ff', 'seed': seed, ...r});
            _print('suite ff857ff seed=$seed', r);
          }
        } finally {
          await base.dispose();
        }
        final ai = LlamaCppLocalAiService(config: config);
        final send = SendMessage(
          repository: InMemoryChatRepository(),
          ai: ai,
          ids: IdGenerator(),
          clock: DateTime.now,
        );
        try {
          for (final c in buildCases(DateTime.now())) {
            final r = await _after(send, c);
            results.add({'pipeline': 'current', 'seed': seed, ...r});
            _print('suite current seed=$seed', r);
          }
        } finally {
          await ai.dispose();
        }
      }
      await _save('ff857ff', results);
    });
  }, skip: !_parts.contains('ff857ff'),
      timeout: const Timeout(Duration(minutes: 120)));
}
