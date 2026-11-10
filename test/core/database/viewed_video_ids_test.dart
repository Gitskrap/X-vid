import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xflow/core/database/repository.dart';
import 'package:xflow/core/models/tweet.dart';

Tweet clip(String id) => Tweet(
  id:id, text:'Video #nature', userHandle:'@nature',
  isVideo:true, durationMs:25000,
  mediaUrls: const ['https://video.twimg.com/a.mp4'],
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('viewed IDs persist and exclude unplayed clips', () async {
    final db = await Repository.database;
    await db.delete(tableCachedMedia);
    final a = clip('1900000000000001010');
    final b = clip('1900000000000001020');
    await Repository.insertCachedMedia([a,b]);
    expect(await Repository.getViewedVideoIds(), isEmpty);
    await Repository.markMediaAsPlayed(a.id);
    final viewed = await Repository.getViewedVideoIds();
    expect(viewed, contains(a.id));
    expect(viewed, isNot(contains(b.id)));
    final candidates = await Repository.getCachedMediaCandidates(
      10, avoidWatchedContent:true, allowedHandles:{'nature'});
    expect(candidates.map((v)=>v.id), contains(b.id));
    expect(candidates.map((v)=>v.id), isNot(contains(a.id)));
  });
}
