import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/client/twitter_client.dart';
import '../../core/client/twitter_account.dart';
import '../../core/client/account_provider.dart';
import '../../core/client/public_x_client.dart';
import '../../core/models/tweet.dart';
import '../../core/database/repository.dart';
import '../../core/client/discovery_engine.dart';
import '../../core/utils/app_logger.dart';
import '../settings/settings_provider.dart';
import '../subscriptions/subscription_list_screen.dart';
import 'local_video_filter.dart';
import 'similar_video_discovery.dart';
import 'local_recommendation_profile.dart';
import 'local_video_reactions_provider.dart';
import '../../core/models/local_video_reaction.dart';
import '../player/player_pool_provider.dart';

final twitterClientProvider = Provider((ref) => TwitterClient());

class FeedState {
  final List<Tweet> tweets;
  final String? cursorBottom;
  final bool isLoadingMore;
  final bool isRefreshing;

  FeedState({
    required List<Tweet> tweets,
    this.cursorBottom,
    this.isLoadingMore = false,
    this.isRefreshing = false,
  }) : tweets = List<Tweet>.unmodifiable(
          tweets.where((tweet) => tweet.isVideo && tweet.mediaUrls.isNotEmpty),
        );

  FeedState copyWith({
    List<Tweet>? tweets,
    String? cursorBottom,
    bool? isLoadingMore,
    bool? isRefreshing,
  }) {
    return FeedState(
      tweets: tweets ?? this.tweets,
      cursorBottom: cursorBottom ?? this.cursorBottom,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

class FeedNotifier extends AsyncNotifier<FeedState> {
  static int _publicSubscriptionOffset = 0;

  /// Read-only fallback when X does not return videos for followed accounts.
  /// FxEmbed never receives the user's X cookies or tokens.
  Future<TweetResponse> _fetchPublicSubscriptions(int maxVideos) async {
    final subscriptions = ref.read(subscriptionListProvider).allSubscriptions;
    if (subscriptions.isEmpty) return TweetResponse(tweets: []);
    final limit = subscriptions.length < 5 ? subscriptions.length : 5;
    final selected = [
      for (var i = 0; i < limit; i++)
        subscriptions[(_publicSubscriptionOffset + i) % subscriptions.length]
    ];
    _publicSubscriptionOffset =
        (_publicSubscriptionOffset + limit) % subscriptions.length;

    final publicClient = PublicXClient();
    final pages = await Future.wait(selected.map((sub) async {
      try {
        return await publicClient.userVideos(sub.screenName, count: 20);
      } catch (error) {
        AppLogger.log('Public videos unavailable for @${sub.screenName}: $error');
        return TweetResponse(tweets: []);
      }
    }));
    final unique = <String, Tweet>{};
    for (final page in pages) {
      for (final tweet in page.tweets) {
        unique.putIfAbsent(tweet.id, () => tweet);
      }
    }
    final videos = unique.values.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));
    return TweetResponse(tweets: videos.take(maxVideos).toList());
  }

  /// Optional discovery: queries topics extracted from actual videos of
  /// locally saved creators. Recommendations never modify the local follow list.
  Future<List<Tweet>> _fetchRelatedVideos(
    List<Tweet> examples,
    Set<String> localHandles,
    TwitterClient client,
    Map<String, LocalVideoReaction> reactions,
  ) async {
    // Liked clips have stronger influence than passive follows. Rejected
    // captions/hashtags reduce suggestions, without POSTing any X likes.
    final topics = personalizedVideoTopics(examples, reactions, limit: 3);
    if (topics.isEmpty) return const [];
    final found = <String, Tweet>{};
    final hasSession =
        TwitterAccount.hasAuthSession(ref.read(accountProvider));
    for (final topic in topics) {
      if (!ref.mounted) break;
      TweetResponse result = TweetResponse(tweets: []);
      if (hasSession) {
        try {
          result = await client.fetchTrendingMedia(
            query: topic,
            count: 20,
            filters: const {MediaFilter.video},
            timeoutSeconds: 9,
            reportErrors: true,
          ).timeout(const Duration(seconds: 11));
        } catch (error) {
          AppLogger.log('Related X query unavailable: $error');
        }
      }
      if (result.tweets.isEmpty) {
        try {
          result = await PublicXClient().searchVideos(topic, count: 20)
              .timeout(const Duration(seconds: 10));
        } catch (error) {
          AppLogger.log('Related public query unavailable: $error');
        }
      }
      for (final video in result.tweets) {
        final author = video.userHandle.replaceFirst('@', '').toLowerCase();
        if (!video.isVideo || video.mediaUrls.isEmpty ||
            localHandles.contains(author) ||
            excludedByFeedback(video, reactions)) continue;
        found.putIfAbsent(video.id,
            () => video.copyWith(source: 'Découverte'));
      }
      if (found.length >= 5) break;
    }
    return found.values.take(5).toList();
  }

  // A bounded number of detailed X requests refreshes visible counters
  // without rate-limiting every vertical swipe.
  final Map<String, DateTime> _checkedEngagementAt = {};
  DateTime? _lastEngagementRequest;
  bool _engagementRequestPending = false;

  /// A cached count is a snapshot; refresh it when the video is viewed.
  Future<bool> refreshVisibleEngagement(String tweetId,
      {bool force = false}) async {
    if (TwitterAccount.currentAccount == null) return false;
    if (_engagementRequestPending) return false;
    final current = state.value;
    if (current == null ||
        !current.tweets.any((tweet) => tweet.id == tweetId)) {
      return false;
    }
    final now = DateTime.now();
    final previouslyChecked = _checkedEngagementAt[tweetId];
    if (!force &&
        previouslyChecked != null &&
        now.difference(previouslyChecked) < const Duration(minutes: 15)) {
      return false;
    }
    if (!force &&
        _lastEngagementRequest != null &&
        now.difference(_lastEngagementRequest!) < const Duration(seconds: 25)) {
      return false;
    }

    _engagementRequestPending = true;
    _lastEngagementRequest = now;
    _checkedEngagementAt[tweetId] = now;
    try {
      final response =
          await ref.read(twitterClientProvider).fetchTweetDetail(tweetId);
      Tweet? fresh;
      for (final candidate in response.tweets) {
        if (candidate.id == tweetId) {
          fresh = candidate;
          break;
        }
      }
      if (fresh == null ||
          (!fresh.favoriteCountKnown &&
              !fresh.replyCountKnown &&
              !fresh.isLikedKnown)) {
        return false;
      }

      final latest = state.value;
      if (latest == null) return false;
      final index = latest.tweets.indexWhere((tweet) => tweet.id == tweetId);
      if (index < 0) return false;
      final previous = latest.tweets[index];

      final merged = previous.copyWith(
        retrievedVia: fresh.retrievedVia,
        favoriteCount: fresh.favoriteCountKnown
            ? fresh.favoriteCount
            : previous.favoriteCount,
        replyCount: fresh.replyCountKnown
            ? fresh.replyCount
            : previous.replyCount,
        isLiked: fresh.isLikedKnown ? fresh.isLiked : previous.isLiked,
        favoriteCountKnown:
            previous.favoriteCountKnown || fresh.favoriteCountKnown,
        replyCountKnown: previous.replyCountKnown || fresh.replyCountKnown,
        isLikedKnown: previous.isLikedKnown || fresh.isLikedKnown,
      );
      final updated = List<Tweet>.from(latest.tweets);
      updated[index] = merged;
      state = AsyncData(latest.copyWith(tweets: updated));
      await Repository.insertCachedMedia([merged]);
      return true;
    } catch (e) {
      AppLogger.log('XFLOW: Could not refresh engagement for $tweetId: $e');
      return false;
    } finally {
      _engagementRequestPending = false;
    }
  }

  List<Tweet> _runDiscoveryPipeline(
    List<Tweet> freshPool,
    List<Tweet> localPool,
    SettingsState settings,
    Map<String, int> playedByUser, {
    int protectedIndex = 0,
    List<Tweet> currentTweets = const [],
  }) {
    final head = currentTweets.take(protectedIndex).toList();
    final headIds = head.map((t) => t.id).toSet();
    final headMedia = head
        .where((t) => t.mediaUrls.isNotEmpty)
        .map((t) => t.mediaUrls.first)
        .toSet();

    // Initialize seen sets using a sliding window of already visible tweets
    final dedupeWindow = currentTweets.length >
            settings.mediaDeduplicationWindow
        ? currentTweets
            .sublist(currentTweets.length - settings.mediaDeduplicationWindow)
        : currentTweets;

    final seenIds = {...headIds, ...dedupeWindow.map((t) => t.id)};
    final seenMediaUrls = {
      ...headMedia,
      ...dedupeWindow
          .where((t) => t.mediaUrls.isNotEmpty)
          .map((t) => t.mediaUrls.first)
    };

    List<Tweet> deduplicate(List<Tweet> pool) {
      return pool.where((t) {
        if (seenIds.contains(t.id)) return false;
        if (t.mediaUrls.isNotEmpty &&
            seenMediaUrls.contains(t.mediaUrls.first)) {
          return false;
        }
        seenIds.add(t.id);
        if (t.mediaUrls.isNotEmpty) seenMediaUrls.add(t.mediaUrls.first);
        return true;
      }).toList();
    }

    final uniqueFresh = deduplicate(freshPool)..shuffle();
    final uniqueLocal = deduplicate(localPool)..shuffle();

    final interleaved = DiscoveryEngine.interleave(
        uniqueFresh, uniqueLocal, settings.freshMixRatio);

    var processed = [...head, ...interleaved];

    if (settings.unseenSubscriptionBoost) {
      processed = DiscoveryEngine.applyUnseenSubscriptionBoost(
        processed,
        playedByUser,
        lookahead: settings.unseenBoostLookahead,
        startIndex: head.length,
      );
    }

    processed = DiscoveryEngine.applySaturation(
      processed,
      threshold: settings.saturationThreshold,
      mediaThreshold: settings.mediaSaturationThreshold,
      windowSize: settings.saturationWindow,
      startIndex: head.length,
      maxSaturationSwaps: settings.maxSaturationSwaps,
      maxPasses: settings.maxSaturationPasses,
    );

    return processed;
  }

  @override
  FutureOr<FeedState> build() async {
    final settings = ref.watch(settingsProvider);
    final reactions = ref.watch(localVideoReactionsProvider).value ??
        const <String, LocalVideoReaction>{};
    // The local list, not X's follow list, is the sole source of creators.
    final subscriptions = ref.watch(subscriptionListProvider);
    // Rebuild after login, switching accounts, or logout.
    ref.watch(accountProvider);
    if (subscriptions.isLoading) {
      return FeedState(tweets: [], isRefreshing: true);
    }
    final allowedHandles = localVideoHandles(subscriptions.allSubscriptions);
    if (allowedHandles.isEmpty) {
      return FeedState(tweets: [], isRefreshing: false);
    }

    debugPrint(
        'XFLOW: Building FeedNotifier. fetchStrategy: ${settings.fetchStrategy}');

    try {
      // Stage 1: Immediate local candidate retrieval
      final localPool = await Repository.getCachedMediaCandidates(
        settings.loadBatchSize * settings.dbCandidateMultiplier,
        avoidWatchedContent: settings.avoidWatchedContent,
        filters: settings.filters,
        allowedHandles: allowedHandles,
      );
      final localTagged = filterByFeedback(
        onlyLocalSubscriptionVideos(localPool, allowedHandles), reactions,
      ).map((t) => t.copyWith(source: 'Cache')).toList();
      AppLogger.log(
          'XFLOW: Cold start: Retrieved ${localPool.length} local candidates');

      // EARLY MEDIA WARMUP
      if (localTagged.isNotEmpty) {
        final pool = ref.read(playerPoolProvider.notifier);
        for (int i = 0; i < localTagged.length && i < 2; i++) {
          final tweet = localTagged[i];
          if (tweet.isVideo && tweet.mediaUrls.isNotEmpty) {
            pool.warmup(tweet.id, tweet.mediaUrls.first);
          }
        }
      }

      // TRIGGER BACKGROUND SYNC
      if (settings.isInitialized) {
        Future.delayed(Duration.zero, () => _refreshInBackground());
      }

      return FeedState(
        tweets: localTagged,
        cursorBottom: null,
        isRefreshing: localTagged.isEmpty,
      );
    } catch (e, st) {
      debugPrint('XFLOW: Error in build(): $e\n$st');
      return FeedState(tweets: [], isRefreshing: false);
    }
  }

  Future<void> refresh() async {
    final currentState = state.value;
    if (currentState == null || currentState.isRefreshing) return;

    state = AsyncData(currentState.copyWith(isRefreshing: true));
    await _refreshInBackground(resetHead: true);
  }

  Future<void> _refreshInBackground({bool resetHead = false}) async {
    if (!ref.exists(feedNotifierProvider)) return;

    final client = ref.read(twitterClientProvider);
    final settings = ref.read(settingsProvider);
    final reactions = ref.read(localVideoReactionsProvider).value ??
        const <String, LocalVideoReaction>{};
    final allowedHandles = localVideoHandles(
        ref.read(subscriptionListProvider).allSubscriptions);
    if (allowedHandles.isEmpty) {
      if (ref.mounted && state.hasValue) {
        state = AsyncData(FeedState(tweets: [], isRefreshing: false));
      }
      return;
    }

    debugPrint('XFLOW: Background refresh started');

    try {
      // 1. Fetch from API
      // Do not use For You, Following or global trending as home sources.
      // Only author handles explicitly saved inside Twitter vidéo qualify.
      TweetResponse freshResponse = await client.fetchSubscribedMedia(
        sort: settings.fetchStrategy == FeedSort.popular
            ? FeedSort.popular
            : FeedSort.latest,
        filters: const {MediaFilter.video},
        subBatchSize: settings.syncBatchSize,
        loadBatchSize: settings.initialSyncCount,
        cooldownMinutes: settings.cooldownDuration,
        strictSubscriptionsOnly: true,
        includeNativeRetweets: false,
        useChunkedSubscriptions: settings.useChunkedSubscriptions,
        minFaves: settings.minFavesFilter,
      );

      if (freshResponse.tweets.isEmpty) {
        final publicResponse =
            await _fetchPublicSubscriptions(settings.initialSyncCount);
        if (publicResponse.tweets.isNotEmpty) freshResponse = publicResponse;
      }

      if (!ref.mounted) return;
      final freshPool = filterByFeedback(
          onlyLocalSubscriptionVideos(freshResponse.tweets, allowedHandles),
          reactions);
      final freshTagged = freshPool
          .map((t) => t.copyWith(source: 'API'))
          .toList();

      debugPrint(
          'XFLOW: Background refresh returned ${freshPool.length} fresh tweets');

      if (freshPool.isNotEmpty) {
        await Repository.insertCachedMedia(freshPool);
      }

      // 2. Fetch local pool (now including fresh items)
      final localPool = await Repository.getCachedMediaCandidates(
        settings.loadBatchSize * settings.dbCandidateMultiplier,
        avoidWatchedContent: settings.avoidWatchedContent,
        filters: settings.filters,
        allowedHandles: allowedHandles,
      );
      final localTagged = filterByFeedback(
        onlyLocalSubscriptionVideos(localPool, allowedHandles), reactions,
      ).map((t) => t.copyWith(source: 'Cache')).toList();

      final currentAsync = ref.read(feedNotifierProvider);
      if (currentAsync.hasValue) {
        final current = currentAsync.value!;

        final playedByUser = settings.unseenSubscriptionBoost
            ? await Repository.getPlayedCountsByUser()
            : const <String, int>{};

        // PROTECT THE ACTIVE VIDEO: If user is at index 0, protect index 0 from being swapped.
        // We protect up to 2 items to ensure the "next" item also doesn't jump unexpectedly.
        final processed = _runDiscoveryPipeline(
          freshTagged,
          localTagged,
          settings,
          playedByUser,
          protectedIndex: resetHead ? 0 : 2,
          currentTweets: resetHead ? [] :
              filterByFeedback(current.tweets, reactions),
        );

        final related = settings.suggestSimilarVideos
            ? await _fetchRelatedVideos(
                [...freshTagged, ...localTagged], allowedHandles, client,
                reactions)
            : <Tweet>[];
        if (!ref.mounted) return;
        final mixed = filterByFeedback(
            mixRelatedVideos(processed, related), reactions);
        state = AsyncData(current.copyWith(
          tweets: mixed,
          cursorBottom: freshResponse.cursorBottom,
          isRefreshing: false,
        ));
        debugPrint(
            'XFLOW: Feed state updated from background refresh. Total: ${processed.length}');
      }
    } catch (e) {
      debugPrint('XFLOW: Background refresh error: $e');
      final currentAsync = ref.read(feedNotifierProvider);
      if (currentAsync.hasValue) {
        state = AsyncData(currentAsync.value!.copyWith(isRefreshing: false));
      }
    }
  }

  Future<void> fetchMore() async {
    final currentState = state.value;
    if (currentState == null || currentState.isLoadingMore) return;

    final settings = ref.read(settingsProvider);
    final reactions = ref.read(localVideoReactionsProvider).value ??
        const <String, LocalVideoReaction>{};
    final allowedHandles = localVideoHandles(
        ref.read(subscriptionListProvider).allSubscriptions);
    if (allowedHandles.isEmpty) {
      state = AsyncData(FeedState(tweets: [], isRefreshing: false));
      return;
    }

    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    try {
      final seenIds = state.value!.tweets.map((t) => t.id).toSet();

      // Use dynamic deduplication window from settings
      final dedupeWindow = state.value!.tweets.length >
              settings.mediaDeduplicationWindow
          ? state.value!.tweets.sublist(
              state.value!.tweets.length - settings.mediaDeduplicationWindow)
          : state.value!.tweets;

      final seenMedia = dedupeWindow
          .where((t) => t.mediaUrls.isNotEmpty)
          .map((t) => t.mediaUrls.first)
          .toSet();

      List<Tweet> allNewTweets = [];
      String? currentCursor = state.value!.cursorBottom;
      final seenCursors = <String>{};
      bool publicFallbackAttempted = false;
      int apiRetries = 0;
      int chunkRotations = 0;
      final maxRetries =
          settings.apiRetryLimit * 2; // Increase limit for robustness

      while (allNewTweets.length < settings.minNewTweetsThreshold &&
          apiRetries < maxRetries &&
          chunkRotations < settings.chunkRotationLimit) {
        // 1. Try to fetch from DB first (refresh pool)
        final dbCandidates = await Repository.getCachedMediaCandidates(
          settings.loadBatchSize * settings.dbCandidateMultiplier,
          avoidWatchedContent: settings.avoidWatchedContent,
          filters: settings.filters,
          allowedHandles: allowedHandles,
        );

        var localNew = filterByFeedback(
          onlyLocalSubscriptionVideos(dbCandidates, allowedHandles),
          reactions,
        ).where((t) {
          if (!t.isVideo || t.mediaUrls.isEmpty) return false;
          return !seenIds.contains(t.id) &&
              (t.mediaUrls.isEmpty || !seenMedia.contains(t.mediaUrls.first));
        }).toList();

        if (localNew.isNotEmpty) {
          allNewTweets.addAll(localNew);
          if (allNewTweets.length >= settings.minNewTweetsThreshold) break;
        }

        // 2. Hit the API
        final client = ref.read(twitterClientProvider);
        if (currentCursor != null) seenCursors.add(currentCursor);

        try {
          final TweetResponse response = await client.fetchSubscribedMedia(
            cursor: currentCursor,
            sort: settings.fetchStrategy == FeedSort.popular
                ? FeedSort.popular
                : FeedSort.latest,
            filters: const {MediaFilter.video},
            subBatchSize: settings.syncBatchSize,
            loadBatchSize: settings.loadBatchSize,
            cooldownMinutes: settings.cooldownDuration,
            strictSubscriptionsOnly: true,
            includeNativeRetweets: false,
            useChunkedSubscriptions: settings.useChunkedSubscriptions,
            minFaves: settings.minFavesFilter,
            maxQueryLength: settings.maxQueryLength,
            timeoutSeconds: settings.apiTimeoutSeconds,
          );

          // Once per load-more action, try public videos when native X
          // returns none. Do not loop on the public service indefinitely.
          TweetResponse effectiveResponse = response;
          if (response.tweets.isEmpty && !publicFallbackAttempted) {
            publicFallbackAttempted = true;
            final publicResponse =
                await _fetchPublicSubscriptions(settings.loadBatchSize);
            if (publicResponse.tweets.isNotEmpty) {
              effectiveResponse = publicResponse;
            }
          }

          final localFresh = filterByFeedback(
              onlyLocalSubscriptionVideos(effectiveResponse.tweets,
                  allowedHandles), reactions);
          final freshUnique = localFresh.where((t) {
            if (!t.isVideo || t.mediaUrls.isEmpty) return false;
            return !seenIds.contains(t.id) &&
                (t.mediaUrls.isEmpty || !seenMedia.contains(t.mediaUrls.first));
          }).toList();

          if (localFresh.isNotEmpty) {
            await Repository.insertCachedMedia(localFresh);
          }

          allNewTweets.addAll(freshUnique);
          apiRetries++;

          // Handle Pagination vs Rotation
          if (response.cursorBottom != null &&
              response.cursorBottom != currentCursor &&
              !seenCursors.contains(response.cursorBottom!)) {
            currentCursor = response.cursorBottom;
          } else {
            // Chunk exhausted or stuck cursor
            AppLogger.log(
                'XFLOW: Chunk exhausted or stuck cursor. Rotating to next subscription chunk.');
            currentCursor = null;
            chunkRotations++;
            await Future.delayed(const Duration(milliseconds: 300));
          }
        } catch (e) {
          AppLogger.log('XFLOW: fetchMore API error: $e');
          apiRetries++;
          await Future.delayed(const Duration(seconds: 1));
        }

        if (allNewTweets.length < settings.minNewTweetsThreshold) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (allNewTweets.isEmpty) {
        state = AsyncData(state.value!.copyWith(isLoadingMore: false));
        return;
      }

      // Shuffle candidates BEFORE taking the batch to improve diversity
      allNewTweets.shuffle();

      final finalNewTweets = filterByFeedback(
          allNewTweets, reactions)
          .take(settings.loadBatchSize)
          .map((t) => t.copyWith(source: t.source ?? 'Mixed'))
          .toList();

      final related = settings.suggestSimilarVideos
          ? await _fetchRelatedVideos(
              onlyLocalSubscriptionVideos(
                [...state.value!.tweets, ...finalNewTweets], allowedHandles),
              allowedHandles,
              ref.read(twitterClientProvider),
              reactions,
            )
          : <Tweet>[];
      if (!ref.mounted) return;
      final mixedNew = mixRelatedVideos(finalNewTweets, related);
      var combined = filterByFeedback(
          [...state.value!.tweets, ...mixedNew], reactions);

      // Apply diversity enforcement to the new tail
      combined = DiscoveryEngine.applySaturation(
        combined,
        threshold: settings.saturationThreshold,
        mediaThreshold: settings.mediaSaturationThreshold,
        windowSize: settings.saturationWindow,
        startIndex: state.value!.tweets.length,
        maxSaturationSwaps: settings.maxSaturationSwaps,
        maxPasses: settings.maxSaturationPasses,
      );

      state = AsyncData(state.value!.copyWith(
        tweets: combined,
        cursorBottom: currentCursor,
        isLoadingMore: false,
      ));
      debugPrint(
          'XFLOW: fetchMore complete. Added ${finalNewTweets.length} tweets. Total: ${combined.length}');
    } catch (e, st) {
      debugPrint('Error fetching more: $e\n$st');
      state = AsyncData(state.value!.copyWith(isLoadingMore: false));
    }
  }


}

final feedNotifierProvider =
    AsyncNotifierProvider.autoDispose<FeedNotifier, FeedState>(
        FeedNotifier.new);
