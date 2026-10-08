import 'package:flutter/foundation.dart';

import '../../../core/utils/process_memory.dart';

/// Development instrumentation for speech recognition: one `[STT]` line per
/// event in the platform log. Never contains audio. On by default in
/// debug/profile builds; off in release unless built with
/// `--dart-define=LLM_METRICS=true` (one switch for all on-device AI
/// metrics), so a shipped build never logs what the user said.
abstract final class SttMetrics {
  static const bool enabled =
      bool.fromEnvironment('LLM_METRICS', defaultValue: !kReleaseMode);

  static void log(String event, Map<String, Object?> fields) {
    if (!enabled) return;
    final body = fields.entries.map((e) => '${e.key}=${e.value}').join(' ');
    debugPrint('[STT] $event $body rss_mib=${residentMemoryMiB()}');
  }
}
