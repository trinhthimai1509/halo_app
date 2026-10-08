import 'dart:math' as math;
import 'dart:typed_data';

/// Pure signal helpers for recorded speech.
abstract final class AudioSignal {
  /// Frame length used for energy analysis.
  static const Duration frame = Duration(milliseconds: 30);

  /// RMS level (full scale = 1.0) above which a frame counts as speech.
  /// About −42 dBFS: quiet speech in the spike measured well above this,
  /// while a silent room on the tablet microphone stays below it.
  static const double speechRms = 0.008;

  /// Audio kept before the first and after the last speech frame, so soft
  /// onsets and endings are not clipped.
  static const Duration padding = Duration(milliseconds: 300);

  /// Shorter speech than this is treated as noise (a click or a breath).
  static const Duration minSpeech = Duration(milliseconds: 150);

  /// 16-bit little-endian PCM to floats in [-1, 1).
  static Float32List pcm16ToFloat32(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final out = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  /// Largest absolute sample value (1.0 means the input clipped).
  static double peak(Float32List samples) {
    var max = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > max) max = a;
    }
    return max;
  }

  /// Removes leading and trailing silence. Returns null when the recording
  /// contains no speech at all (or less than [minSpeech]).
  static Float32List? trimSilence(
    Float32List samples, {
    required int sampleRate,
  }) {
    final frameLength = sampleRate * frame.inMilliseconds ~/ 1000;
    if (frameLength == 0 || samples.length < frameLength) return null;
    final frames = samples.length ~/ frameLength;

    int? first;
    int? last;
    for (var f = 0; f < frames; f++) {
      if (_rms(samples, f * frameLength, frameLength) >= speechRms) {
        first ??= f;
        last = f;
      }
    }
    if (first == null || last == null) return null;

    final speechMs = (last - first + 1) * frame.inMilliseconds;
    if (speechMs < minSpeech.inMilliseconds) return null;

    final pad = sampleRate * padding.inMilliseconds ~/ 1000;
    final start = math.max(0, first * frameLength - pad);
    final end = math.min(samples.length, (last + 1) * frameLength + pad);
    return Float32List.sublistView(samples, start, end);
  }

  static double _rms(Float32List samples, int offset, int length) {
    var sum = 0.0;
    for (var i = offset; i < offset + length; i++) {
      sum += samples[i] * samples[i];
    }
    return math.sqrt(sum / length);
  }
}
