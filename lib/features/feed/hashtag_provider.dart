import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/client/account_provider.dart';
import '../../core/client/public_x_client.dart';
import '../../core/client/twitter_account.dart';
import '../../core/client/twitter_client.dart';
import '../../core/database/repository.dart';
import '../../core/models/tweet.dart';
import '../settings/settings_provider.dart';
import 'feed_provider.dart';

class HashtagListNotifier extends AsyncNotifier<List<String>> {
  @override
  FutureOr<List<String>> build() => Repository.getHashtags();

  Future<void> addHashtag(String tag) async {
    final cleanTag = tag.trim().startsWith('#') ? tag.trim() : '#${tag.trim()}';
    await Repository.addHashtag(cleanTag);
    ref.invalidateSelf();
  }

  Future<void> removeHashtag(String tag) async {
    await Repository.deleteHashtag(tag);
    ref.invalidateSelf();
  }
}

final hashtagListProvider =
    AsyncNotifierProvider<HashtagListNotifier, List<String>>(
  HashtagListNotifier.new,
);

String normalizeHashtagQuery(String hashtag) {
  final text = hashtag.trim();
  if (text.isEmpty) return '';
  return text.startsWith('#') ? text : '#$text';
}

/// A hashtag page works without X credentials: X -> public search ->
/// locally indexed videos. Failures stay visible instead of silently empty.
class HashtagMediaNotifier extends AsyncNotifier<FeedState> {
  HashtagMediaNotifier(this.arg);
  final String arg;
  String? _activeQuery;
  bool _usingPublic = false;
  String? _lastSourceError;

  Future<TweetResponse> _search({
    required String hashtag,
    String? cursor,
    int count = 20,
    bool more = false,
  }) async {
    final client = ref.read(twitterClientProvider);
    final authed =
        TwitterAccount.hasAuthSession(ref.read(accountProvider));
    final query = normalizeHashtagQuery(hashtag);
    if (query.isEmpty) return TweetResponse(tweets: []);
    Object? xError;
    if (authed && !_usingPublic) {
      try {
        final res = await client.fetchTrendingMedia(
          query: query,
          cursor: cursor,
          count: count,
          sort: FeedSort.latest,
          filters: const {MediaFilter.video},
          timeoutSeconds: 10,
          reportErrors: true,
        ).timeout(const Duration(seconds: 13));
        if (res.tweets.isNotEmpty || (more && res.cursorBottom != null)) {
          _activeQuery = query;
          return res;
        }
      } catch (error) {
        xError = error;
      }
    }
    try {
      final public = await PublicXClient()
          .searchVideos(query, count: count, cursor: more ? cursor : null)
          .timeout(const Duration(seconds: 15));
      _usingPublic = true;
      _activeQuery = query;
      if (public.tweets.isNotEmpty || more) return public;
    } catch (error) {
      _lastSourceError = 'X : ${xError ?? 'aucun résultat'} ; public : $error';
    }
    return TweetResponse(tweets: []);
  }

  @override
  Future<FeedState> build() async {
    final settings = ref.watch(settingsProvider);
    // Reset on a new request, but remember which backend supplied the cursor
    // so that pagination never passes an X cursor to the public API.
    _usingPublic = false;
    _lastSourceError = null;
    final hashtag = normalizeHashtagQuery(arg);
    if (hashtag.isEmpty) {
      return FeedState(tweets: []);
    }
    final response = await _search(
      hashtag: hashtag, count: settings.timelineBatchSize,
    );
    if (!ref.mounted) return FeedState(tweets: []);
    var tweets = response.tweets;
    if (tweets.isEmpty) {
      tweets = await Repository.getHashtagCachedMedia(
          hashtag, settings.timelineBatchSize * 3,
          filters: const {MediaFilter.video});
    } else {
      unawaited(Repository.insertCachedMedia(tweets));
    }
    // If X and public search are unavailable, the local cache remains
    // searchable. An empty cache gives an explicit error, not a broken page.
    if (tweets.isEmpty && _lastSourceError != null) {
      throw StateError(
        'Impossible de charger #${hashtag.replaceFirst('#', '')}. '
        '${_lastSourceError!}',
      );
    }
    return FeedState(
      tweets: tweets,
      cursorBottom: response.cursorBottom,
    );
  }

  Future<void> refresh() async {
    _usingPublic = false;
    ref.invalidateSelf();
  }

  Future<void> fetchMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore ||
        current.cursorBottom == null) return;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final response = await _search(
        hashtag: _activeQuery ?? arg,
        cursor: current.cursorBottom,
        count: ref.read(settingsProvider).loadBatchSize,
        more: true,
      );
      if (!ref.mounted) return;
      final seen = current.tweets.map((t) => t.id).toSet();
      final added = response.tweets.where((t) => seen.add(t.id)).toList();
      if (added.isNotEmpty) unawaited(Repository.insertCachedMedia(added));
      state = AsyncData(current.copyWith(
        tweets: [...current.tweets, ...added],
        // Never repeatedly re-fetch an exhausted cursor.
        cursorBottom: response.cursorBottom == current.cursorBottom
            ? '' : (response.cursorBottom ?? ''),
        isLoadingMore: false,
      ));
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(current.copyWith(isLoadingMore: false));
      }
    }
  }
}

final hashtagMediaProvider =
    AsyncNotifierProvider.family<HashtagMediaNotifier, FeedState, String>(
  HashtagMediaNotifier.new,
);
