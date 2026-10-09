import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A document the user picked in the system file picker. [uri] is an
/// opaque content URI; it is never shown in the UI.
@immutable
class PickedDocument {
  const PickedDocument({required this.uri, required this.name, this.size});

  final String uri;
  final String name;

  /// Size reported by the provider; null if unknown.
  final int? size;
}

/// Result of streaming one file into private storage.
@immutable
class CopiedFile {
  const CopiedFile({required this.bytes, required this.sha256});

  final int bytes;
  final String sha256;
}

/// Thrown when the user cancels a running copy.
class ImportCancelled implements Exception {
  const ImportCancelled();
}

/// Platform side of model import (Android Storage Access Framework).
/// Abstracted so the installer can be tested on the host.
abstract interface class ModelImportPlatform {
  /// Opens the system file picker. Empty when the user backs out.
  Future<List<PickedDocument>> pick({required bool multiple});

  /// Free bytes on the volume holding [directory].
  Future<int> freeBytes(String directory);

  /// Streams [uri] into [destination], hashing on the fly. Throws
  /// [ImportCancelled] after [cancel] for the same [jobId].
  Future<CopiedFile> copy(String uri, String destination, String jobId);

  /// Streams the ZIP at [uri] and writes the entries whose file name is in
  /// [names] (from any folder) into [directory].
  Future<Map<String, CopiedFile>> extractZip(
    String uri,
    String directory,
    List<String> names,
    String jobId,
  );

  Future<void> cancel(String jobId);

  /// Bytes read so far, per job.
  Stream<({String jobId, int bytes})> get progress;
}

/// [ModelImportPlatform] backed by `MainActivity` (no storage permission).
class MethodChannelModelImportPlatform implements ModelImportPlatform {
  MethodChannelModelImportPlatform();

  static const MethodChannel _channel = MethodChannel('halo/model_import');
  static const EventChannel _events =
      EventChannel('halo/model_import/progress');

  late final Stream<({String jobId, int bytes})> _progress = _events
      .receiveBroadcastStream()
      .map((event) {
        final map = event as Map;
        return (
          jobId: map['jobId'] as String,
          bytes: (map['bytes'] as num).toInt(),
        );
      })
      .asBroadcastStream();

  @override
  Stream<({String jobId, int bytes})> get progress => _progress;

  @override
  Future<List<PickedDocument>> pick({required bool multiple}) async {
    final result = await _channel
        .invokeListMethod<Map<Object?, Object?>>('pick', {'multiple': multiple});
    return [
      for (final m in result ?? const <Map<Object?, Object?>>[])
        PickedDocument(
          uri: m['uri']! as String,
          name: m['name']! as String,
          size: (m['size'] as num?)?.toInt(),
        ),
    ];
  }

  @override
  Future<int> freeBytes(String directory) async =>
      (await _channel.invokeMethod<num>('freeBytes', {'path': directory}))!
          .toInt();

  @override
  Future<CopiedFile> copy(String uri, String destination, String jobId) =>
      _guard(() async {
        final m = (await _channel.invokeMapMethod<String, Object?>('copy', {
          'uri': uri,
          'dest': destination,
          'jobId': jobId,
        }))!;
        return _copied(m);
      });

  @override
  Future<Map<String, CopiedFile>> extractZip(
    String uri,
    String directory,
    List<String> names,
    String jobId,
  ) =>
      _guard(() async {
        final m = (await _channel.invokeMapMethod<String, Object?>(
          'extractZip',
          {'uri': uri, 'destDir': directory, 'names': names, 'jobId': jobId},
        ))!;
        return {
          for (final e in m.entries) e.key: _copied(e.value! as Map),
        };
      });

  @override
  Future<void> cancel(String jobId) =>
      _channel.invokeMethod<void>('cancel', {'jobId': jobId});

  static CopiedFile _copied(Map<Object?, Object?> m) => CopiedFile(
        bytes: (m['bytes']! as num).toInt(),
        sha256: m['sha256']! as String,
      );

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') throw const ImportCancelled();
      rethrow;
    }
  }
}
