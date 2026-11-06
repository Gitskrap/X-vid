import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/client/twitter_client.dart';
import '../../core/client/twitter_account.dart';
import '../../core/client/account_provider.dart';
import '../../core/client/public_x_client.dart';
import '../../core/database/repository.dart';
import '../../core/database/entities.dart';
import '../feed/feed_provider.dart'; // For FeedState
import '../settings/settings_provider.dart';

final userProfileProvider =
    FutureProvider.family<Subscription?, String>((ref, screenName) async {
  final account = ref.watch(accountProvider);
  final handle = screenName.startsWith('@')
      ? screenName.substring(1)
      : screenName;
  // Use local bookmark metadata when logged out or remote access is denied.
  // The saved list works independently of an X login.
  if (account != null) {
    try {
      final profile = await ref.watch(twitterClientProvider).fetchProfile(handle);
      if (profile != null) return profile;
    } catch (error) {
      debugPrint('Profile lookup unavailable: $error');
    }
  }
  final local = await Repository.getSubscriptions();
  Subscription? saved;
  for (final sub in local) {
    if (sub.screenName.toLowerCase() == handle.toLowerCase()) {
      saved = sub;
      break;
    }
  }
  if (account == null &&
      (saved == null || saved.profileImageUrl == null)) {
    final publicProfile = await PublicXClient().profile(handle);
    if (publicProfile != null) return publicProfile;
  }
  return saved;
});

class UserMediaNotifier extends AsyncNotifier<FeedState> {
  UserMediaNotifier(this.arg);
  final String arg;

  @override
  FutureOr<FeedState> build() async {
    final client = ref.watch(twitterClientProvider);
    final settings = ref.watch(settingsProvider);
    final account = ref.watch(accountProvider);
    final screenName = arg.startsWith('@') ? arg.substring(1) : arg;

    // 1. Try to load from cache immediately to show SOMETHING
    final cached =
        await Repository.getUserCachedMedia(screenName, settings.loadBatchSize);

    // Use the public read-only media source when logged out. A provider
    // outage cannot erase already cached videos.
    unawaited(_fetchFreshData(screenName, client, settings));

    return FeedState(
      tweets: cached.map((t) => t.copyWith(source: 'Cache')).toList(),
      isRefreshing: true,
    );
  }

  Future<void> refresh() async {
    final screenName = arg.startsWith('@') ? arg.substring(1) : arg;
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(isRefreshing: true));
    }
    final client = ref.read(twitterClientProvider);
    final settings = ref.read(settingsProvider);
    await _fetchFreshData(screenName, client, settings);
  }

  Future<void> _fetchFreshData(
    String screenName,
    TwitterClient client,
    SettingsState settings,
  ) async {
    try {
      final response = await _fetchUserMedia(
        client,
        screenName,
        cooldownMinutes: settings.cooldownDuration,
      );

      if (!ref.mounted) return;

      if (response.tweets.isNotEmpty) {
        await Repository.insertCachedMedia(response.tweets);

        final freshTweets =
            response.tweets.map((t) => t.copyWith(source: 'API')).toList();

        // Update state by MERGING to avoid jumps
        if (!ref.mounted) return;
        if (state.hasValue) {
          final currentTweets = state.value!.tweets;
          final existingIds = currentTweets.map((t) => t.id).toSet();
          final uniqueFresh =
              freshTweets.where((t) => !existingIds.contains(t.id)).toList();

          if (uniqueFresh.isNotEmpty) {
            final merged = [...currentTweets, ...uniqueFresh];
            merged.sort((a, b) => (b.createdAt ?? DateTime(0))
                .compareTo(a.createdAt ?? DateTime(0)));

            state = AsyncData(FeedState(
              tweets: merged,
              cursorBottom: response.cursorBottom ?? state.value!.cursorBottom,
              isRefreshing: false,
            ));
          } else {
            state = AsyncData(state.value!.copyWith(isRefreshing: false));
          }
        }
      } else {
        if (!ref.mounted) return;
        if (state.hasValue) {
          state = AsyncData(state.value!.copyWith(isRefreshing: false));
        }
      }
    } catch (e) {
      debugPrint('XFLOW: Background user media fetch error: $e');
      if (!ref.mounted) return;
      if (state.hasValue) {
        state = AsyncData(state.value!.copyWith(isRefreshing: false));
      }
    }
  }

  Future<void> fetchMore() async {
    final currentState = state.value;
    final screenName = arg.startsWith('@') ? arg.substring(1) : arg;

    if (currentState == null || currentState.isLoadingMore) {
      return;
    }

    final client = ref.read(twitterClientProvider);
    final settings = ref.read(settingsProvider);
    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    try {
      final response = await _fetchUserMedia(
        client,
        screenName,
        cursor: currentState.cursorBottom,
        cooldownMinutes: settings.cooldownDuration,
      );

      final newTweets = response.tweets;
      if (newTweets.isNotEmpty) {
        await Repository.insertCachedMedia(newTweets);
      }

      final seenIds = currentState.tweets.map((t) => t.id).toSet();
      final uniqueNewTweets =
          newTweets.where((t) => !seenIds.contains(t.id)).toList();

      state = AsyncData(currentState.copyWith(
        tweets: [...currentState.tweets, ...uniqueNewTweets],
        cursorBottom: response.cursorBottom,
        isLoadingMore: false,
      ));
    } catch (e) {
      debugPrint('Error fetching more user media: $e');
      state = AsyncData(currentState.copyWith(isLoadingMore: false));
    }
  }

  Future<TweetResponse> _fetchUserMedia(
    TwitterClient client,
    String screenName, {
    String? cursor,
    required int cooldownMinutes,
  }) async {
    if (TwitterAccount.currentAccount == null) {
      return PublicXClient().userVideos(screenName, cursor: cursor);
    }
    Subscription? profile;
    try {
      profile = await client.fetchProfile(screenName);
    } catch (e) {
      debugPrint('XFLOW: Could not resolve @$screenName profile id: $e');
    }

    final userId = profile?.id;
    if (userId != null && userId.isNotEmpty) {
      try {
        return await client.fetchUserTimeline(
          userId,
          cursor: cursor,
          cooldownMinutes: cooldownMinutes,
        );
      } catch (e) {
        debugPrint('XFLOW: User timeline fetch failed for $userId: $e');
      }
    }

    return client.fetchUserTimelineByScreenName(
      screenName,
      cursor: cursor,
      cooldownMinutes: cooldownMinutes,
    );
  }
}

final userMediaNotifierProvider =
    AsyncNotifierProvider.family<UserMediaNotifier, FeedState, String>(
        UserMediaNotifier.new);
