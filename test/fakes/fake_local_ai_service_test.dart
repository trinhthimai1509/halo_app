import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/core/error/app_exception.dart';
import 'package:offline_ai_chat/features/local_ai/domain/local_ai_service.dart';

import 'fake_local_ai_service.dart';
import 'fake_responses.dart';

void main() {
  const request = GenerationRequest(
    messages: [AiMessage(role: AiRole.user, content: 'Explain on-device AI')],
  );

  test('streams the reply progressively in several chunks', () async {
    final ai = FakeLocalAiService(
      initializationDelay: Duration.zero,
      firstChunkDelay: Duration.zero,
      chunkDelay: Duration.zero,
    );
    await ai.initialize();

    final chunks = await ai.generate(request).toList();

    expect(chunks.length, greaterThan(10));
    expect(chunks.join(), FakeResponses.replyTo(request.messages));
  });

  test('refuses to generate before initialization', () async {
    final ai = FakeLocalAiService(initializationDelay: Duration.zero);

    expect(ai.isReady, isFalse);
    await expectLater(
      ai.generate(request).toList(),
      throwsA(isA<GenerationException>()),
    );
  });

  test('cancelling the subscription stops generation', () async {
    final ai = FakeLocalAiService(
      initializationDelay: Duration.zero,
      firstChunkDelay: Duration.zero,
      chunkDelay: const Duration(milliseconds: 5),
    );
    await ai.initialize();

    final received = <String>[];
    final firstChunk = Completer<void>();
    final subscription = ai.generate(request).listen((chunk) {
      received.add(chunk);
      if (!firstChunk.isCompleted) firstChunk.complete();
    });
    await firstChunk.future;
    await subscription.cancel();
    final countAtCancel = received.length;

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(received.length, countAtCancel);
    expect(received.join().length,
        lessThan(FakeResponses.replyTo(request.messages).length));
  });

  test('cannot be used after dispose', () async {
    final ai = FakeLocalAiService(initializationDelay: Duration.zero);
    await ai.initialize();
    await ai.dispose();

    expect(ai.isReady, isFalse);
    await expectLater(
      ai.generate(request).toList(),
      throwsA(isA<GenerationException>()),
    );
  });
}
