/// Makes raw recognizer output readable without inventing content.
///
/// The Vietnamese Zipformer model emits UPPER-CASE text with no punctuation
/// (e.g. `HÔM NAY TRỜI ĐẸP QUÁ`). Such text is lower-cased and its first
/// letter capitalised: `Hôm nay trời đẹp quá`. Diacritics are preserved
/// (case mapping is per code point on NFC text, which is what the model
/// emits).
///
/// Deliberately NOT done: adding punctuation, and guessing proper nouns.
/// The model's output carries no casing information, so a name such as
/// `HÀ NỘI` becomes `hà nội`; restoring it would need a lexicon or model.
/// Text that already contains lower-case letters is left as recognised.
abstract final class TranscriptFormatter {
  static final RegExp _spaces = RegExp(r'\s+');

  static String format(String raw) {
    final text = raw.trim().replaceAll(_spaces, ' ');
    if (text.isEmpty) return text;
    final isAllUpper = text == text.toUpperCase() && text != text.toLowerCase();
    if (!isAllUpper) return text;
    final lower = text.toLowerCase();
    final first = lower.runes.first;
    final head = String.fromCharCode(first);
    return head.toUpperCase() + lower.substring(head.length);
  }
}
