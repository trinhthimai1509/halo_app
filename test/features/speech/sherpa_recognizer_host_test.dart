// Host-side check of the production SherpaRecognizer with the real model
// (no microphone). Skipped unless both paths are given, e.g. on Windows:
//   flutter test test/features/speech/sherpa_recognizer_host_test.dart
//     --dart-define=STT_MODEL_DIR=C:/dev/stt_models/sherpa-onnx-zipformer-vi-int8-2025-04-20
//     --dart-define=STT_LIB_DIR=<pub-cache>/sherpa_onnx_windows-1.13.8/windows
// The model's test_wavs/ are used here only as local test input; they are
// never bundled or installed with the app (non-commercial licence).
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/speech/data/audio/audio_signal.dart';
import 'package:offline_ai_chat/features/speech/data/sherpa/sherpa_recognizer.dart';
import 'package:offline_ai_chat/features/speech/data/sherpa/stt_model.dart';
import 'package:offline_ai_chat/features/speech/domain/transcript_formatter.dart';

const String _modelDir = String.fromEnvironment('STT_MODEL_DIR');
const String _libDir = String.fromEnvironment('STT_LIB_DIR');

void main() {
  test(
    'production recognizer decodes Vietnamese reference audio',
    () async {
      // Windows 11 ships an older onnxruntime.dll in System32; pin ours.
      if (Platform.isWindows) DynamicLibrary.open('$_libDir/onnxruntime.dll');
      final recognizer = await SherpaRecognizer.spawn(
        _modelDir,
        SttModel.vietnamese,
        nativeLibDir: _libDir,
      );
      try {
        await recognizer.warmUp();
        // 16 kHz mono PCM16 WAV with a 44-byte header.
        final bytes = File('$_modelDir/test_wavs/2.wav').readAsBytesSync();
        final samples =
            AudioSignal.pcm16ToFloat32(Uint8List.sublistView(bytes, 44));
        final text =
            TranscriptFormatter.format(await recognizer.transcribe(samples));
        expect(text, 'Âm lượng tivi giảm');
      } finally {
        await recognizer.dispose();
      }
    },
    skip: _modelDir.isEmpty || _libDir.isEmpty
        ? 'needs --dart-define=STT_MODEL_DIR and STT_LIB_DIR'
        : false,
  );
}
