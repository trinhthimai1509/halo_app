import '../../local_ai/data/llama_cpp/llm_model_config.dart';
import '../../local_ai/data/llama_cpp/model_file_locator.dart';
import '../../speech/data/sherpa/stt_model.dart';
import '../domain/model_package.dart';

/// The model packages Halo can import, with exact sizes and SHA-256 hashes.
///
/// Hash provenance (checked 2026-10-09, see docs/MODEL_INSTALL.md):
/// - GGUF: Hugging Face LFS metadata of `unsloth/Qwen3.5-2B-GGUF`
///   (`X-Linked-ETag` = SHA-256, `X-Linked-Size`).
/// - ONNX files: Hugging Face LFS metadata of
///   `csukuangfj/sherpa-onnx-zipformer-vi-int8-2025-04-20`.
/// - tokens.txt: not an LFS file; its git blob SHA-1 published by Hugging
///   Face (8adf5f75…) matches the file whose SHA-256 is recorded here.
abstract final class ModelCatalog {
  static final ModelPackage llm = ModelPackage(
    id: 'llm',
    title: 'Local AI model',
    installDir: ModelFileLocator.modelsDirectory,
    files: [
      ModelFileSpec(
        name: LlmModelConfig.qwen35_2b.fileName,
        bytes: 1280835840,
        sha256:
            'aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223',
      ),
    ],
  );

  static final ModelPackage speech = ModelPackage(
    id: 'stt',
    title: 'Vietnamese speech model',
    installDir:
        '${SttModelLocator.sttDirectory}/${SttModel.vietnamese.directoryName}',
    acceptsZip: true,
    files: [
      ModelFileSpec(
        name: SttModel.vietnamese.encoder,
        bytes: 70876129,
        sha256:
            'b3abdef7a660fea7faf5e076b3c7613b0fc98406707103784d018189bb522124',
      ),
      ModelFileSpec(
        name: SttModel.vietnamese.decoder,
        bytes: 5165084,
        sha256:
            'd1d27cca84c824a8acf5ce6edf0f2c0880cfe295d2e69b95134de1707e1d9998',
      ),
      ModelFileSpec(
        name: SttModel.vietnamese.joiner,
        bytes: 1033417,
        sha256:
            '38ec49e1c18e4feb0cad4de13e25c83a866cf56f4a66f22e8ff579d591a69a46',
      ),
      ModelFileSpec(
        name: SttModel.vietnamese.tokens,
        bytes: 25847,
        sha256:
            'f536d03c2e95ebd2930cf0abec88e823bd17d3c1933da7ae6a82db3b80605e15',
      ),
    ],
  );

  static List<ModelPackage> get all => [llm, speech];
}
