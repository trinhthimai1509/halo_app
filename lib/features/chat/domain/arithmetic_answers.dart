/// Answers explicit, simple calculations ("17 cộng 25 bằng bao nhiêu?",
/// "12.000 × 3", "100 chia 8") exactly, in Dart. The 2B model gets these
/// wrong at random (17 + 25 = 32 on device; see docs/LLM_QUALITY.md).
///
/// Safety and scope:
/// - Nothing is evaluated as code. The message must match a fixed grammar:
///   2–4 non-negative numbers joined by + − × ÷ (symbols or the Vietnamese
///   words cộng / trừ / nhân / chia), optionally preceded by "tính" and
///   followed by "bằng bao nhiêu / là bao nhiêu / =". Anything else —
///   including word problems ("mua 3 quyển vở…") — goes to the model.
/// - Numbers use Vietnamese notation: "." groups thousands (12.000), ","
///   is the decimal separator (2,5). Ambiguous forms such as "1.5" are not
///   recognised.
/// - × and ÷ bind tighter than + and −.
abstract final class ArithmeticAnswers {
  static final RegExp _punctuation = RegExp(r'[?!]+');
  static final RegExp _spaces = RegExp(r'\s+');

  static final RegExp _leading = RegExp(
    r'^(?:(?:xin chào|chào bạn|chào|bạn ơi|cho (?:tôi|mình|em) hỏi|'
    r'(?:hãy |bạn )?(?:tính giúp|tính hộ|tính)(?: (?:tôi|mình|em))?)\s+)+',
  );
  static final RegExp _trailing = RegExp(
    r'(?:\s*(?:=|bằng|là|được)?\s*(?:bao nhiêu|mấy|gì)?'
    r'(?:\s+(?:vậy|nhỉ|ạ|thế|hả|nhé|bạn))*\s*)$',
  );

  static const Map<String, String> _words = {
    'cộng với': '+', 'cộng': '+', 'trừ đi': '-', 'trừ': '-',
    'nhân với': '*', 'nhân': '*', 'chia cho': '/', 'chia': '/',
    '×': '*', 'x': '*', '÷': '/', ':': '/', '−': '-',
  };

  static final RegExp _number =
      RegExp(r'^(?:\d{1,3}(?:\.\d{3})+|\d+)(?:,\d+)?$');
  static final RegExp _token = RegExp(r'[^\s+\-*/]+|[+\-*/]');

  /// The reply for [message], or null when it is not a plain calculation.
  static String? answer(String message) {
    var text = message
        .toLowerCase()
        .replaceAll(_punctuation, ' ')
        // A comma followed by a space is punctuation; "2,5" is a decimal.
        .replaceAll(RegExp(r',(?=\s)|,$'), ' ')
        .replaceAll(_spaces, ' ')
        .trim();
    if (text.endsWith('.')) text = text.substring(0, text.length - 1).trim();
    text = text.replaceFirst(_leading, '');
    final greeted = message.toLowerCase().trimLeft().startsWith(
          RegExp(r'(?:xin chào|chào)'),
        );
    // Operator words → symbols (longest first), then strip the question tail.
    for (final entry in _words.entries) {
      text = text.replaceAll(
        RegExp('(?<=[\\s\\d])${RegExp.escape(entry.key)}(?=[\\s\\d])'),
        ' ${entry.value} ',
      );
    }
    text = text.replaceFirst(_trailing, '').trim();
    if (text.isEmpty) return null;

    final tokens = _token.allMatches(text).map((m) => m.group(0)!).toList();
    if (tokens.length < 3 || tokens.length > 7 || tokens.length.isEven) {
      return null;
    }
    final numbers = <_Num>[];
    final ops = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      if (i.isEven) {
        final n = _Num.parse(tokens[i]);
        if (n == null) return null;
        numbers.add(n);
      } else {
        if (!'+-*/'.contains(tokens[i]) || tokens[i].length != 1) return null;
        ops.add(tokens[i]);
      }
    }

