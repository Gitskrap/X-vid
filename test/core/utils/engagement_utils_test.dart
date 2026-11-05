import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/core/utils/engagement_utils.dart';
import 'package:xflow/core/models/tweet.dart';

void main() {
  test('zero is a known metric while null is unknown', () {
    expect(readXCount(0), 0);
    expect(readXCount('0'), 0);
    expect(readXCount(null), isNull);
    expect(readXCount('invalid'), isNull);
    expect(readXCount(-1), isNull);
    expect(readXCount(15.5), isNull);
    expect(readXCount('32 000'), isNull);
    expect(readXCount('32000'), 32000);
  });

  test('copyWith keeps known engagement and like state', () {
    final tweet = Tweet(
      id: '1829000000000000000',
      text: 'Exemple',
      userHandle: '@example',
      mediaUrls: const ['https://video.twimg.com/example.mp4'],
      favoriteCount: 120,
      replyCount: 34,
      isLiked: true,
      favoriteCountKnown: true,
      replyCountKnown: true,
      isLikedKnown: true,
    );
    final copy = tweet.copyWith(source: 'Cache');
    expect(copy.favoriteCount, 120);
    expect(copy.replyCount, 34);
    expect(copy.isLiked, isTrue);
    expect(copy.favoriteCountKnown, isTrue);
    expect(copy.replyCountKnown, isTrue);
    expect(copy.isLikedKnown, isTrue);
  });
}
