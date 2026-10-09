import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/llm_model_config.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/model_file_locator.dart';
import 'package:offline_ai_chat/features/model_setup/data/model_catalog.dart';
import 'package:offline_ai_chat/features/speech/data/sherpa/stt_model.dart';

void main() {
  test('the LLM package installs exactly where the LLM service looks', () {
    final llm = ModelCatalog.llm;
    expect(llm.installDir, ModelFileLocator.modelsDirectory);
    expect(llm.files.single.name, LlmModelConfig.qwen35_2b.fileName);
    expect(llm.files.single.bytes, 1280835840);
  });

  test('the speech package installs exactly the files the recognizer loads', () {
    final stt = ModelCatalog.speech;
    expect(
      stt.installDir,
      '${SttModelLocator.sttDirectory}/${SttModel.vietnamese.directoryName}',
    );
    expect(stt.files.map((f) => f.name), SttModel.vietnamese.files);
    expect(stt.files.any((f) => f.name.endsWith('.wav')), isFalse);
  });

  test('every file has a full SHA-256 and a size', () {
    for (final package in ModelCatalog.all) {
      for (final f in package.files) {
        expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: f.name);
        expect(f.bytes, greaterThan(0));
      }
    }
  });
}
