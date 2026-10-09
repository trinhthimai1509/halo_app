import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:offline_ai_chat/features/model_setup/data/model_import_platform.dart';
import 'package:path/path.dart' as p;

/// Host-side stand-in for the Android SAF bridge: "documents" are byte
/// arrays keyed by URI; copies really write files and really hash them.
class FakeImportPlatform implements ModelImportPlatform {
  List<PickedDocument> nextPick = const [];
  final Map<String, Uint8List> documents = {};

  /// ZIP documents: uri → (entry path → bytes).
  final Map<String, Map<String, Uint8List>> zips = {};

  int free = 1 << 40;
  Object? failWith;

  /// When set, copies wait here, so tests can cancel mid-import.
  Completer<void>? gate;

  final Set<String> _cancelled = {};
  final StreamController<({String jobId, int bytes})> _progress =
      StreamController.broadcast();

  @override
  Stream<({String jobId, int bytes})> get progress => _progress.stream;

  @override
  Future<List<PickedDocument>> pick({required bool multiple}) async => nextPick;

  @override
  Future<int> freeBytes(String directory) async => free;

  @override
  Future<CopiedFile> copy(String uri, String destination, String jobId) async {
    await _wait(jobId);
    final bytes = documents[uri]!;
    final file = File(destination);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    _progress.add((jobId: jobId, bytes: bytes.length));
    return CopiedFile(bytes: bytes.length, sha256: sha256.convert(bytes).toString());
  }

  @override
  Future<Map<String, CopiedFile>> extractZip(
    String uri,
    String directory,
    List<String> names,
    String jobId,
  ) async {
    await _wait(jobId);
    final out = <String, CopiedFile>{};
    for (final entry in zips[uri]!.entries) {
      final name = p.basename(entry.key);
      if (!names.contains(name)) continue;
      final file = File(p.join(directory, name));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value);
      out[name] = CopiedFile(
        bytes: entry.value.length,
        sha256: sha256.convert(entry.value).toString(),
      );
    }
    return out;
  }

  Future<void> _wait(String jobId) async {
    await gate?.future;
    if (_cancelled.contains(jobId)) throw const ImportCancelled();
    final error = failWith;
    if (error != null) throw error;
  }

  @override
  Future<void> cancel(String jobId) async {
    _cancelled.add(jobId);
  }
}

/// Bytes of [length] with a recognisable pattern.
Uint8List bytesOf(int length, [int seed = 1]) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * seed + 7) & 0xff));

String sha(Uint8List bytes) => sha256.convert(bytes).toString();
