import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation/navigation_provider.dart';
import '../cast/cast_video_button.dart';
import '../player/player_pool_provider.dart';
import '../player/widgets/media_container.dart';
import '../../core/models/tweet.dart';
import '../settings/settings_provider.dart';
import '../settings/settings_screen.dart';
import 'hashtag_provider.dart';
import 'hashtag_blacklist_provider.dart';
import 'local_video_reactions_provider.dart';
import 'widgets/tweet_text_overlay.dart';

class HashtagListScreen extends ConsumerWidget {
  const HashtagListScreen({super.key});

  void _showAddHashtagDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Hashtag'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'e.g. #nature or nature',
            prefixText: '#',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final tag = controller.text.trim();
              if (tag.isNotEmpty) {
                ref.read(hashtagListProvider.notifier).addHashtag(tag);
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showBlockHashtagDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Blacklist de hashtags'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            prefixText: '#',
            hintText: 'Hashtag à exclure des recommandations',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final tag = normalizeBlockedHashtag(controller.text);
                await ref.read(hashtagBlacklistProvider.notifier).add(tag);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Hashtag non ajouté : $error')),
                );
              }
            },
            child: const Text('Bloquer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hashtagsAsync = ref.watch(hashtagListProvider);
    final blockedAsync = ref.watch(hashtagBlacklistProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hashtags'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddHashtagDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (c) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: hashtagsAsync.when(
        data: (tags) => ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            ListTile(
              leading: const Icon(Icons.tag, color: Color(0xFF70F0CE)),
              title: const Text('Hashtags suivis'),
              subtitle: const Text('Favorisent les recommandations Vidéos'),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Suivre un hashtag',
                onPressed: () => _showAddHashtagDialog(context, ref),
              ),
            ),
            if (tags.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Text('Aucun hashtag suivi. Ajoute des sujets qui '
                    't’intéressent pour personnaliser le fil Vidéos.'),
              ),
            for (final tag in tags)
              ListTile(
                leading: const Icon(Icons.tag),
                title: Text(tag),
                onTap: () =>
                    ref.read(navigationProvider.notifier).selectHashtag(tag),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Ne plus suivre $tag',
                  onPressed: () => _confirmDelete(context, ref, tag),
                ),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.block, color: Color(0xFFFF8B8B)),
              title: const Text('Blacklist des hashtags'),
              subtitle: const Text(
                'Ne jamais recommander de vidéos avec ces hashtags. '
                'Le blocage est prioritaire sur les likes et abonnements.',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Bloquer un hashtag',
                onPressed: () => _showBlockHashtagDialog(context, ref),
              ),
            ),
            ...blockedAsync.when(
              data: (blocked) => blocked.isEmpty
                  ? <Widget>[
                      const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Text('Aucun hashtag bloqué.',
                            style: TextStyle(color: Colors.white70)),
                      ),
                    ]
                  : <Widget>[
                      for (final tag in blocked)
                        ListTile(
                          leading: const Icon(Icons.block_outlined,
                              color: Color(0xFFFF8B8B)),
                          title: Text('#$tag'),
                          subtitle: const Text('Exclu des recommandations'),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Débloquer #$tag',
                            onPressed: () async {
                              await ref.read(hashtagBlacklistProvider.notifier)
                                  .remove(tag);
                            },
                          ),
                        ),
                    ],
              loading: () => <Widget>[
                const Center(child: CircularProgressIndicator()),
              ],
              error: (error, stack) =>
                  <Widget>[Text('Blacklist indisponible : $error')],
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Erreur : $error')),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String tag) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Hashtag'),
        content: Text('Are you sure you want to remove $tag?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(hashtagListProvider.notifier).removeHashtag(tag);
              Navigator.pop(context);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class HashtagMediaFeedScreen extends ConsumerStatefulWidget {
  final String hashtag;

  const HashtagMediaFeedScreen({super.key, required this.hashtag});

  @override
  ConsumerState<HashtagMediaFeedScreen> createState() =>
      _HashtagMediaFeedScreenState();
}

class _HashtagMediaFeedScreenState
    extends ConsumerState<HashtagMediaFeedScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _pageController.removeListener(_handleScroll);
    _pageController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page?.round() ?? 0;
    if (page != _currentIndex) {
      setState(() {
        _currentIndex = page;
      });
      _managePool();

      final feedAsync = ref.read(hashtagMediaProvider(widget.hashtag));
      if (feedAsync.hasValue) {
        final tweets = feedAsync.value!.tweets;
        final settings = ref.read(settingsProvider);
        if (page >= tweets.length - settings.lazyLoadThreshold &&
            !feedAsync.value!.isLoadingMore) {
          ref.read(hashtagMediaProvider(widget.hashtag).notifier).fetchMore();
        }
      }
    }
  }

  void _managePool() {
    Future.microtask(() {
      if (!mounted) return;
      final feedAsync = ref.read(hashtagMediaProvider(widget.hashtag));
      final state = feedAsync.value;
      if (state == null) return;
      final tweets = state.tweets;
      if (ref.read(navigationProvider).selectedHashtag == widget.hashtag) {
        ref.read(castPlaylistProvider.notifier).state =
            List<Tweet>.unmodifiable(tweets);
      }

      final pool = ref.read(playerPoolProvider.notifier);
      final activeIds = <String>{};

      for (int i = _currentIndex - 1; i <= _currentIndex + 3; i++) {
        if (i >= 0 && i < tweets.length) {
          final tweet = tweets[i];
          activeIds.add(tweet.id);
          if (tweet.isVideo && tweet.mediaUrls.isNotEmpty) {
            pool.warmup(tweet.id, tweet.mediaUrls.first);
          }
        }
      }
      pool.cleanupExcept(activeIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(hashtagMediaProvider(widget.hashtag));
    final reactions = ref.watch(localVideoReactionsProvider).value;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => ref.read(navigationProvider.notifier).back(),
        ),
        title: Text(widget.hashtag,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _pageController.jumpToPage(0);
              ref.read(hashtagMediaProvider(widget.hashtag).notifier).refresh();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (c) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: feedAsync.when(
        data: (state) {
          final tweets = state.tweets.where(
            (tweet) => reactions?[tweet.id]?.value != -1,
          ).toList();
          if (tweets.isEmpty) {
            return const Center(
                child: Text('No media found',
                    style: TextStyle(color: Colors.white70)));
          }

          _managePool();

          return Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: tweets.length,
                itemBuilder: (context, index) {
                  final settings = ref.read(settingsProvider);
                  return HashtagFeedItem(
                    key: ValueKey('hash_feed_${tweets[index].id}'),
                    tweet: tweets[index],
                    isVisible: index == _currentIndex,
                    onDislike: () {
                      if (!mounted || index != _currentIndex) return;
                      // The optimistic local reaction filters the current
                      // clip immediately and reveals the next one.
                      if (index >= tweets.length - 1) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted || !_pageController.hasClients) return;
                          _pageController.jumpToPage(
                              (tweets.length - 2).clamp(0, tweets.length));
                          setState(() => _currentIndex =
                              (tweets.length - 2).clamp(0, tweets.length));
                        });
                      }
                    },
                    onPlaybackError: () {
                      if (index == _currentIndex && mounted) {
                        Future.delayed(
                            Duration(seconds: settings.autoSkipDelaySeconds),
                            () {
                          if (mounted && _currentIndex == index) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        });
                      }
                    },
                  );
                },
              ),
              if (state.isLoadingMore || state.isRefreshing)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error: $e', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref
                    .read(hashtagMediaProvider(widget.hashtag).notifier)
                    .refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class HashtagFeedItem extends StatelessWidget {
  final Tweet tweet;
  final bool isVisible;
  final bool autoFullscreen;
  final VoidCallback? onPlaybackError;
  final VoidCallback? onDislike;

  const HashtagFeedItem({
    super.key,
    required this.tweet,
    required this.isVisible,
    this.autoFullscreen = false,
    this.onPlaybackError,
    this.onDislike,
  });

  @override
  Widget build(BuildContext context) {
    return TiktokMediaContainer(
      tweet: tweet,
      isVisible: isVisible,
      autoFullscreen: autoFullscreen,
      overlayBuilder: (context, onFullscreen, isFullscreen) => TweetTextOverlay(
        tweet: tweet,
        onFullscreen: onFullscreen,
        isFullscreen: isFullscreen,
        onDislike: onDislike,
      ),
      onDislike: onDislike,
      onPlaybackError: onPlaybackError,
    );
  }
}
