import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xflow/core/database/repository.dart';
import 'package:xflow/core/models/tweet.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final video = Tweet(
    id: '1900000000000000921',
    text: 'Une vidéo de #Babyfoot',
    userHandle: '@creator',
    isVideo: true,
    mediaUrls: const ['https://video.twimg.com/example.mp4'],
  );

  test('likes/dislikes persist locally and are exclusive', () async {
    final db = await Repository.database;
    await db.delete(tableLocalReactions);

    await Repository.setLocalVideoReaction(video, 1);
    var saved = await Repository.getLocalVideoReactions();
    expect(saved[video.id]?.value, 1);
    expect(saved[video.id]?.caption, contains('#Babyfoot'));
    expect(saved[video.id]?.author, '@creator');

    await Repository.setLocalVideoReaction(video, -1);
    saved = await Repository.getLocalVideoReactions();
    expect(saved, hasLength(1));
    expect(saved[video.id]?.value, -1);

    await Repository.setLocalVideoReaction(video, 0);
    expect(await Repository.getLocalVideoReactions(), isEmpty);
  });

  test('reset local reactions does not clear cached posts or X sessions',
      () async {
    final db = await Repository.database;
    await db.delete(tableLocalReactions);
    await Repository.insertCachedMedia([video]);
    await Repository.setLocalVideoReaction(video, 1);
    await Repository.clearLocalVideoReactions();
    expect(await Repository.getLocalVideoReactions(), isEmpty);
    expect(await Repository.getUserCachedMedia('creator', 10), isNotEmpty);
  });

  test('reaction input validation', () async {
    await expectLater(
      Repository.setLocalVideoReaction(video, 3),
      throwsArgumentError,
    );
  });
}
