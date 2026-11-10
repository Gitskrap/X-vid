import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xflow/core/database/repository.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/feed/hashtag_provider.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('normalizes hashtags on tap and in keyword search', () {
    expect(normalizeHashtagQuery('babyfoot'), '#babyfoot');
    expect(normalizeHashtagQuery(' #Nature '), '#Nature');
    expect(normalizeHashtagQuery('  '), '');
  });

  test('cached hashtag media remains searchable when APIs are unavailable',
    () async {
    final db = await Repository.database;
    await db.delete(tableCachedMedia);
    final tagged = Tweet(
      id:'1900000000000001030',
      text:'Grand tournoi #Babyfoot à Paris',
      userHandle:'@club', isVideo:true, durationMs:30000,
      mediaUrls:const ['https://video.twimg.com/video.mp4'],
    );
    await Repository.insertCachedMedia([tagged]);
    final results = await Repository.getHashtagCachedMedia(
      normalizeHashtagQuery('Babyfoot'), 20);
    expect(results.map((video)=>video.id), contains(tagged.id));
  });
}
