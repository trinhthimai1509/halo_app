import 'dart:async';
import 'dart:math';

import 'package:offline_ai_chat/core/error/app_exception.dart';
import 'package:offline_ai_chat/features/local_ai/domain/local_ai_service.dart';
import 'fake_responses.dart';

/// Development stand-in for a local model.
///
/// Produces canned replies word by word with a realistic "time to first
/// token" and jittered inter-token delay, so the streaming UX can be built
/// and tested before a real runtime exists. All delays are injectable;
/// tests pass [Duration.zero].
class FakeLocalAiService implements LocalAiService {
  FakeLocalAiService({
    this.initializationDelay = const Duration(milliseconds: 300),
    this.firstChunkDelay = const Duration(milliseconds: 750),
    this.chunkDelay = const Duration(milliseconds: 38),
    Random? random,
  }) : _random = random ?? Random();

  final Duration initializationDelay;
  final Duration firstChunkDelay;
  final Duration chunkDelay;
  final Random _random;

  static final RegExp _chunkPattern = RegExp(r'\S+\s*');

  bool _ready = false;
  bool _disposed = false;
  Future<void>? _initializing;

  @override
  bool get isReady => _ready;

  @override
  Future<void> initialize() {
    if (_disposed) {
      return Future.error(const GenerationException('Service was disposed.'));
    }
    return _initializing ??= Future<void>.delayed(initializationDelay, () {
      _ready = true;
    });
  }

  @override
  Stream<String> generate(GenerationRequest request) {
    if (!_ready || _disposed) {
      return Stream.error(const GenerationException('Model is not loaded.'));
    }
    final chunks = _chunkPattern
        .allMatches(FakeResponses.replyTo(request.messages))
        .map((match) => match.group(0)!)
        .toList(growable: false);
    return _streamChunks(chunks);
  }

  Stream<String> _streamChunks(List<String> chunks) {
    late final StreamController<String> controller;
    Timer? timer;
    var index = 0;

    void emitNext() {
      if (index >= chunks.length) {
        controller.close();
        return;
      }
      controller.add(chunks[index++]);
      timer = Timer(_jittered(chunkDelay), emitNext);
    }

    controller = StreamController<String>(
      onListen: () => timer = Timer(firstChunkDelay, emitNext),
      onPause: () => timer?.cancel(),
      onResume: () => timer = Timer(_jittered(chunkDelay), emitNext),
      // Cancellation contract: stop producing immediately.
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  Duration _jittered(Duration base) {
    if (base == Duration.zero) return base;
    final factor = 0.5 + _random.nextDouble();
    return base * factor;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _ready = false;
  }
}