    final result = _evaluate(numbers, ops);
    final expression = StringBuffer(numbers.first.source);
    for (var i = 0; i < ops.length; i++) {
      expression.write(' ${_symbol(ops[i])} ${numbers[i + 1].source}');
    }
    final reply = result == null
        ? 'Không thể chia cho 0.'
        : '$expression ${result.isExact4 ? '=' : '≈'} ${_format(result)}.';
    return greeted ? 'Xin chào! $reply' : reply;
  }

  /// Exact rational evaluation with × ÷ before + −. Null on division by 0.
  static _Fraction? _evaluate(List<_Num> numbers, List<String> ops) {
    final terms = <_Fraction>[numbers.first.value];
    final signs = <String>[];
    for (var i = 0; i < ops.length; i++) {
      final next = numbers[i + 1].value;
      switch (ops[i]) {
        case '*':
          terms.last = terms.last * next;
        case '/':
          if (next.isZero) return null;
          terms.last = terms.last / next;
        default:
          signs.add(ops[i]);
          terms.add(next);
      }
    }
    var total = terms.first;
    for (var i = 0; i < signs.length; i++) {
      total = signs[i] == '+' ? total + terms[i + 1] : total - terms[i + 1];
    }
    return total;
  }

  static String _symbol(String op) => switch (op) {
        '+' => '+',
        '-' => '−',
        '*' => '×',
        _ => ':',
      };

  /// Vietnamese number format: 36.000 · 12,5 · −3 · 0,3333 (4 decimals max).
  static String _format(_Fraction f) {
    final negative = f.numerator.isNegative;
    final n = f.numerator.abs();
    final whole = n ~/ f.denominator;
    var remainder = n % f.denominator;
    final digits = StringBuffer();
    for (var i = 0; i < 4 && remainder != BigInt.zero; i++) {
      remainder *= BigInt.from(10);
      digits.write(remainder ~/ f.denominator);
      remainder %= f.denominator;
    }
    final grouped = whole
        .toString()
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    final frac = digits.toString().replaceFirst(RegExp(r'0+$'), '');
    return '${negative ? '−' : ''}$grouped${frac.isEmpty ? '' : ',$frac'}';
  }
}

class _Num {
  _Num(this.source, this.value);

  final String source;
  final _Fraction value;

  static _Num? parse(String token) {
    if (!ArithmeticAnswers._number.hasMatch(token) || token.length > 18) {
      return null;
    }
    final parts = token.replaceAll('.', '').split(',');
    final whole = BigInt.parse(parts[0]);
    if (parts.length == 1) return _Num(token, _Fraction(whole, BigInt.one));
    final scale = BigInt.from(10).pow(parts[1].length);
    return _Num(token, _Fraction(whole * scale + BigInt.parse(parts[1]), scale));
  }
}

/// Minimal exact fraction (BigInt), normalised, positive denominator.
class _Fraction {
  _Fraction(BigInt numerator, BigInt denominator)
      : numerator = _norm(numerator, denominator).$1,
        denominator = _norm(numerator, denominator).$2;

  final BigInt numerator;
  final BigInt denominator;

  bool get isZero => numerator == BigInt.zero;

  /// Whether the value has at most 4 decimal places (printed exactly).
  bool get isExact4 =>
      (numerator * BigInt.from(10000)) % denominator == BigInt.zero;

  static (BigInt, BigInt) _norm(BigInt n, BigInt d) {
    if (d.isNegative) {
      n = -n;
      d = -d;
    }
    final g = n.gcd(d);
    return g == BigInt.zero || g == BigInt.one ? (n, d) : (n ~/ g, d ~/ g);
  }

  _Fraction operator +(_Fraction o) => _Fraction(
        numerator * o.denominator + o.numerator * denominator,
        denominator * o.denominator,
      );
  _Fraction operator -(_Fraction o) => _Fraction(
        numerator * o.denominator - o.numerator * denominator,
        denominator * o.denominator,
      );
  _Fraction operator *(_Fraction o) =>
      _Fraction(numerator * o.numerator, denominator * o.denominator);
  _Fraction operator /(_Fraction o) =>
      _Fraction(numerator * o.denominator, denominator * o.numerator);
}
