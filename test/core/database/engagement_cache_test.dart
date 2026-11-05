import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xflow/core/database/repository.dart';
import 'package:xflow/core/models/tweet.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    final db = await Repository.database;
    await db.delete(tableCachedMedia);
  });

  test('caches known counts, including a real zero', () async {
    final tweet = Tweet(
      id: 'engagement_test_1',
      text: 'Video',
      userHandle: '@example',
      mediaUrls: const ['https://video.twimg.com/example.mp4'],
      isVideo: true,
      favoriteCount: 500,
      replyCount: 0,
      isLiked: true,
      favoriteCountKnown: true,
      replyCountKnown: true,
      isLikedKnown: true,
    );
    await Repository.insertCachedMedia([tweet]);
    final cached = await Repository.getUserCachedMedia('example', 5);
    expect(cached, hasLength(1));
    expect(cached.single.favoriteCount, 500);
    expect(cached.single.replyCount, 0);
    expect(cached.single.isLiked, true);
    expect(cached.single.favoriteCountKnown, true);
    expect(cached.single.replyCountKnown, true);
    expect(cached.single.isLikedKnown, true);
  });

  test('missing counts stay unknown rather than becoming fake zeros', () async {
    await Repository.insertCachedMedia([
      Tweet(
        id: 'engagement_test_2',
        text: 'Old video',
        userHandle: '@example',
        mediaUrls: const ['https://video.twimg.com/example.mp4'],
        isVideo: true,
      ),
    ]);
    final cached = await Repository.getUserCachedMedia('example', 5);
    expect(cached, hasLength(1));
    expect(cached.single.favoriteCountKnown, false);
    expect(cached.single.replyCountKnown, false);
    expect(cached.single.isLikedKnown, false);
  });

  test('new API metrics repair old cache without resetting playback history',
      () async {
    final first = Tweet(
      id: 'engagement_test_3',
      text: 'Video',
      userHandle: '@example',
      mediaUrls: const ['https://video.twimg.com/example.mp4'],
      isVideo: true,
    );
    await Repository.insertCachedMedia([first]);
    await Repository.markMediaAsPlayed(first.id);

    final fresh = first.copyWith(
      favoriteCount: 343,
      replyCount: 12,
      isLiked: false,
      favoriteCountKnown: true,
      replyCountKnown: true,
      isLikedKnown: true,
    );
    await Repository.insertCachedMedia([fresh]);

    final db = await Repository.database;
    final rows = await db.query(
      tableCachedMedia,
      where: 'id = ?',
      whereArgs: [first.id],
    );
    expect(rows, hasLength(1));
    expect(rows.single['played_count'], 1);
    expect(rows.single['favorite_count'], 343);
    expect(rows.single['reply_count'], 12);
    expect(rows.single['is_liked'], 0);

    // A later API response omitting stats must not delete confirmed ones.
    await Repository.insertCachedMedia([first]);
    final after = await db.query(
      tableCachedMedia,
      where: 'id = ?',
      whereArgs: [first.id],
    );
    expect(after.single['favorite_count'], 343);
    expect(after.single['reply_count'], 12);
    expect(after.single['is_liked'], 0);
  });
}
