import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xflow/core/database/repository.dart';
import 'package:xflow/core/models/tweet.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('video retrieval account survives cache roundtrip', () async {
    final db = await Repository.database;
    await db.delete(tableCachedMedia);
    await Repository.insertCachedMedia([
      Tweet(
        id: '1900000000000000001', text: 'Video', userHandle: '@NASA',
        mediaUrls: const ['https://video.twimg.com/video.mp4'],
        isVideo: true, retrievedVia: '@accountA',
      ),
    ]);
    final first = await Repository.getUserCachedMedia('nasa', 10);
    expect(first.single.retrievedVia, '@accountA');

    // Metadata fetched without a known account must not discard provenance.
    await Repository.insertCachedMedia([
      Tweet(
        id: '1900000000000000001', text: 'Video', userHandle: '@NASA',
        mediaUrls: const ['https://video.twimg.com/video.mp4'],
        isVideo: true,
      ),
    ]);
    final again = await Repository.getUserCachedMedia('NASA', 10);
    expect(again.single.retrievedVia, '@accountA');
  });
}
