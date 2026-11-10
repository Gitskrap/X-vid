import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/features/player/widgets/video_seek_bar.dart';

void main() {
  test('formats short playback times using minutes and seconds', () {
    expect(formatVideoTime(Duration.zero), '0:00');
    expect(formatVideoTime(const Duration(seconds: 9)), '0:09');
    expect(formatVideoTime(const Duration(minutes: 5, seconds: 7)), '5:07');
    expect(formatVideoTime(const Duration(minutes: 42)), '42:00');
  });

  test('formats long videos including hours', () {
    expect(
      formatVideoTime(const Duration(hours: 1, minutes: 3, seconds: 8)),
      '1:03:08',
    );
    expect(formatVideoTime(const Duration(seconds: -1)), '0:00');
  });
}
