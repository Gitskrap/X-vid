import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xflow/core/database/repository.dart';
import 'package:xflow/core/models/local_video_reaction.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/feed/local_recommendation_profile.dart';

Tweet clip(String caption) => Tweet(
  id: '1900000000000000910',
  text: caption,
  userHandle: '@subscribed',
  isVideo: true,
  mediaUrls: const ['https://video.twimg.com/clip.mp4'],
);

LocalVideoReaction opinion(int value, String caption) =>
    LocalVideoReaction(
      videoId: value == 1 ? 'liked' : 'disliked',
      value: value,
      caption: caption,
      author: '@subscribed',
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('saved hashtags influence personalized discovery, regardless of case',
      () {
    final topics = personalizedVideoTopics(
      [clip('#football #basketball highlights')],
      {},
      followedHashtags: [' #Babyfoot ', '#F1', '#Babyfoot', ''],
    );
    expect(topics.first, 'babyfoot');
    expect(topics, contains('f1'));
  });

  test('local likes and followed hashtags are stronger than passive follows',
      () {
    final topics = personalizedVideoTopics(
      [clip('#football #basketball highlights')],
      {'like': opinion(1, '#Cyclisme tour de France')},
      followedHashtags: ['#Babyfoot'],
    );
    expect(topics.first, 'cyclisme');
    expect(topics, contains('babyfoot'));
  });

  test('disliked hashtags do not seed recommendations even when followed',
      () {
    final topics = personalizedVideoTopics(
      [],
      {'dislike': opinion(-1, '#Horror film')},
      followedHashtags: ['#Horror', '#Nature'],
    );
    expect(topics, contains('nature'));
    expect(topics, isNot(contains('horror')));
  });

  test('removing a followed hashtag removes its recommendation signal', () {
    final withFollow = personalizedVideoTopics(
      [], {}, followedHashtags: ['#Babyfoot'],
    );
    final withoutFollow = personalizedVideoTopics(
      [], {}, followedHashtags: [],
    );
    expect(withFollow, ['babyfoot']);
    expect(withoutFollow, isEmpty);
  });

  test('hashtags survive app database reads and can be removed', () async {
    final db = await Repository.database;
    await db.delete(tableHashtags);

    await Repository.addHashtag('#babyfoot');
    var saved = await Repository.getHashtags();
    expect(saved, ['#babyfoot']);
    expect(personalizedVideoTopics([], {}, followedHashtags: saved),
        ['babyfoot']);

    await Repository.deleteHashtag('#babyfoot');
    saved = await Repository.getHashtags();
    expect(saved, isEmpty);
    expect(personalizedVideoTopics([], {}, followedHashtags: saved), isEmpty);
  });
}
