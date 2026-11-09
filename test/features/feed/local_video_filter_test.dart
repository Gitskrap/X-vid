import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/core/database/entities.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/feed/local_video_filter.dart';

void main() {
  Tweet video(String author) => Tweet(
    id: '${author.hashCode.abs()}',
    text: 'Clip',
    userHandle: author,
    mediaUrls: const ['https://video.twimg.com/demo.mp4'],
    isVideo: true,
  );

  test('home feed uses only locally subscribed authors, case-insensitively', () {
    final allowed = localVideoHandles([
      Subscription(id: 'local_1', screenName: 'NASA', name: 'NASA'),
      Subscription(id: 'local_2', screenName: 'Test_User', name: 'Test'),
    ]);
    final videos = onlyLocalSubscriptionVideos(
      [video('@nasa'), video('@SomeoneElse'), video('@TEST_user')],
      allowed,
    );
    expect(videos.map((t) => t.userHandle).toList(),
        ['@nasa', '@TEST_user']);
  });

  test('empty local list never falls back to X followed accounts', () {
    expect(onlyLocalSubscriptionVideos([video('@NASA')], <String>{}), isEmpty);
  });

  test('non-videos from subscribed authors are not displayed', () {
    final photo = Tweet(
      id: '400', text: 'Photo', userHandle: '@nasa',
      mediaUrls: const ['https://pbs.twimg.com/photo.jpg'],
    );
    expect(onlyLocalSubscriptionVideos([photo], {'nasa'}), isEmpty);
  });
}
