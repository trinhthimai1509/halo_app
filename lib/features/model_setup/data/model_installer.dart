import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../domain/model_package.dart';
import 'model_import_platform.dart';

/// Why an import did not complete.
enum ImportFailure {
  /// Another import is running.
  busy,

  /// The picked file is not the expected model (name or size).
  wrongFile,

  /// A multi-file package was picked without all required files.
  missingFiles,

  /// Not enough free space for the model.
  insufficientStorage,

  /// Size or SHA-256 differs after copying (damaged or different file).
  verificationFailed,

  /// Reading or writing failed.
  ioError,
}

sealed class ImportOutcome {
  const ImportOutcome();
}

final class ImportSucceeded extends ImportOutcome {
  const ImportSucceeded(this.elapsed);
  final Duration elapsed;
}

/// The user closed the file picker without choosing anything.
final class ImportDismissed extends ImportOutcome {
  const ImportDismissed();
}

final class ImportCancelledByUser extends ImportOutcome {
  const ImportCancelledByUser();
}

final class ImportFailed extends ImportOutcome {
  const ImportFailed(this.reason, {this.detail, this.requiredBytes, this.freeBytes});
  final ImportFailure reason;

  /// Technical detail for logs / the error text (never a device path).
  final String? detail;
  final int? requiredBytes;
  final int? freeBytes;
}

