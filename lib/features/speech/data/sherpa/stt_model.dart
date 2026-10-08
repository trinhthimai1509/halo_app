import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One sherpa-onnx offline transducer model: its directory name and files.
/// Everything model-specific lives here.
class SttModel {
  const SttModel({
    required this.directoryName,
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
    this.sampleRate = 16000,
    this.threads = 2,
  });

  /// Vietnamese Zipformer transducer, int8, Apache-2.0
  /// (`k2-fsa/sherpa-onnx` release `asr-models`, converted from
  /// `zzasdf/viet_iter3_pseudo_label`). 77.5 MB on disk. Validated in
  /// docs/STT_SPIKE.md. Its `test_wavs/` folder is NOT part of the install
  /// (non-commercial licence).
  static const SttModel vietnamese = SttModel(
    directoryName: 'sherpa-onnx-zipformer-vi-int8-2025-04-20',
    encoder: 'encoder-epoch-12-avg-8.int8.onnx',
    decoder: 'decoder-epoch-12-avg-8.onnx',
    joiner: 'joiner-epoch-12-avg-8.int8.onnx',
    tokens: 'tokens.txt',
  );

  final String directoryName;
  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
  final int sampleRate;

  /// Decode threads. Two matched the LLM's validated Android setting and
  /// gave RTF ≈ 0.04 on an Exynos 1380.
  final int threads;

  List<String> get files => [encoder, decoder, joiner, tokens];
}

/// Finds an installed [SttModel] on the device.
///
/// Same convention as the LLM's `ModelFileLocator`: the development
/// location is `<external files>/stt/<directoryName>/` (writable with
/// `adb push`), then the internal support directory, where a production
/// installer would place it.
class SttModelLocator {
  const SttModelLocator();

  static const String sttDirectory = 'stt';

  Future<List<String>> candidateDirectories(SttModel model) async {
    final roots = <Directory?>[
      if (Platform.isAndroid) await getExternalStorageDirectory(),
      await getApplicationSupportDirectory(),
    ];
    return [
      for (final root in roots.whereType<Directory>())
        p.join(root.path, sttDirectory, model.directoryName),
    ];
  }

  /// The first directory that contains every model file, or null.
  Future<String?> find(SttModel model) async {
    for (final dir in await candidateDirectories(model)) {
      final complete = await Future.wait(
        model.files.map((f) => File(p.join(dir, f)).exists()),
      );
      if (complete.every((exists) => exists)) return dir;
    }
    return null;
  }
}
