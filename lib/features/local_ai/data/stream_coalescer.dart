import 'dart:async';

/// Merges rapid small text pieces into fewer emissions so the UI rebuilds at
/// most about once per [interval], while the first piece is emitted
/// immediately (time to first token stays visible).
class StreamCoalescer {
  StreamCoalescer({
    required this._onEmit,
    this.interval = const Duration(milliseconds: 50),
  });

  final void Function(String text) _onEmit;
  final Duration interval;

  final StringBuffer _pending = StringBuffer();
  Timer? _timer;
  bool _emittedFirst = false;

  void add(String text) {
    if (text.isEmpty) return;
    if (!_emittedFirst) {
      _emittedFirst = true;
      _onEmit(text);
      return;
    }
    _pending.write(text);
    _timer ??= Timer(interval, flush);
  }

  /// Emits anything pending now.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    _onEmit(text);
  }

  /// Drops pending text and stops the timer.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
