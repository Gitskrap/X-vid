import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository.dart';
import '../../core/models/local_video_reaction.dart';
import '../../core/models/tweet.dart';

/// All reactions are local to Twitter vidéo, independent of the X account.
final localVideoReactionsProvider =
    AsyncNotifierProvider<LocalVideoReactionsNotifier,
        Map<String, LocalVideoReaction>>(LocalVideoReactionsNotifier.new);

class LocalVideoReactionsNotifier
    extends AsyncNotifier<Map<String, LocalVideoReaction>> {
  @override
  FutureOr<Map<String, LocalVideoReaction>> build() =>
      Repository.getLocalVideoReactions();

  /// Tapping a selected reaction again removes it; like/dislike are exclusive.
  /// Unlike the former like button this never invokes TwitterClient.
  Future<void> toggle(Tweet tweet, int reaction) async {
    if (reaction != 1 && reaction != -1) {
      throw ArgumentError.value(reaction, 'reaction');
    }
    final current = await future;
    final nextValue = current[tweet.id]?.value == reaction ? 0 : reaction;
    await Repository.setLocalVideoReaction(tweet, nextValue);
    if (!ref.mounted) return;
    final next = Map<String, LocalVideoReaction>.from(current);
    if (nextValue == 0) {
      next.remove(tweet.id);
    } else {
      next[tweet.id] = LocalVideoReaction(
        videoId: tweet.id,
        value: nextValue,
        caption: tweet.text,
        author: tweet.userHandle,
      );
    }
    state = AsyncData(Map<String, LocalVideoReaction>.unmodifiable(next));
  }

  Future<void> clearAll() async {
    await Repository.clearLocalVideoReactions();
    if (ref.mounted) state = const AsyncData({});
  }
}
