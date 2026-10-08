import 'dart:math';

/// Generates compact, roughly time-ordered unique identifiers.
///
/// A timestamp prefix keeps ids sortable for debugging; the random suffix
/// makes collisions practically impossible for a single-user local database.
class IdGenerator {
  IdGenerator({Random? random}) : _random = random ?? Random.secure();

  static const String _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
  static const int _suffixLength = 10;

  final Random _random;

  String next() {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = List.generate(
      _suffixLength,
      (_) => _alphabet[_random.nextInt(_alphabet.length)],
    ).join();
    return '$time$suffix';
  }
}
