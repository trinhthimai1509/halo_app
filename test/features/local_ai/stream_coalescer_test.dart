import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/local_ai/data/stream_coalescer.dart';

void main() {
  test('emits the first piece immediately, then batches by interval', () {
    fakeAsync((async) {
      final emitted = <String>[];
      final coalescer = StreamCoalescer(onEmit: emitted.add);

      coalescer.add('Xin');
      expect(emitted, ['Xin']);

      for (final piece in [' ch', 'ào', ',', ' b', 'ạn']) {
        coalescer.add(piece);
        async.elapse(const Duration(milliseconds: 5));
      }
      expect(emitted, ['Xin']);

      async.elapse(const Duration(milliseconds: 50));
      expect(emitted, ['Xin', ' chào, bạn']);
    });
  });

  test('flush emits pending text; dispose drops it', () {
    fakeAsync((async) {
      final emitted = <String>[];
      final coalescer = StreamCoalescer(onEmit: emitted.add)
        ..add('a')
        ..add('b')
        ..flush();
      expect(emitted, ['a', 'b']);

      coalescer
        ..add('c')
        ..dispose();
      async.elapse(const Duration(seconds: 1));
      expect(emitted, ['a', 'b']);
    });
  });
}
