import 'package:flutter/painting.dart';

/// Renders the small Markdown subset the local model emits despite being
/// asked not to: `**bold**` / `__bold__`, `*italic*`, `` `code` ``,
/// `# headings` (shown bold), `- bullets` (shown as •) and `---` rules
/// (dropped). Everything else, including unclosed markers while a reply is
/// still streaming, stays literal text. No links, images or HTML are
/// interpreted, so nothing in a reply can trigger an action.
abstract final class MarkdownLite {
  static final RegExp _heading = RegExp(r'^\s{0,3}#{1,6}\s+(.*)$');
  static final RegExp _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
  static final RegExp _rule = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');
  static final RegExp _inline = RegExp(
    r'\*\*(?=\S)(.+?)(?<=\S)\*\*'
    r'|(?<!\w)__(?=\S)(.+?)(?<=\S)__(?!\w)'
    r'|`([^`\n]+)`'
    r'|(?<![*\w])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![*\w])',
  );

  static const TextStyle _bold = TextStyle(fontWeight: FontWeight.w600);
  static const TextStyle _italic = TextStyle(fontStyle: FontStyle.italic);
  static const TextStyle _code = TextStyle(fontFamily: 'monospace');

  static List<InlineSpan> spans(String text) {
    final out = <InlineSpan>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLast = i == lines.length - 1;
      if (_rule.hasMatch(line)) continue;
      final heading = _heading.firstMatch(line);
      final bullet = _bullet.firstMatch(line);
      if (heading != null) {
        out.add(TextSpan(style: _bold, children: _inlineSpans(heading[1]!)));
      } else if (bullet != null) {
        out
          ..add(TextSpan(text: '${bullet[1]}• '))
          ..addAll(_inlineSpans(bullet[2]!));
      } else {
        out.addAll(_inlineSpans(line));
      }
      if (!isLast) out.add(const TextSpan(text: '\n'));
    }
    return out;
  }

  /// Plain text with the same markers removed (for tests and copying).
  static String plain(String text) =>
      TextSpan(children: spans(text)).toPlainText();

  static List<InlineSpan> _inlineSpans(String text) {
    final out = <InlineSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > last) {
        out.add(TextSpan(text: text.substring(last, m.start)));
      }
      final (content, style) = m[1] != null
          ? (m[1]!, _bold)
          : m[2] != null
          ? (m[2]!, _bold)
          : m[3] != null
          ? (m[3]!, _code)
          : (m[4]!, _italic);
      out.add(TextSpan(text: content, style: style));
      last = m.end;
    }
    if (last < text.length) out.add(TextSpan(text: text.substring(last)));
    return out;
  }
}
