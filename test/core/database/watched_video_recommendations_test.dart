import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xflow/core/database/repository.dart';
import 'package:xflow/core/models/local_video_reaction.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/feed/local_recommendation_profile.dart';

Tweet clip(String id, String caption, int length) => Tweet(
  id: id, text: caption, userHandle: '@sports',
  isVideo: true, durationMs: length,
  mediaUrls: const ['https://video.twimg.com/example.mp4'],
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('meaningfully watched videos teach recommendations locally', () async {
    final db = await Repository.database;
    await db.delete(tableCachedMedia);
    final watched = clip('1900000000000009101', '#Cyclisme super course', 20000);
    final brieflySeen = clip('1900000000000009102', '#Football', 30000);
    await Repository.insertCachedMedia([watched, brieflySeen]);
    await Repository.recordMeaningfulVideoWatch(watched);
    final samples = await Repository.getMeaningfullyWatchedVideos();
    expect(samples.map((t) => t.id), [watched.id]);
    expect(samples.single.durationMs, 20000);
    final topics = personalizedVideoTopics([], const <String, LocalVideoReaction>{},
      watchedVideos: samples);
    expect(topics, contains('cyclisme'));
    expect(topics, isNot(contains('football')));
  });

  test('strictly 15-second video cannot be a watched interest', () async {
    final db = await Repository.database;
    await db.delete(tableCachedMedia);
    final short = clip('1900000000000009201', '#Shorts', 15000);
    await Repository.recordMeaningfulVideoWatch(short);
    final samples = await Repository.getMeaningfullyWatchedVideos();
    expect(samples, isEmpty);
  });

  test('cache roundtrip retains true duration', () async {
    final db = await Repository.database;
    await db.delete(tableCachedMedia);
    final sample = clip('1900000000000009301', '#Nature', 15001);
    await Repository.insertCachedMedia([sample]);
    final cached = await Repository.getUserCachedMedia('sports', 10);
    expect(cached.single.durationMs, 15001);
    await Repository.saveResolvedVideoDuration(sample.id, 45000);
    final updated = await Repository.getUserCachedMedia('sports', 10);
    expect(updated.single.durationMs, 45000);
  });

  test('all four interest signals combine and dislike takes precedence', () {
    final followed = [clip('1', '#Running #Nature race', 30000),
      clip('2', '#Running #Nature event', 35000)];
    final watched = [clip('3', '#Cycling discovery', 40000)];
    final reactions = <String, LocalVideoReaction>{
      'good': const LocalVideoReaction(videoId:'good', value:1,
         caption:'#Babyfoot final', author:'@club'),
      'bad': const LocalVideoReaction(videoId:'bad', value:-1,
         caption:'#Horror film', author:'@unfollowed'),
    };
    final topics = personalizedVideoTopics(followed, reactions,
      followedHashtags: ['#Cyclisme', '#Horror'],
      watchedVideos: watched,
      limit: 8);
    expect(topics, containsAll(['babyfoot','cyclisme','running','cycling']));
    expect(topics, isNot(contains('horror')));
  });
}
