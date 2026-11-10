import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xflow/core/database/repository.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/feed/local_video_reactions_provider.dart';

Tweet clip() => Tweet(
  id: '1900000000000000917',
  text: '#Sports',
  userHandle: '@creator',
  isVideo: true,
  mediaUrls: const ['https://video.twimg.com/a.mp4'],
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('dislike updates the visible reaction before SQLite finishes',
      () async {
    final db = await Repository.database;
    await db.delete(tableLocalReactions);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(localVideoReactionsProvider.future);

    final future = container.read(localVideoReactionsProvider.notifier)
        .reject(clip());

    expect(container.read(localVideoReactionsProvider)
        .value?[clip().id]?.value, -1);
    await future;
    expect((await Repository.getLocalVideoReactions())[clip().id]?.value, -1);
  });

  test('rejecting twice does not toggle back to neutral', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(localVideoReactionsProvider.future);
    await container.read(localVideoReactionsProvider.notifier)
        .reject(clip());
    await container.read(localVideoReactionsProvider.notifier)
        .reject(clip());
    expect(container.read(localVideoReactionsProvider)
        .value?[clip().id]?.value, -1);
  });
}
