// Host-side check of the sherpa-onnx Vietnamese model (no microphone).
// Skipped unless both paths are given, e.g. on Windows:
//   flutter test test/spike/stt_host_test.dart
//     --dart-define=STT_MODEL_DIR=C:/dev/stt_models/sherpa-onnx-zipformer-vi-int8-2025-04-20
//     --dart-define=STT_LIB_DIR=<pub-cache>/sherpa_onnx_windows-1.13.8/windows
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../spike/stt_vi/stt_worker.dart';

const String _modelDir = String.fromEnvironment('STT_MODEL_DIR');
const String _libDir = String.fromEnvironment('STT_LIB_DIR');

void main() {
  test(
    'recognises the bundled Vietnamese reference WAVs',
    () async {
      // Windows 11 ships an older onnxruntime.dll in System32, which the
      // loader would pick first. Pin the package's copy for this process.
      if (Platform.isWindows) DynamicLibrary.open('$_libDir/onnxruntime.dll');
      final worker = await SttWorker.spawn(_modelDir, nativeLibDir: _libDir);
      // ignore: avoid_print
      print('[STT] host load_ms=${worker.loadMs}');
      try {
        final wavs = Directory('$_modelDir/test_wavs')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.wav'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        expect(wavs, isNotEmpty);
        for (final wav in wavs) {
          final r = await worker.transcribeFile(wav.path);
          // ignore: avoid_print
          print('[STT] host file=${wav.uri.pathSegments.last} '
              'decode_ms=${r.decodeMs} got="${r.text}"');
          expect(r.text.trim(), isNotEmpty);
        }
      } finally {
        await worker.dispose();
      }
    },
    skip: _modelDir.isEmpty || _libDir.isEmpty
        ? 'needs --dart-define=STT_MODEL_DIR and STT_LIB_DIR'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
