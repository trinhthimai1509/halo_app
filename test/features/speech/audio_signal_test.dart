import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/speech/data/audio/audio_signal.dart';

const int _rate = 16000;

/// [ms] of a 220 Hz tone at [amplitude] (0 = digital silence).
Float32List _tone(int ms, double amplitude) {
  final out = Float32List(_rate * ms ~/ 1000);
  for (var i = 0; i < out.length; i++) {
    out[i] = amplitude * math.sin(2 * math.pi * 220 * i / _rate);
  }
  return out;
}

Float32List _concat(List<Float32List> parts) =>
    Float32List.fromList([for (final p in parts) ...p]);

void main() {
  test('pcm16ToFloat32 decodes little-endian samples', () {
    final bytes = Uint8List.fromList([0x00, 0x40, 0x00, 0xC0, 0xFF, 0x7F]);
    final samples = AudioSignal.pcm16ToFloat32(bytes);
    expect(samples[0], 0.5);
    expect(samples[1], -0.5);
    expect(samples[2], closeTo(1.0, 1e-4));
  });

  test('pure silence and low noise are rejected', () {
    expect(AudioSignal.trimSilence(_tone(2000, 0), sampleRate: _rate), isNull);
    expect(
      AudioSignal.trimSilence(_tone(2000, 0.005), sampleRate: _rate),
      isNull,
    );
  });

  test('a very short click is not speech', () {
    final audio = _concat([_tone(1000, 0), _tone(60, 0.3), _tone(1000, 0)]);
    expect(AudioSignal.trimSilence(audio, sampleRate: _rate), isNull);
  });

  test('trims long silence around speech but keeps padding', () {
    final audio = _concat([_tone(5000, 0), _tone(1200, 0.2), _tone(5000, 0)]);
    final speech = AudioSignal.trimSilence(audio, sampleRate: _rate)!;
    final ms = speech.length * 1000 ~/ _rate;
    // 1.2 s of speech + up to 300 ms padding on each side (frame-aligned).
    expect(ms, inInclusiveRange(1200, 1860));
  });

  test('quiet speech (peak 0.09, like the spike\'s longest take) is kept', () {
    final speech =
        AudioSignal.trimSilence(_tone(3000, 0.09), sampleRate: _rate);
    expect(speech, isNotNull);
  });

  test('peak reports clipping', () {
    expect(AudioSignal.peak(Float32List.fromList([0.1, -1.0, 0.5])), 1.0);
  });
}
