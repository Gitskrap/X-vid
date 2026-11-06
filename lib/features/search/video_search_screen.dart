import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/client/twitter_account.dart';
import '../../core/database/repository.dart';
import '../../core/models/tweet.dart';
import '../../core/navigation/navigation_provider.dart';
import '../feed/feed_provider.dart';
import '../feed/tiktok_feed_screen.dart';
import '../player/player_pool_provider.dart';
import '../player/video_ui_provider.dart';
import '../settings/settings_provider.dart';
import 'video_search_utils.dart';

/// Searches videos across X rather than searching only followed accounts.
/// The result screen reuses the main TikTok-style player and Cast controls.
class VideoSearchScreen extends ConsumerStatefulWidget {
  const VideoSearchScreen({super.key});

  @override
  ConsumerState<VideoSearchScreen> createState() => _VideoSearchScreenState();
}

class _VideoSearchScreenState extends ConsumerState<VideoSearchScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _pageController = PageController();

  List<Tweet> _results = [];
  FeedSort _sort = FeedSort.trending;
  String _query = '';
  String? _cursor;
  String? _error;
  int _index = 0;
  int _searchVersion = 0;
  bool _isLoading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _poolScheduled = false;
  final Set<String> _likePending = {};

  @override
  void dispose() {
    _searchVersion++;
    _input.dispose();
    _focus.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _runSearch({bool more = false}) async {
    if (more && (_isLoading || _loadingMore || !_hasMore)) return;

    final text = more ? _query : normalizeVideoSearch(_input.text);
    if (text.isEmpty) {
      if (!more) {
        setState(() {
          _query = '';
          _results = [];
          _cursor = null;
          _hasMore = false;
          _error = null;
        });
        _focus.requestFocus();
      }
      return;
    }

    if (more) {
      setState(() => _loadingMore = true);
    } else {
      _searchVersion++;
      _focus.unfocus();
      ref.read(videoUiHiddenProvider.notifier).show();
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      setState(() {
        _query = text;
        _results = [];
        _cursor = null;
        _hasMore = false;
        _index = 0;
        _isLoading = true;
        _error = null;
      });
    }

    final requestVersion = _searchVersion;
    final cursor = _cursor;

    try {
      // No from: or following: constraint: search across public X posts.
      // Video filter is enforced both by X and by our local MP4 filter.
      final response = await ref.read(twitterClientProvider).fetchTrendingMedia(
        query: text,
        sort: _sort,
        filters: const {MediaFilter.video},
        cursor: more ? cursor : null,
        count: 30,
        timeoutSeconds: 20,
      );
      if (!mounted || _searchVersion != requestVersion) return;

      final videos = videoSearchResults(response.tweets);
      final knownIds = _results.map((tweet) => tweet.id).toSet();
      final additional = videos.where((tweet) => !knownIds.contains(tweet.id));
      setState(() {
        _results = more ? [..._results, ...additional] : videos;
        _cursor = response.cursorBottom;
        _hasMore = response.tweets.isNotEmpty &&
            response.cursorBottom != null &&
            response.cursorBottom!.isNotEmpty &&
            response.cursorBottom != cursor;
        _error = null;
      });

      if (videos.isNotEmpty) {
        // Saves only tweet media and engagement, not the search terms.
        unawaited(Repository.insertCachedMedia(videos).catchError((Object e) {
          debugPrint('Unable to cache search videos: $e');
        }));
      }
      _warmupPlayers();
    } catch (error) {
      if (!mounted || _searchVersion != requestVersion) return;
      setState(() => _error = 'Erreur lors de la recherche sur X : $error');
    } finally {
      if (mounted && _searchVersion == requestVersion) {
        setState(() {
          _isLoading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _changePage(int next) {
    setState(() => _index = next);
    ref.read(videoUiHiddenProvider.notifier).show();

    if (next >= 0 && next < _results.length) {
      unawaited(Repository.markMediaAsPlayed(_results[next].id));
    }
    _warmupPlayers();
    if (_hasMore && next >= _results.length - 4) {
      unawaited(_runSearch(more: true));
    }
  }

  void _warmupPlayers() {
    if (_poolScheduled) return;
    _poolScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _poolScheduled = false;
      if (!mounted || _results.isEmpty) return;
      final pool = ref.read(playerPoolProvider.notifier);
      final active = <String>{};
      for (int i = _index - 1; i <= _index + 1; i++) {
        if (i < 0 || i >= _results.length) continue;
        final tweet = _results[i];
        active.add(tweet.id);
        if (tweet.mediaUrls.isNotEmpty) {
          pool.warmup(tweet.id, tweet.mediaUrls.first);
        }
      }
      pool.cleanupExcept(active);
    });
  }

  Future<void> _like(String id) async {
    if (_likePending.contains(id)) return;
    if (TwitterAccount.currentAccount == null) {
      _notify('Connecte-toi à X pour aimer une vidéo.');
      return;
    }
    var index = _results.indexWhere((tweet) => tweet.id == id);
    if (index < 0) return;

    _likePending.add(id);
    try {
      var current = _results[index];
      if (!current.isLikedKnown) {
        final detail =
            await ref.read(twitterClientProvider).fetchTweetDetail(id);
        if (!mounted) return;
        final verified =
            detail.tweets.where((tweet) => tweet.id == id).firstOrNull;
        if (verified == null || !verified.isLikedKnown) {
          _notify('X ne permet pas de vérifier le statut du like.');
          return;
        }
        current = current.copyWith(
          isLiked: verified.isLiked,
          isLikedKnown: true,
          favoriteCount: verified.favoriteCountKnown
              ? verified.favoriteCount
              : current.favoriteCount,
          favoriteCountKnown:
              current.favoriteCountKnown || verified.favoriteCountKnown,
        );
      }

      index = _results.indexWhere((tweet) => tweet.id == id);
      if (index < 0 || !mounted) return;
      final initial = current;
      final newIsLiked = !initial.isLiked;
      final calculatedCount = initial.favoriteCount + (newIsLiked ? 1 : -1);
      final pending = initial.copyWith(
        isLiked: newIsLiked,
        isLikedKnown: true,
        favoriteCount: calculatedCount < 0 ? 0 : calculatedCount,
      );

      setState(() => _results[index] = pending);
      final client = ref.read(twitterClientProvider);
      final success = newIsLiked
          ? await client.favoriteTweet(id)
          : await client.unfavoriteTweet(id);
      if (!mounted) return;
      final updatedIndex = _results.indexWhere((tweet) => tweet.id == id);
      if (updatedIndex < 0) return;
      if (!success) {
        setState(() => _results[updatedIndex] = initial);
        _notify('X a refusé la modification du like.');
      } else {
        unawaited(Repository.insertCachedMedia([pending]));
      }
    } catch (error) {
      _notify('Impossible de modifier le like : $error');
    } finally {
      _likePending.remove(id);
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _setSort(FeedSort sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    if (_query.isNotEmpty) unawaited(_runSearch());
  }

  @override
  Widget build(BuildContext context) {
    final hideUi = ref.watch(videoUiHiddenProvider);
    final hasVideos = _results.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (hasVideos)
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: _results.length,
                onPageChanged: _changePage,
                itemBuilder: (context, index) => TiktokFeedItem(
                  key: ValueKey(_results[index].id),
                  tweet: _results[index],
                  isVisible: index == _index,
                  onLike: _like,
                ),
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _isLoading
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Recherche de vidéos sur X…'),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.ondemand_video_outlined,
                              color: Color(0xFF70F0CE), size: 56),
                          const SizedBox(height: 16),
                          const Text(
                            'Rechercher des vidéos',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Des vidéos de tous les comptes publics sur X, '
                            'même sans les suivre.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                          if (_query.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Aucune vidéo trouvée pour « ' + _query + ' ». '
                              'Essaie d’autres mots-clés.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.orangeAccent),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          if (!hideUi)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
                  color: const Color(0xD9000000),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Retour au fil',
                            icon: const Icon(Icons.arrow_back_rounded),
                            onPressed: () {
                              ref.read(videoUiHiddenProvider.notifier).show();
                              ref.read(navigationProvider.notifier).back();
                            },
                          ),
                          Expanded(
                            child: TextField(
                              controller: _input,
                              focusNode: _focus,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: 'Vidéos, mots-clés, #hashtag…',
                                prefixIcon: const Icon(Icons.search),
                                filled: true,
                                fillColor: const Color(0xFF23282A),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) => unawaited(_runSearch()),
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Lancer la recherche',
                            onPressed: () => unawaited(_runSearch()),
                            icon: const Icon(Icons.search_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Populaires'),
                            selected: _sort == FeedSort.trending,
                            onSelected: (v) {
                              if (v) _setSort(FeedSort.trending);
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Récentes'),
                            selected: _sort == FeedSort.latest,
                            onSelected: (v) {
                              if (v) _setSort(FeedSort.latest);
                            },
                          ),
                          if (hasVideos) ...[
                            const Spacer(),
                            Text(
                              (_index + 1).toString() +
                                  ' / ' +
                                  _results.length.toString(),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (hasVideos && (_isLoading || _loadingMore))
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (hasVideos && _error != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 18,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