/// Installs model packages into app-private storage from user-picked files.
///
/// Guarantees:
/// - Streaming only (the platform copies in 1 MiB blocks); nothing is held
///   in memory.
/// - Files are written to a staging folder, verified (size + SHA-256), and
///   only then promoted with `rename` (atomic on the same volume). A failed,
///   cancelled or interrupted import never touches the installed model.
/// - [recover] (call at start-up) removes staging leftovers and finishes or
///   rolls back an interrupted folder swap.
class ModelInstaller {
  ModelInstaller({
    required this._platform,
    required this._privateRoot,
    this._developerRoot,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ModelImportPlatform _platform;
  final Future<String> Function() _privateRoot;
  final Future<String?> Function()? _developerRoot;
  final DateTime Function() _clock;

  /// Extra free space kept on top of the model size (file-system slack).
  static const int safetyMarginBytes = 64 << 20;

  static const String _stagingRoot = '.import';

  String? _activeJob;
  bool _cancelRequested = false;

  bool get isBusy => _activeJob != null;

  // ---------------------------------------------------------------- status

  Future<ModelStatus> status(ModelPackage package) async {
    final private = await _privateRoot();
    final imported = await _check(p.join(private, package.installDir), package);
    if (imported != ModelState.missing) {
      return ModelStatus(imported, source: ModelSource.imported);
    }
    final dev = await _developerRoot?.call();
    if (dev != null) {
      final developer = await _check(p.join(dev, package.installDir), package);
      if (developer != ModelState.missing) {
        return ModelStatus(developer, source: ModelSource.developer);
      }
    }
    return const ModelStatus.missing();
  }

  Future<ModelState> _check(String dir, ModelPackage package) async {
    var present = 0;
    var valid = true;
    for (final spec in package.files) {
      final file = File(p.join(dir, spec.name));
      if (!await file.exists()) {
        valid = false;
        continue;
      }
      present++;
      if (await file.length() != spec.bytes) valid = false;
    }
    if (present == 0) return ModelState.missing;
    return valid ? ModelState.installed : ModelState.invalid;
  }

  // ---------------------------------------------------------------- import

  /// Lets the user pick the files for [package] and installs them.
  /// [onProgress] receives 0..1 while copying.
  Future<ImportOutcome> import(
    ModelPackage package, {
    void Function(double fraction)? onProgress,
  }) async {
    if (_activeJob != null) return const ImportFailed(ImportFailure.busy);
    final job = '${package.id}-${_clock().microsecondsSinceEpoch}';
    _activeJob = job;
    _cancelRequested = false;
    final started = Stopwatch()..start();
    StreamSubscription<({String jobId, int bytes})>? progress;
    String? staging;
    try {
      final picked = await _platform.pick(multiple: package.isMultiFile);
      if (picked.isEmpty) return const ImportDismissed();

      final plan = _plan(package, picked);
      if (plan is ImportFailed) return plan;
      plan as _Plan;

      final root = await _privateRoot();
      final need = package.totalBytes + safetyMarginBytes;
      final free = await _platform.freeBytes(root);
      if (free < need) {
        return ImportFailed(
          ImportFailure.insufficientStorage,
          requiredBytes: need,
          freeBytes: free,
        );
      }

      staging = p.join(root, _stagingRoot, '${package.id}.staging');
      await _deleteIfExists(staging);
      await Directory(staging).create(recursive: true);

      final copied = <String, CopiedFile>{};
      if (plan.zip != null) {
        final total = plan.zip!.size ?? package.totalBytes;
        progress = _platform.progress
            .where((e) => e.jobId == job)
            .listen((e) => onProgress?.call((e.bytes / total).clamp(0, 1)));
        copied.addAll(await _platform.extractZip(
          plan.zip!.uri,
          staging,
          [for (final f in package.files) f.name],
          job,
        ));
      } else {
        var done = 0;
        progress = _platform.progress.where((e) => e.jobId == job).listen(
              (e) => onProgress
                  ?.call(((done + e.bytes) / package.totalBytes).clamp(0, 1)),
            );
        for (final spec in package.files) {
          if (_cancelRequested) throw const ImportCancelled();
          copied[spec.name] = await _platform.copy(
            plan.files[spec.name]!.uri,
            p.join(staging, spec.name),
            job,
          );
          done += spec.bytes;
        }
      }

      for (final spec in package.files) {
        final got = copied[spec.name];
        if (got == null) {
          return ImportFailed(ImportFailure.missingFiles, detail: spec.name);
        }
        if (got.bytes != spec.bytes || got.sha256 != spec.sha256) {
          return ImportFailed(
            ImportFailure.verificationFailed,
            detail: spec.name,
          );
        }
      }

      if (_cancelRequested) throw const ImportCancelled();
      await _promote(root, staging, package);
      onProgress?.call(1);
      return ImportSucceeded(started.elapsed);
    } on ImportCancelled {
      return const ImportCancelledByUser();
    } catch (error) {
      return ImportFailed(ImportFailure.ioError, detail: '$error');
    } finally {
      await progress?.cancel();
      if (staging != null) await _deleteIfExists(staging);
      _activeJob = null;
    }
  }

  /// Cancels the running import, if any. The installed model is unchanged.
  Future<void> cancel() async {
    final job = _activeJob;
    if (job == null) return;
    _cancelRequested = true;
    await _platform.cancel(job);
  }

  Object _plan(ModelPackage package, List<PickedDocument> picked) {
    if (package.acceptsZip &&
        picked.length == 1 &&
        picked.single.name.toLowerCase().endsWith('.zip')) {
      return _Plan(zip: picked.single);
    }
    if (!package.isMultiFile) {
      if (picked.length != 1) {
        return const ImportFailed(ImportFailure.wrongFile);
      }
      final spec = package.files.single;
      final doc = picked.single;
      if (doc.size != null && doc.size != spec.bytes) {
        return ImportFailed(ImportFailure.wrongFile, detail: doc.name);
      }
      return _Plan(files: {spec.name: doc});
    }
    final byName = {for (final d in picked) d.name: d};
    final missing = [
      for (final f in package.files)
        if (!byName.containsKey(f.name)) f.name,
    ];
    if (missing.isNotEmpty) {
      return ImportFailed(ImportFailure.missingFiles, detail: missing.join(', '));
    }
    for (final f in package.files) {
      final size = byName[f.name]!.size;
      if (size != null && size != f.bytes) {
        return ImportFailed(ImportFailure.wrongFile, detail: f.name);
      }
    }
    return _Plan(files: {for (final f in package.files) f.name: byName[f.name]!});
  }

  /// Moves verified files into place. Single-file packages replace the file
  /// atomically. Multi-file packages swap whole folders via `<id>.old`,
  /// which [recover] completes or rolls back after a crash.
  Future<void> _promote(String root, String staging, ModelPackage package) async {
    final target = p.join(root, package.installDir);
    if (!package.isMultiFile) {
      await Directory(target).create(recursive: true);
      final name = package.files.single.name;
      await File(p.join(staging, name)).rename(p.join(target, name));
      return;
    }
    final old = p.join(root, _stagingRoot, '${package.id}.old');
    await _deleteIfExists(old);
    await Directory(p.dirname(target)).create(recursive: true);
    if (await Directory(target).exists()) {
      await Directory(target).rename(old);
    }
    await Directory(staging).rename(target);
    await _deleteIfExists(old);
  }

  // -------------------------------------------------------------- recovery

  /// Cleans up after an import that was interrupted (app killed, crash,
  /// power loss): staging files are deleted, and a half-finished folder
  /// swap is rolled back to the previous model.
  Future<void> recover(List<ModelPackage> packages) async {
    final root = await _privateRoot();
    final dir = Directory(p.join(root, _stagingRoot));
    if (!await dir.exists()) return;
    for (final package in packages) {
      final old = Directory(p.join(dir.path, '${package.id}.old'));
      if (!await old.exists()) continue;
      final target = Directory(p.join(root, package.installDir));
      if (!await target.exists()) {
        // The swap was interrupted: roll back to the previous model.
        await target.parent.create(recursive: true);
        await old.rename(target.path);
      } else {
        await old.delete(recursive: true); // swap had finished
      }
    }
    await for (final entry in dir.list()) {
      if (entry.path.endsWith('.staging')) {
        await entry.delete(recursive: true);
      }
    }
  }

  static Future<void> _deleteIfExists(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) return;
    await (type == FileSystemEntityType.directory
            ? Directory(path)
            : File(path) as FileSystemEntity)
        .delete(recursive: true);
  }
}

@immutable
class _Plan {
  const _Plan({this.zip, this.files = const {}});

  final PickedDocument? zip;
  final Map<String, PickedDocument> files;
}
