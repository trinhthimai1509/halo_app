import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../local_ai/data/llama_cpp/llm_metrics.dart';
import '../data/model_catalog.dart';
import '../data/model_installer.dart';
import '../domain/model_package.dart';

@immutable
class ModelEntryState {
  const ModelEntryState({
    this.status,
    this.importing = false,
    this.progress,
    this.message,
    this.isError = false,
  });

  /// Null while the status is being checked.
  final ModelStatus? status;
  final bool importing;

  /// 0..1 while copying.
  final double? progress;

  /// Result of the last action (error or confirmation).
  final String? message;
  final bool isError;

  ModelEntryState copyWith({
    ModelStatus? status,
    bool? importing,
    ValueGetter<double?>? progress,
    ValueGetter<String?>? message,
    bool? isError,
  }) =>
      ModelEntryState(
        status: status ?? this.status,
        importing: importing ?? this.importing,
        progress: progress != null ? progress() : this.progress,
        message: message != null ? message() : this.message,
        isError: isError ?? this.isError,
      );
}

/// Status and import actions for every model package (Model Setup screen).
final modelSetupControllerProvider =
    NotifierProvider<ModelSetupController, Map<String, ModelEntryState>>(
  ModelSetupController.new,
);

/// Whether every model needed for chat and voice is installed. Read once
/// at start-up to open Model Setup for a first-time user.
final modelsReadyProvider = FutureProvider<bool>((ref) async {
  final installer = ref.watch(modelInstallerProvider);
  for (final package in ModelCatalog.all) {
    if (!(await installer.status(package)).isReady) return false;
  }
  return true;
});

class ModelSetupController extends Notifier<Map<String, ModelEntryState>> {
  ModelInstaller get _installer => ref.read(modelInstallerProvider);

  @override
  Map<String, ModelEntryState> build() {
    Future.microtask(refresh);
    return {for (final p in ModelCatalog.all) p.id: const ModelEntryState()};
  }

  Future<void> refresh() async {
    for (final package in ModelCatalog.all) {
      final status = await _installer.status(package);
      if (!ref.mounted) return;
      _update(package, (e) => e.copyWith(status: status));
    }
  }

  Future<void> import(ModelPackage package) async {
    if (_installer.isBusy) return;
    _update(
      package,
      (e) => e.copyWith(
        importing: true,
        progress: () => null,
        message: () => null,
        isError: false,
      ),
    );
    final outcome = await _installer.import(
      package,
      onProgress: (f) {
        if (ref.mounted) _update(package, (e) => e.copyWith(progress: () => f));
      },
    );
    _logOutcome(package, outcome);
    if (!ref.mounted) return;
    final (message, isError) = _describe(package, outcome);
    final status = await _installer.status(package);
    if (!ref.mounted) return;
    _update(
      package,
      (e) => ModelEntryState(status: status, message: message, isError: isError),
    );
    if (outcome is ImportSucceeded) {
      // Load the new files on next use; nothing else is reset.
      ref
        ..invalidate(localAiServiceProvider)
        ..invalidate(speechToTextServiceProvider)
        ..invalidate(modelsReadyProvider);
    }
  }

  Future<void> cancel() => _installer.cancel();

  /// Development metrics (same switch as the `[LLM]` lines): import time and
  /// outcome, never file paths or names chosen by the user.
  static void _logOutcome(ModelPackage package, ImportOutcome outcome) {
    if (!LlmMetrics.enabled) return;
    final fields = switch (outcome) {
      ImportSucceeded(:final elapsed) =>
        'result=ok ms=${elapsed.inMilliseconds} bytes=${package.totalBytes}',
      ImportFailed(:final reason) => 'result=failed reason=${reason.name}',
      ImportCancelledByUser() => 'result=cancelled',
      ImportDismissed() => 'result=dismissed',
    };
    debugPrint('[MODEL] import package=${package.id} $fields');
  }

  void _update(
    ModelPackage package,
    ModelEntryState Function(ModelEntryState) change,
  ) {
    state = {...state, package.id: change(state[package.id]!)};
  }

  static (String?, bool) _describe(ModelPackage package, ImportOutcome o) =>
      switch (o) {
        ImportSucceeded() => (AppStrings.importDone, false),
        ImportDismissed() => (null, false),
        ImportCancelledByUser() => (AppStrings.importCancelled, false),
        ImportFailed(:final reason, :final requiredBytes, :final freeBytes) =>
          (
            switch (reason) {
              ImportFailure.busy => AppStrings.importBusy,
              ImportFailure.wrongFile => package.isMultiFile
                  ? AppStrings.importWrongSpeechFile
                  : AppStrings.importWrongLlmFile,
              ImportFailure.missingFiles => AppStrings.importMissingSpeechFiles,
              ImportFailure.insufficientStorage => AppStrings.importNoSpace(
                  formatBytes(requiredBytes ?? package.totalBytes),
                  formatBytes(freeBytes ?? 0),
                ),
              ImportFailure.verificationFailed => AppStrings.importCorrupt,
              ImportFailure.ioError => AppStrings.importIoError,
            },
            true,
          ),
      };
}

/// `1.2 GB`, `77 MB`.
String formatBytes(int bytes) {
  const gb = 1000 * 1000 * 1000;
  const mb = 1000 * 1000;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  return '${(bytes / mb).round()} MB';
}
