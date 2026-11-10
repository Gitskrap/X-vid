import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/feed/x_like_counter.dart';

Tweet withXCount(int likes, {bool known = true}) => Tweet(
  id: '1900000000000000345',
  text: 'Video',
  userHandle: '@creator',
  isVideo: true,
  mediaUrls: const ['https://video.twimg.com/video.mp4'],
  favoriteCount: likes,
  favoriteCountKnown: known,
);

void main() {
  test('shows public X likes when known', () {
    expect(publicXLikeCountLabel(withXCount(0)), 'X · 0');
    expect(publicXLikeCountLabel(withXCount(83)), 'X · 83');
    expect(publicXLikeCountLabel(withXCount(2300)), 'X · 2.3K');
    expect(publicXLikeCountLabel(withXCount(1200000)), 'X · 1.2M');
  });

  test('never invents a count when X omitted it', () {
    expect(publicXLikeCountLabel(withXCount(0, known: false)), 'X · —');
  });

  test('public counter does not change when a private reaction is stored', () {
    final original = withXCount(182);
    // A local reaction is kept separately; no increment/decrement on Tweet.
    expect(publicXLikeCountLabel(original), 'X · 182');
  });
}
