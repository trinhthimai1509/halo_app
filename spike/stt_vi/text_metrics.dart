/// Accuracy metrics for comparing a transcript with the expected sentence.
///
/// Both sides are normalised first: lower-case (the Vietnamese Zipformer
/// emits UPPER-CASE), punctuation removed, whitespace collapsed. Diacritics
/// are kept: a missing or wrong tone mark is an error in Vietnamese.
abstract final class TextMetrics {
  static final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
  static final RegExp _spaces = RegExp(r'\s+');

  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(_nonWord, ' ')
      .replaceAll(_spaces, ' ')
      .trim();

  /// Word error rate: word-level edit distance / reference word count.
  static double wer(String reference, String hypothesis) {
    final ref = _words(reference);
    if (ref.isEmpty) return _words(hypothesis).isEmpty ? 0 : 1;
    return _distance(ref, _words(hypothesis)) / ref.length;
  }

  /// Character error rate over normalised text without spaces.
  static double cer(String reference, String hypothesis) {
    final ref = _chars(reference);
    if (ref.isEmpty) return _chars(hypothesis).isEmpty ? 0 : 1;
    return _distance(ref, _chars(hypothesis)) / ref.length;
  }

  static List<String> _words(String text) {
    final n = normalize(text);
    return n.isEmpty ? const [] : n.split(' ');
  }

  static List<String> _chars(String text) =>
      normalize(text).replaceAll(' ', '').runes.map(String.fromCharCode).toList();

  /// Levenshtein distance (substitution, insertion, deletion all cost 1).
  static int _distance(List<String> a, List<String> b) {
    var previous = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }
}
