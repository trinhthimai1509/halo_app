import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/app/di/providers.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/llama_cpp_local_ai_service.dart';
import 'package:offline_ai_chat/features/local_ai/data/unsupported_local_ai_service.dart';
import 'package:offline_ai_chat/features/speech/data/sherpa_speech_to_text_service.dart';
import 'package:offline_ai_chat/features/speech/data/unsupported_speech_to_text_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The real speech service creates a `record` AudioRecorder, which talks
  // to its native side immediately; answer with no-ops on the test host.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.record/messages'),
    (_) async => null,
  );

  test('no fake AI or fake speech class exists in production code (lib/)', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (RegExp(r'class\s+Fake\w*').hasMatch(source) ||
          source.contains('fake_local_ai_service') ||
          source.contains('fake_speech_to_text_service')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('Android uses the real llama.cpp and sherpa-onnx services', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = ProviderContainer.test();
    expect(container.read(localAiServiceProvider), isA<LlamaCppLocalAiService>());
    expect(
      container.read(speechToTextServiceProvider),
      isA<SherpaSpeechToTextService>(),
    );
  });

  test('an unsupported platform reports "not available" and never falls '
      'back to canned answers', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = ProviderContainer.test();
    expect(
      container.read(localAiServiceProvider),
      isA<UnsupportedLocalAiService>(),
    );
    expect(
      container.read(speechToTextServiceProvider),
      isA<UnsupportedSpeechToTextService>(),
    );
    await expectLater(
      container.read(localAiServiceProvider).initialize(),
      throwsA(anything),
    );
  });
}
