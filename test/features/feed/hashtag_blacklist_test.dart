import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xflow/core/database/repository.dart';
import 'package:xflow/core/models/local_video_reaction.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/feed/hashtag_blacklist_provider.dart';
import 'package:xflow/features/feed/local_recommendation_profile.dart';

Tweet clip(String id, String caption) => Tweet(
  id: id, text: caption, userHandle: '@author',
  isVideo: true,
  mediaUrls: const ['https://video.twimg.com/demo.mp4'],
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('normalizes blacklisted hashtags, accepting short tags', () {
    expect(normalizeBlockedHashtag(' #F1 '), 'f1');
    expect(normalizeBlockedHashtag('###Nature'), 'nature');
    expect(() => normalizeBlockedHashtag(''), throwsFormatException);
    expect(() => normalizeBlockedHashtag('two words'),
        throwsFormatException);
  });

  test('blacklist persists separately from followed hashtags', () async {
    final db = await Repository.database;
    await db.delete(tableHashtags);
    await db.delete(tableBlockedHashtags);
    await Repository.addHashtag('#nature');
    await Repository.addBlockedHashtag('f1');
    expect(await Repository.getHashtags(), ['#nature']);
    expect(await Repository.getBlockedHashtags(), ['f1']);
    await Repository.removeBlockedHashtag('f1');
    expect(await Repository.getBlockedHashtags(), isEmpty);
    expect(await Repository.getHashtags(), ['#nature']);
  });

  test('blocked hashtag overrides liked videos and subscriptions', () {
    final liked = {
      '1': const LocalVideoReaction(
        videoId:'1', value:1, caption:'#Horror movie', author:'@author',
      ),
    };
    final result = filterByFeedback(
      [clip('1','#Horror'), clip('2','#F1 course'), clip('3','#Nature walk')],
      liked, blockedHashtags: const {'horror','f1'},
    );
    expect(result.map((tweet) => tweet.id), ['3']);
  });

  test('blacklisted words cannot seed discovery from any signal', () {
    final reactions = {
      'liked': const LocalVideoReaction(
        videoId:'liked', value:1, caption:'#F1 racing', author:'@author',
      ),
    };
    final topics = personalizedVideoTopics(
      [clip('a','#F1 #Nature scenery')],
      reactions,
      followedHashtags: const ['#F1','#Nature'],
      watchedVideos: [clip('b','#F1 racing')],
      blockedHashtags: const ['f1'],
    );
    expect(topics, isNot(contains('f1')));
    expect(topics, contains('nature'));
  });
}
