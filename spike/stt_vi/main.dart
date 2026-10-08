// Vietnamese offline STT spike (sherpa-onnx + Zipformer-vi int8).
//
// NOT part of the app. Run on a device with:
//   flutter run -t spike/stt_vi/main.dart -d <serial> --release
// Model files must be pushed to
//   /sdcard/Android/data/dev.offlineai.offline_ai_chat/files/stt/<modelDir>/
// See docs/STT_SPIKE.md. Every result is logged to logcat as one `[STT]` line.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/llama_cpp_local_ai_service.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/llm_metrics.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'stt_worker.dart';
import 'text_metrics.dart';
import 'utterances.dart';

const String _modelDirName = 'sherpa-onnx-zipformer-vi-int8-2025-04-20';
const int _sampleRate = 16000;
const int _threads = int.fromEnvironment('STT_THREADS', defaultValue: 2);

void main() => runApp(const MaterialApp(home: SttSpikePage()));

/// Set once the model directory is known; every `[STT]` line is also
/// appended there, so results survive adb disconnects (airplane mode).
File? _logFile;

void _log(String event, Map<String, Object?> fields) {
  final body = fields.entries.map((e) => '${e.key}=${e.value}').join(' ');
  final line = '[STT] ${DateTime.now().toIso8601String()} $event $body';
  debugPrint(line);
  _logFile?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
}

class SttSpikePage extends StatefulWidget {
  const SttSpikePage({super.key});

  @override
  State<SttSpikePage> createState() => _SttSpikePageState();
}

class _SttSpikePageState extends State<SttSpikePage> {
  final AudioRecorder _recorder = AudioRecorder();
  SttWorker? _worker;
  LlamaCppLocalAiService? _llm;
  String? _modelDir;

  int? _recordingIndex;
  StreamSubscription<Uint8List>? _audio;
  BytesBuilder? _pcm;
  Completer<void>? _audioDone;

  bool _busy = false;
  String _status = 'Idle';
  final Map<int, String> _results = {};

  @override
  void dispose() {
    _audio?.cancel();
    _recorder.dispose();
    _worker?.dispose();
    _llm?.dispose();
    super.dispose();
  }

