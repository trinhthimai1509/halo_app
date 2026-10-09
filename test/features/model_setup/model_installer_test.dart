import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/model_setup/data/model_import_platform.dart';
import 'package:offline_ai_chat/features/model_setup/data/model_installer.dart';
import 'package:offline_ai_chat/features/model_setup/domain/model_package.dart';
import 'package:path/path.dart' as p;

import 'fake_import_platform.dart';

void main() {
  late Directory root;
  late Directory devRoot;
  late FakeImportPlatform platform;

  final llmBytes = bytesOf(4096, 3);
  final encoder = bytesOf(2048, 5);
  final tokens = bytesOf(300, 11);

  final llm = ModelPackage(
    id: 'llm',
    title: 'LLM',
    installDir: 'models',
    files: [ModelFileSpec(name: 'model.gguf', bytes: llmBytes.length, sha256: sha(llmBytes))],
  );
  final speech = ModelPackage(
    id: 'stt',
    title: 'STT',
    installDir: 'stt/vi',
    acceptsZip: true,
    files: [
      ModelFileSpec(name: 'encoder.onnx', bytes: encoder.length, sha256: sha(encoder)),
      ModelFileSpec(name: 'tokens.txt', bytes: tokens.length, sha256: sha(tokens)),
    ],
  );

  ModelInstaller installer() => ModelInstaller(
        platform: platform,
        privateRoot: () async => root.path,
        developerRoot: () async => devRoot.path,
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('halo_models_');
    devRoot = await Directory.systemTemp.createTemp('halo_dev_');
    platform = FakeImportPlatform();
  });

  tearDown(() async {
    await root.delete(recursive: true);
    await devRoot.delete(recursive: true);
  });

  String installed(String package, String name) => p.join(root.path, package, name);

  void pickLlm({Uint8List? bytes, int? reportedSize, String name = 'model.gguf'}) {
    final data = bytes ?? llmBytes;
    platform.documents['content://llm'] = data;
    platform.nextPick = [
      PickedDocument(uri: 'content://llm', name: name, size: reportedSize ?? data.length),
    ];
  }

  Future<bool> stagingLeft() async {
    final dir = Directory(p.join(root.path, '.import'));
    if (!await dir.exists()) return false;
    return dir.list().any((e) => e.path.endsWith('.staging'));
  }

  test('missing models are reported as missing', () async {
    expect((await installer().status(llm)).state, ModelState.missing);
    expect((await installer().status(speech)).state, ModelState.missing);
  });

  test('successful single-file import installs and verifies', () async {
    pickLlm();
    final progress = <double>[];
    final outcome = await installer().import(llm, onProgress: progress.add);
    expect(outcome, isA<ImportSucceeded>());
    expect(await File(installed('models', 'model.gguf')).readAsBytes(), llmBytes);
    final status = await installer().status(llm);
    expect(status.state, ModelState.installed);
    expect(status.source, ModelSource.imported);
    expect(progress.last, 1);
    expect(await stagingLeft(), isFalse);
  });

  test('speech model imports from one ZIP, ignoring other entries', () async {
    platform.zips['content://zip'] = {
      'sherpa-onnx-vi/encoder.onnx': encoder,
      'sherpa-onnx-vi/tokens.txt': tokens,
      'sherpa-onnx-vi/test_wavs/0.wav': bytesOf(100), // must not be installed
    };
    platform.nextPick = const [PickedDocument(uri: 'content://zip', name: 'halo-stt-vi.zip', size: 5000)];
    expect(await installer().import(speech), isA<ImportSucceeded>());
    final dir = Directory(p.join(root.path, 'stt', 'vi'));
    expect(
      (await dir.list().map((e) => p.basename(e.path)).toList())..sort(),
      ['encoder.onnx', 'tokens.txt'],
    );
  });

  test('speech model imports from the loose files picked together', () async {
    platform.documents
      ..['content://e'] = encoder
      ..['content://t'] = tokens;
    platform.nextPick = [
      PickedDocument(uri: 'content://t', name: 'tokens.txt', size: tokens.length),
      PickedDocument(uri: 'content://e', name: 'encoder.onnx', size: encoder.length),
    ];
    expect(await installer().import(speech), isA<ImportSucceeded>());
    expect((await installer().status(speech)).state, ModelState.installed);
  });

  test('a wrong file is rejected before copying (size from the picker)', () async {
    pickLlm(bytes: bytesOf(100), reportedSize: 100, name: 'photo.jpg');
    final outcome = await installer().import(llm);
    expect(outcome, isA<ImportFailed>().having((f) => f.reason, 'reason', ImportFailure.wrongFile));
    expect(File(installed('models', 'model.gguf')).existsSync(), isFalse);
  });

  test('a same-size but different file fails verification', () async {
    platform.documents['content://llm'] = bytesOf(llmBytes.length, 9);
    platform.nextPick = [PickedDocument(uri: 'content://llm', name: 'model.gguf', size: llmBytes.length)];
    final outcome = await installer().import(llm);
    expect(
      outcome,
      isA<ImportFailed>().having((f) => f.reason, 'reason', ImportFailure.verificationFailed),
    );
    expect(File(installed('models', 'model.gguf')).existsSync(), isFalse);
    expect(await stagingLeft(), isFalse);
  });

  test('missing speech files are named', () async {
    platform.documents['content://e'] = encoder;
    platform.nextPick = [PickedDocument(uri: 'content://e', name: 'encoder.onnx', size: encoder.length)];
    final outcome = await installer().import(speech);
    expect(
      outcome,
      isA<ImportFailed>()
          .having((f) => f.reason, 'reason', ImportFailure.missingFiles)
          .having((f) => f.detail, 'detail', 'tokens.txt'),
    );
  });

  test('insufficient storage is detected before copying', () async {
    pickLlm();
    platform.free = llmBytes.length; // less than size + safety margin
    final outcome = await installer().import(llm);
    expect(
      outcome,
      isA<ImportFailed>()
          .having((f) => f.reason, 'reason', ImportFailure.insufficientStorage)
          .having((f) => f.requiredBytes, 'required',
              llmBytes.length + ModelInstaller.safetyMarginBytes),
    );
    expect(await stagingLeft(), isFalse);
  });

  test('closing the picker changes nothing', () async {
    platform.nextPick = const [];
    expect(await installer().import(llm), isA<ImportDismissed>());
  });

  test('cancelling mid-import keeps the previous model', () async {
    pickLlm();
    final i = installer();
    expect(await i.import(llm), isA<ImportSucceeded>()); // previous model

    final replacement = bytesOf(llmBytes.length, 13);
    platform.documents['content://llm'] = replacement;
    platform.gate = Completer<void>();
    final running = i.import(llm);
    await Future<void>.delayed(Duration.zero);
    expect(i.isBusy, isTrue);
    await i.cancel();
    platform.gate!.complete();
    expect(await running, isA<ImportCancelledByUser>());
    expect(await File(installed('models', 'model.gguf')).readAsBytes(), llmBytes);
    expect(await stagingLeft(), isFalse);
    expect(i.isBusy, isFalse);
  });

  test('a failed replacement rolls back to the working speech model', () async {
    platform.zips['content://zip'] = {'encoder.onnx': encoder, 'tokens.txt': tokens};
    platform.nextPick = const [PickedDocument(uri: 'content://zip', name: 's.zip', size: 10)];
    final i = installer();
    expect(await i.import(speech), isA<ImportSucceeded>());

    platform.zips['content://bad'] = {'encoder.onnx': bytesOf(encoder.length, 21), 'tokens.txt': tokens};
    platform.nextPick = const [PickedDocument(uri: 'content://bad', name: 'other.zip', size: 10)];
    expect(await i.import(speech), isA<ImportFailed>());
    expect(await File(installed('stt/vi', 'encoder.onnx')).readAsBytes(), encoder);
    expect((await i.status(speech)).state, ModelState.installed);
  });

  test('retry after an I/O failure succeeds', () async {
    pickLlm();
    final i = installer();
    platform.failWith = const FileSystemException('read error');
    expect(
      await i.import(llm),
      isA<ImportFailed>().having((f) => f.reason, 'reason', ImportFailure.ioError),
    );
    platform.failWith = null;
    expect(await i.import(llm), isA<ImportSucceeded>());
  });

  test('a second import while one is running is refused', () async {
    pickLlm();
    final i = installer();
    platform.gate = Completer<void>();
    final first = i.import(llm);
    await Future<void>.delayed(Duration.zero);
    expect(
      await i.import(llm),
      isA<ImportFailed>().having((f) => f.reason, 'reason', ImportFailure.busy),
    );
    platform.gate!.complete();
    expect(await first, isA<ImportSucceeded>());
  });

  test('installed models persist across restarts (new installer instance)', () async {
    pickLlm();
    await installer().import(llm);
    final afterRestart = installer();
    expect((await afterRestart.status(llm)).state, ModelState.installed);
  });

  test('interrupted import: staging is removed, half swap is rolled back', () async {
    // App killed after the old folder was moved aside, before the new one
    // was moved in: only `.import/stt.old` holds the working model.
    final old = Directory(p.join(root.path, '.import', 'stt.old'));
    await old.create(recursive: true);
    await File(p.join(old.path, 'encoder.onnx')).writeAsBytes(encoder);
    await File(p.join(old.path, 'tokens.txt')).writeAsBytes(tokens);
    final staging = Directory(p.join(root.path, '.import', 'llm.staging'));
    await staging.create(recursive: true);
    await File(p.join(staging.path, 'model.gguf')).writeAsBytes(bytesOf(10));

    await installer().recover([llm, speech]);

    expect(await staging.exists(), isFalse);
    expect(await old.exists(), isFalse);
    expect((await installer().status(speech)).state, ModelState.installed);
  });

  test('interrupted after the swap: the leftover old copy is deleted', () async {
    platform.zips['content://zip'] = {'encoder.onnx': encoder, 'tokens.txt': tokens};
    platform.nextPick = const [PickedDocument(uri: 'content://zip', name: 's.zip', size: 10)];
    await installer().import(speech);
    final old = Directory(p.join(root.path, '.import', 'stt.old'));
    await old.create(recursive: true);
    await File(p.join(old.path, 'encoder.onnx')).writeAsBytes(bytesOf(5));

    await installer().recover([llm, speech]);

    expect(await old.exists(), isFalse);
    expect(await File(installed('stt/vi', 'encoder.onnx')).readAsBytes(), encoder);
  });

  test('a damaged installed file is reported as invalid', () async {
    pickLlm();
    await installer().import(llm);
    await File(installed('models', 'model.gguf')).writeAsBytes(bytesOf(10));
    expect((await installer().status(llm)).state, ModelState.invalid);
  });

  test('a developer (adb) copy is recognised but labelled as such', () async {
    final dev = File(p.join(devRoot.path, 'models', 'model.gguf'));
    await dev.parent.create(recursive: true);
    await dev.writeAsBytes(llmBytes);
    final status = await installer().status(llm);
    expect(status.state, ModelState.installed);
    expect(status.source, ModelSource.developer);
  });
}
