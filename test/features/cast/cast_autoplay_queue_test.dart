import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/cast/cast_autoplay_queue.dart';

Tweet video(String id, {int? lengthMs = 40000, bool video = true}) => Tweet(
  id: id,
  text: '#nature',
  userHandle: '@author',
  isVideo: video,
  durationMs: lengthMs,
  mediaUrls: const ['https://video.twimg.com/a.mp4'],
);

void main() {
  test('finished cast picks the next video in order', () {
    final queue = [video('a'), video('b'), video('c')];
    expect(nextCastVideo('a', queue, {'a'})?.id, 'b');
    expect(nextCastVideo('b', queue, {'a','b'})?.id, 'c');
  });

  test('does not loop the same video after end of playlist', () {
    final queue = [video('a'), video('b')];
    expect(nextCastVideo('b', queue, {'a','b'}), isNull);
  });

  test('skips previously cast and known short videos', () {
    final queue = [
      video('a'), video('short', lengthMs: 15000),
      video('seen'), video('fresh'), video('later'),
    ];
    expect(nextCastVideo('a', queue, {'a','seen'})?.id, 'fresh');
  });

  test('ignores non-video entries and missing current item', () {
    expect(nextCastVideo('a', [video('a'), video('image', video:false)], {'a'}),
      isNull);
    expect(nextCastVideo('unknown', [video('a')], {}), isNull);
  });
}
