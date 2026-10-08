import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/speech/domain/transcript_formatter.dart';

void main() {
  test('sentence-cases upper-case recognizer output', () {
    expect(
      TranscriptFormatter.format('HÔM NAY TRỜI ĐẸP QUÁ'),
      'Hôm nay trời đẹp quá',
    );
  });

  test('preserves every Vietnamese diacritic and đ', () {
    expect(
      TranscriptFormatter.format(
        'ĐƯỢC KHÔNG BỮA SÁNG LÀNH MẠNH Ở NGOẠI THÀNH HÀ NỘI ỨNG ỬA ỰC',
      ),
      'Được không bữa sáng lành mạnh ở ngoại thành hà nội ứng ửa ực',
    );
  });

  test('capitalises a first letter that carries a tone mark', () {
    expect(TranscriptFormatter.format('Ừ'), 'Ừ');
    expect(TranscriptFormatter.format('ỪM ĐƯỢC'), 'Ừm được');
  });

  test('adds no punctuation and collapses whitespace', () {
    expect(TranscriptFormatter.format('  XIN   CHÀO  '), 'Xin chào');
  });

  test('leaves already mixed-case text untouched', () {
    expect(TranscriptFormatter.format('Hà Nội đẹp'), 'Hà Nội đẹp');
  });

  test('empty and caseless input', () {
    expect(TranscriptFormatter.format('   '), '');
    expect(TranscriptFormatter.format('2026'), '2026');
  });
}
