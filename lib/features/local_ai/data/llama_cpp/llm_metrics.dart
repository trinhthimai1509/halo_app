import 'dart:io';

import 'package:flutter/foundation.dart';

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

  /// Resident memory of this process in MiB, from `/proc/self/status`
  /// (Linux/Android only). Null where unavailable.
  static int? residentMemoryMiB() {
    try {
      final status = File('/proc/self/status').readAsLinesSync();
      final line = status.firstWhere((l) => l.startsWith('VmRSS:'));
      final kib = int.parse(line.replaceAll(RegExp(r'[^0-9]'), ''));
      return kib ~/ 1024;
    } catch (_) {
      return null;
    }
  }
}
