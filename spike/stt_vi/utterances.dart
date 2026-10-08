/// Fixed Vietnamese test sentences, read aloud by a person during the spike.
/// Chat-style requests of increasing length; numbers are written as words
/// because that is how they are spoken (and how the model writes them).
class Utterance {
  const Utterance(this.label, this.text);
  final String label;
  final String text;
}

const List<Utterance> kUtterances = [
  Utterance('very short', 'Xin chào'),
  Utterance('short', 'Hôm nay trời đẹp quá'),
  Utterance('medium', 'Bạn có thể giúp tôi viết một email xin nghỉ phép không'),
  Utterance(
    'medium',
    'Giải thích cho tôi trí tuệ nhân tạo là gì bằng ngôn ngữ đơn giản',
  ),
  Utterance(
    'medium, numbers',
    'Hẹn gặp bạn lúc ba giờ chiều thứ năm tuần sau ở quán cà phê gần nhà',
  ),
  Utterance(
    'long',
    'Tôi muốn nấu một bữa sáng nhanh và lành mạnh cho gia đình bốn người, '
        'bạn gợi ý giúp tôi vài món được không',
  ),
  Utterance(
    'very long',
    'Cuối tuần này tôi định đưa các con đi dã ngoại ở ngoại thành Hà Nội, '
        'hãy lập giúp tôi danh sách những đồ cần mang theo và những lưu ý '
        'về thời tiết',
  ),
];
