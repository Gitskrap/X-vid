import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/client/twitter_account.dart';
import '../../core/client/account_provider.dart';
import '../../core/client/twitter_client.dart';
import '../../core/client/public_x_client.dart';
import '../auth/login_screen.dart';
import '../../core/database/repository.dart';
import '../../core/models/tweet.dart';
import '../../core/navigation/navigation_provider.dart';
import '../feed/feed_provider.dart';
import '../feed/tiktok_feed_screen.dart';
import '../feed/local_video_reactions_provider.dart';
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
  bool _usingPublicSearch = false;
  bool _usingCachedSearch = false;
  bool _poolScheduled = false;

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
        _usingPublicSearch = false;
        _usingCachedSearch = false;
        _index = 0;
        _isLoading = true;
        _error = null;
      });
    }

    final requestVersion = _searchVersion;
    final cursor = _cursor;

    try {
      // Prefer the signed-in X timeline when available. If it fails or
      // returns no videos, fall back to public FxEmbed without X credentials.
      // Keep the same provider for subsequent cursor pages.
      bool usePublic = more
          ? _usingPublicSearch
          : !TwitterAccount.hasAuthSession(ref.read(accountProvider));
      late TweetResponse response;
      Future<TweetResponse> publicSearch() => PublicXClient().searchVideos(
        text,
        cursor: more ? cursor : null,
        count: 30,
        top: _sort == FeedSort.trending || _sort == FeedSort.popular,
      );
      if (usePublic) {
        response = await publicSearch();
      } else {
        try {
          response = await ref.read(twitterClientProvider).fetchTrendingMedia(
            query: text,
            sort: _sort,
            filters: const {MediaFilter.video},
            cursor: more ? cursor : null,
            count: 30,
            timeoutSeconds: 20,
            reportErrors: true,
          );
          if (!more && videoSearchResults(response.tweets).isEmpty) {
            usePublic = true;
            response = await publicSearch();
          }
        } catch (error) {
          debugPrint('X authenticated search failed, trying public: $error');
          usePublic = true;
          response = await publicSearch();
        }
      }
      if (!mounted || _searchVersion != requestVersion) return;

      final reactions = ref.read(localVideoReactionsProvider).value;
      var videos = videoSearchResults(response.tweets)
          .where((tweet) => reactions?[tweet.id]?.value != -1).toList();
      bool cacheOnly = false;
      if (!more && videos.isEmpty) {
        videos = (await Repository.getHashtagCachedMedia(text, 50,
          filters: const {MediaFilter.video}))
          .where((tweet) => reactions?[tweet.id]?.value != -1).toList();
        cacheOnly = videos.isNotEmpty;
      }
      final knownIds = _results.map((tweet) => tweet.id).toSet();
      final additional = videos.where((tweet) => !knownIds.contains(tweet.id));
      setState(() {
        _results = more ? [..._results, ...additional] : videos;
        _usingPublicSearch = usePublic;
        _usingCachedSearch = cacheOnly;
        _cursor = cacheOnly ? null : response.cursorBottom;
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
      if (!more) {
        try {
          final local = await Repository.getHashtagCachedMedia(
              text, 50, filters: const {MediaFilter.video});
          if (!mounted || _searchVersion != requestVersion) return;
          final reactions = ref.read(localVideoReactionsProvider).value;
          final accepted = local.where((tweet) =>
              reactions?[tweet.id]?.value != -1).toList();
          if (accepted.isNotEmpty) {
            setState(() {
              _results = accepted;
              _usingCachedSearch = true;
              _hasMore = false;
              _cursor = null;
              _error = null;
            });
            _warmupPlayers();
            return;
          }
        } catch (_) {
          // Keep the original error if the local database also fails.
        }
      }
      if (mounted) {
        setState(() => _error =
          'Recherche en ligne indisponible. Vérifie la connexion ou '
          'essaie de nouveau : $error');
      }
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

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _connectToX() async {
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (!mounted || connected != true) return;
    if (_query.isNotEmpty) {
      unawaited(_runSearch());
    } else {
      setState(() => _error = null);
    }
  }

  void _setSort(FeedSort sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    if (_query.isNotEmpty) unawaited(_runSearch());
  }

  @override
  Widget build(BuildContext context) {
    final hideUi = ref.watch(videoUiHiddenProvider);
    final account = ref.watch(accountProvider);
    final signedIn = TwitterAccount.hasAuthSession(account);
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
                  onDislike: () {
                    if (!mounted || index != _index) return;
                    setState(() {
                      _results.removeAt(index);
                      if (_results.isNotEmpty && _index >= _results.length) {
                        _index = _results.length - 1;
                      }
                    });
                    if (_results.isNotEmpty && index >= _results.length) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _pageController.hasClients) {
                          _pageController.jumpToPage(_index);
                        }
                      });
                    }
                    if (_hasMore && _results.length - _index < 4) {
                      unawaited(_runSearch(more: true));
                    }
                    _warmupPlayers();
                  },
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
                            'Rechercher les vidéos de comptes publics, '
                            'même sans être abonné à ces comptes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                          if (!signedIn) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Recherche publique disponible sans connexion. '
                              'Connecte-toi pour tenter aussi la recherche X.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.orangeAccent),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: _connectToX,
                              icon: const Icon(Icons.login_rounded),
                              label: const Text('Se connecter à X'),
                            ),
                          ],
                          if (_query.isNotEmpty && _error == null) ...[
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
          if (_usingCachedSearch && !hideUi && hasVideos)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 132,
              left: 14,
              child: const Chip(
                avatar: Icon(Icons.offline_bolt_outlined, size: 16),
                label: Text('Résultats enregistrés · hors ligne'),
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
