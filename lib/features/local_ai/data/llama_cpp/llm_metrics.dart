import 'package:flutter/foundation.dart';

import '../../../../core/utils/process_memory.dart' as process_memory;

/// Development instrumentation for local inference. Writes one `[LLM]` line
/// per event to the platform log (logcat on Android); nothing is stored or
/// sent anywhere.
///
/// Enabled in debug/profile builds, and in release builds with
/// `--dart-define=LLM_METRICS=true`.
abstract final class LlmMetrics {
  static const bool enabled =
      bool.fromEnvironment('LLM_METRICS', defaultValue: !kReleaseMode);

  static void log(String event, Map<String, Object?> fields) {
    if (!enabled) return;
    final body = fields.entries.map((e) => '${e.key}=${e.value}').join(' ');
    debugPrint('[LLM] $event $body');
  }

  /// Resident memory of this process in MiB; null where unavailable.
  static int? residentMemoryMiB() => process_memory.residentMemoryMiB();
}
