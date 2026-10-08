import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licences for components that are not Dart packages, so Flutter does not
/// collect them automatically: the native inference runtimes and the model
/// weights shipped or installed with the app. Dart packages (llamadart,
/// sherpa_onnx, record, …) are added to the licence page by Flutter itself.
///
/// The texts are bundled under `assets/licenses/` so they also travel with
/// every distributed build.
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    Future<String> load(String name) =>
        rootBundle.loadString('assets/licenses/$name');
    final apache = await load('apache_2.0.txt');

    yield LicenseEntryWithLineBreaks(
      const ['llama.cpp', 'ggml'],
      await load('llama_cpp_LICENSE.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['ONNX Runtime'],
      await load('onnxruntime_LICENSE.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['Qwen3.5-2B (language model weights)'],
      'Qwen3.5-2B by the Qwen team, Alibaba Cloud '
      '(https://huggingface.co/Qwen/Qwen3.5-2B). GGUF Q4_K_M quantisation '
      'by Unsloth (https://huggingface.co/unsloth/Qwen3.5-2B-GGUF). '
      'Licensed under the Apache License, Version 2.0.\n\n$apache',
    );
    yield LicenseEntryWithLineBreaks(
      const ['Vietnamese Zipformer ASR (speech model weights)'],
      'Speech recognition model from '
      'https://huggingface.co/zzasdf/viet_iter3_pseudo_label, converted '
      'to ONNX (sherpa-onnx-zipformer-vi-int8-2025-04-20) by the k2-fsa '
      'sherpa-onnx project (https://github.com/k2-fsa/sherpa-onnx). '
      'Licensed under the Apache License, Version 2.0.\n\n$apache',
    );
  });
}
