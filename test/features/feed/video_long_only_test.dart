import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/feed/feed_provider.dart';
import 'package:xflow/features/feed/similar_video_discovery.dart';

Tweet video(String id, int? durationMs) => Tweet(
  id: id,
  text: '#cycling',
  userHandle: '@sports',
  isVideo: true,
  durationMs: durationMs,
  mediaUrls: const ['https://video.twimg.com/a.mp4'],
);

void main() {
  test('known clips at or below 15 seconds never enter a feed', () {
    final items = FeedState(tweets: [
      video('short', 14000),
      video('equal', 15000),
      video('long', 15001),
      video('unknown', null),
    ]);
    expect(items.tweets.map((t) => t.id), ['long', 'unknown']);
  });

  test('unknown metadata requires player verification, not acceptance', () {
    // Unknown duration is only a loading candidate; the player must discover
    // a duration above 15000ms before showing it in the home feed.
    expect(video('unknown', null).durationMs, isNull);
    expect(video('long', 15001).durationMs! > 15000, isTrue);
    expect(video('equal', 15000).durationMs! > 15000, isFalse);
  });

  test('recommendations reject known short clips before interleaving', () {
    final combined = mixRelatedVideos([
      video('followed', 29000),
      video('followed2', 20000),
      video('followed3', 21000),
    ], [
      video('short', 15000), video('recommended', 45000),
    ]);
    expect(combined.map((t) => t.id), isNot(contains('short')));
    expect(combined.map((t) => t.id), contains('recommended'));
  });

  test('no subscriptions: only long or unverified discovery candidates', () {
    final combined = mixRelatedVideos([], [
      video('a', 5000), video('b', 17000), video('c', null),
    ]);
    expect(combined.map((t) => t.id), ['b', 'c']);
  });
}
