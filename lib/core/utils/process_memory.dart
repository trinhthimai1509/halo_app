import 'dart:io';

/// Resident memory of this process in MiB, from `/proc/self/status`
/// (Linux/Android only). Null where unavailable. Development metrics only.
int? residentMemoryMiB() {
  try {
    final status = File('/proc/self/status').readAsLinesSync();
    final line = status.firstWhere((l) => l.startsWith('VmRSS:'));
    final kib = int.parse(line.replaceAll(RegExp(r'[^0-9]'), ''));
    return kib ~/ 1024;
  } catch (_) {
    return null;
  }
}
