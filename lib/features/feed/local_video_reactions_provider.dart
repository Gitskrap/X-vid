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

  /// Makes the UI react immediately, then writes to SQLite. Never waits for
  /// a provider rebuild or remote X call before showing the chosen reaction.
  Future<void> _save(Tweet tweet, int value) async {
    if (value != 1 && value != -1 && value != 0) {
      throw ArgumentError.value(value, 'value');
    }
    final previous = state.value ?? const <String, LocalVideoReaction>{};
    final next = Map<String, LocalVideoReaction>.from(previous);
    if (value == 0) {
      next.remove(tweet.id);
    } else {
      next[tweet.id] = LocalVideoReaction(
        videoId: tweet.id,
        value: value,
        caption: tweet.text,
        author: tweet.userHandle,
      );
    }
    state = AsyncData(Map.unmodifiable(next));
    try {
      await Repository.setLocalVideoReaction(tweet, value);
    } catch (_) {
      // Restore the previous value on a local database failure.
      if (ref.mounted) {
        state = AsyncData(Map<String, LocalVideoReaction>.unmodifiable(previous));
      }
      rethrow;
    }
  }

  Future<void> toggle(Tweet tweet, int reaction) {
    if (reaction != 1 && reaction != -1) {
      throw ArgumentError.value(reaction, 'reaction');
    }
    final previous = state.value?[tweet.id]?.value;
    return _save(tweet, previous == reaction ? 0 : reaction);
  }

  /// A dislike is a strong rejection, never an accidental toggle back to
  /// neutral on repeated taps. The caller can immediately hide the video.
  Future<void> reject(Tweet tweet) => _save(tweet, -1);

  Future<void> clearAll() async {
    await Repository.clearLocalVideoReactions();
    if (ref.mounted) state = const AsyncData({});
  }
}