  Future<void> _run(String label, Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '$label…';
    });
    try {
      await task();
    } catch (error) {
      _log('error', {'step': label, 'error': '"$error"'});
      _status = 'ERROR in $label: $error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _findModelDir() async {
    final roots = [
      if (Platform.isAndroid) await getExternalStorageDirectory(),
      await getApplicationSupportDirectory(),
    ];
    for (final root in roots.whereType<Directory>()) {
      final dir = p.join(root.path, 'stt', _modelDirName);
      if (File(p.join(dir, 'tokens.txt')).existsSync()) return dir;
    }
    throw StateError('Model not found under <files>/stt/$_modelDirName');
  }

  Future<void> _loadStt() => _run('Load STT', () async {
        if (_worker != null) return;
        final before = LlmMetrics.residentMemoryMiB();
        _modelDir = await _findModelDir();
        _logFile = File(p.join(p.dirname(_modelDir!), 'spike_log.txt'));
        final wall = Stopwatch()..start();
        // STT_THREADS may be overridden at build time.
        // ignore: avoid_redundant_argument_values
        _worker = await SttWorker.spawn(_modelDir!, threads: _threads);
        final after = LlmMetrics.residentMemoryMiB();
        _log('stt_loaded', {
          'model': _modelDirName,
          'threads': _threads,
          'load_ms': _worker!.loadMs,
          'wall_ms': wall.elapsedMilliseconds,
          'rss_before_mib': before,
          'rss_after_mib': after,
        });
        _status = 'STT loaded in ${_worker!.loadMs} ms · RSS $before → $after MiB';
      });

  Future<void> _freeStt() => _run('Free STT', () async {
        await _worker?.dispose();
        _worker = null;
        // Give the allocator a moment before sampling.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final rss = LlmMetrics.residentMemoryMiB();
        _log('stt_freed', {'rss_mib': rss});
        _status = 'STT freed · RSS $rss MiB';
      });

  Future<void> _loadLlm() => _run('Load LLM', () async {
        _llm ??= LlamaCppLocalAiService();
        final before = LlmMetrics.residentMemoryMiB();
        await _llm!.initialize();
        final after = LlmMetrics.residentMemoryMiB();
        _log('llm_loaded_alongside', {
          'stt_loaded': _worker != null,
          'rss_before_mib': before,
          'rss_after_mib': after,
        });
        _status = 'LLM loaded · RSS $before → $after MiB';
      });

  Future<void> _referenceWavs() => _run('Reference WAVs', () async {
        final dir = Directory(p.join(_modelDir!, 'test_wavs'));
        final wavs = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.wav'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final wav in wavs) {
          final audioMs = ((wav.lengthSync() - 44) / 2 / _sampleRate * 1000).round();
          final r = await _worker!.transcribeFile(wav.path);
          _log('reference_wav', {
            'file': p.basename(wav.path),
            'audio_ms': audioMs,
            'decode_ms': r.decodeMs,
            'rtf': (r.decodeMs / audioMs).toStringAsFixed(3),
            'rss_mib': LlmMetrics.residentMemoryMiB(),
            'got': '"${r.text}"',
          });
        }
        _status = 'Reference WAVs done (${wavs.length}); see logcat';
      });

  Future<void> _startRecording(int index) async {
    if (_busy || _worker == null || _recordingIndex != null) return;
    if (!await _recorder.hasPermission()) {
      _log('permission_denied', const {});
      setState(() => _status = 'Microphone permission denied');
      return;
    }
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceRecognition,
        ),
      ),
    );
    // Audio is kept in memory only; it is dropped after transcription.
    _pcm = BytesBuilder(copy: false);
    _audioDone = Completer<void>();
    _audio = stream.listen(
      _pcm!.add,
      onDone: () => _audioDone?.complete(),
      onError: (Object e) => _audioDone?.completeError(e),
    );
    setState(() {
      _recordingIndex = index;
      _status = 'Recording #${index + 1}… tap Stop when done';
    });
  }

  Future<void> _stopRecording() async {
    final index = _recordingIndex;
    if (index == null) return;
    setState(() => _recordingIndex = null);
    await _run('Transcribe #${index + 1}', () async {
      final stopClock = Stopwatch()..start();
      await _recorder.stop();
      await _audioDone!.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      await _audio?.cancel();
      _audio = null;
      final bytes = _pcm!.takeBytes();
      _pcm = null;

      final samples = _pcm16ToFloat(bytes);
      final audioMs = samples.length * 1000 ~/ _sampleRate;
      final peak = samples.fold<double>(0, (m, s) => s.abs() > m ? s.abs() : m);
      final r = await _worker!.transcribe(samples);
      final stopToTextMs = stopClock.elapsedMilliseconds;

      final expected = kUtterances[index].text;
      final wer = TextMetrics.wer(expected, r.text);
      final cer = TextMetrics.cer(expected, r.text);
      _log('utterance', {
        'id': index + 1,
        'audio_ms': audioMs,
        'peak': peak.toStringAsFixed(3),
        'decode_ms': r.decodeMs,
        'stop_to_text_ms': stopToTextMs,
        'rtf': audioMs == 0 ? null : (r.decodeMs / audioMs).toStringAsFixed(3),
        'wer': wer.toStringAsFixed(3),
        'cer': cer.toStringAsFixed(3),
        'llm_loaded': _llm?.isReady ?? false,
        'rss_mib': LlmMetrics.residentMemoryMiB(),
        'expected': '"$expected"',
        'got': '"${r.text}"',
      });
      _results[index] = '${r.text}\n'
          'WER ${(wer * 100).toStringAsFixed(1)}% · CER ${(cer * 100).toStringAsFixed(1)}% · '
          'audio ${audioMs}ms · decode ${r.decodeMs}ms · stop→text ${stopToTextMs}ms';
      _status = '#${index + 1} done';
    });
  }

  static Float32List _pcm16ToFloat(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final out = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final ready = _worker != null && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('STT spike · vi')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(_status, key: const Key('status')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy || _worker != null ? null : _loadStt,
                child: const Text('Load STT'),
              ),
              OutlinedButton(
                onPressed: ready ? _referenceWavs : null,
                child: const Text('Reference WAVs'),
              ),
              OutlinedButton(
                onPressed: _busy || (_llm?.isReady ?? false) ? null : _loadLlm,
                child: const Text('Load LLM'),
              ),
              OutlinedButton(
                onPressed: ready ? _freeStt : null,
                child: const Text('Free STT'),
              ),
            ],
          ),
          const Divider(),
          for (var i = 0; i < kUtterances.length; i++)
            Card(
              child: ListTile(
                title: Text('#${i + 1} (${kUtterances[i].label}) ${kUtterances[i].text}'),
                subtitle: _results[i] == null ? null : Text(_results[i]!),
                trailing: _recordingIndex == i
                    ? FilledButton(
                        onPressed: _stopRecording,
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('Stop'),
                      )
                    : IconButton(
                        icon: const Icon(Icons.mic),
                        onPressed: ready && _recordingIndex == null
                            ? () => _startRecording(i)
                            : null,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
