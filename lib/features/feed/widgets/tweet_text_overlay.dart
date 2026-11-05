import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../../core/models/tweet.dart';
import '../../../core/navigation/navigation_provider.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/database/entities.dart';
import '../../subscriptions/subscription_list_screen.dart';
import '../feed_provider.dart';
import '../tweet_detail_screen.dart';

class TweetTextOverlay extends ConsumerStatefulWidget {
  final Tweet tweet;
  final VoidCallback? onFullscreen;
  final bool isFullscreen;

  const TweetTextOverlay({
    super.key,
    required this.tweet,
    this.onFullscreen,
    this.isFullscreen = false,
  });

  @override
  ConsumerState<TweetTextOverlay> createState() => _TweetTextOverlayState();
}

class _TweetTextOverlayState extends ConsumerState<TweetTextOverlay> {
  @override
  Widget build(BuildContext context) {
    final bottomPadding = widget.isFullscreen ? 48.0 : 12.0;
    final rightPadding = widget.isFullscreen ? 24.0 : 8.0;

    return Stack(
      children: [
        // Text Overlay (Bottom)
        Positioned(
          bottom: bottomPadding,
          left: 12,
          right: widget.isFullscreen ? 100 : 78,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xE91B1E23),
              border: Border.all(color: const Color(0x70FFFFFF)),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 5)),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildUserHeader(context),
                if (widget.tweet.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildTweetText(),
                ],
              ],
            ),
          ),
        ),
        // Action Buttons (Right Side)
        Positioned(
          right: rightPadding,
          bottom: widget.isFullscreen ? 60 : 24,
          child: _buildActionButtons(),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: widget.tweet.isLiked ? Icons.favorite : Icons.favorite_border,
          color: widget.tweet.isLiked ? Colors.red : Colors.white,
          label: _formatCount(widget.tweet.favoriteCount),
          onTap: () {
            ref.read(feedNotifierProvider.notifier).toggleLike(widget.tweet.id);
          },
        ),
        const SizedBox(height: 16),
        _ActionButton(
          icon: Icons.chat_bubble_outline,
          label: _formatCount(widget.tweet.replyCount),
          onTap: () {
            TweetRepliesSheet.show(context, widget.tweet);
          },
        ),
        const SizedBox(height: 16),
        _ActionButton(
          icon: Icons.share_outlined,
          label: "Share",
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Share functionality coming soon!"),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        if (widget.onFullscreen != null && widget.tweet.isVideo) ...[
          const SizedBox(height: 16),
          _ActionButton(
            icon:
                widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            label: widget.isFullscreen ? "Exit" : "Full",
            onTap: widget.onFullscreen!,
          ),
        ],
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  Widget _buildUserHeader(BuildContext context) {
    final subscriptionState = ref.watch(subscriptionListProvider);
    final isSubscribed = subscriptionState.isSubscribed(widget.tweet.userHandle);

    String dateStr = 'Date indisponible';
    if (widget.tweet.createdAt != null) {
      try {
        final date = widget.tweet.createdAt!.toLocal();
        dateStr = 'Publié le ${DateFormat('dd/MM/yyyy · HH:mm').format(date)}';
      } catch (e) {
        AppLogger.log('XFLOW: Error formatting date: $e');
        dateStr = 'Date indisponible';
      }
    }

    return Row(
      children: [
        GestureDetector(
          onTap: () {
            final handle = widget.tweet.userHandle.replaceFirst('@', '');
            ref.read(navigationProvider.notifier).selectUser(handle);
          },
          child: CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white24,
            backgroundImage: widget.tweet.userAvatarUrlHighRes != null
                ? CachedNetworkImageProvider(widget.tweet.userAvatarUrlHighRes!)
                : null,
            child: widget.tweet.userAvatarUrlHighRes == null
                ? const Icon(Icons.person, color: Colors.white, size: 20)
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  final handle = widget.tweet.userHandle.replaceFirst('@', '');
                  ref.read(navigationProvider.notifier).selectUser(handle);
                },
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.tweet.userHandle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          shadows: [
                            Shadow(
                                offset: Offset(0, 1),
                                blurRadius: 2,
                                color: Colors.black54),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSubscribed) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.check_circle,
                          color: Colors.blueAccent, size: 16),
                    ],
                  ],
                ),
              ),
              if (dateStr.isNotEmpty)
                Text(
                  dateStr,
                  style: const TextStyle(
                    color: const Color(0xFFE5ECF0),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    shadows: [
                      Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 2,
                          color: Colors.black54),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (!isSubscribed)
          IconButton(
            onPressed: () {
              ref.read(subscriptionListProvider.notifier).toggleSubscription(
                    Subscription(
                      id: widget.tweet.userHandle,
                      screenName: widget.tweet.userHandle.replaceFirst('@', ''),
                      name: widget.tweet.userHandle,
                      profileImageUrl: widget.tweet.userAvatarUrl,
                    ),
                  );
            },
            icon: const Icon(Icons.add, color: Colors.white, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: Colors.blueAccent.withValues(alpha: 0.6),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            tooltip: 'Subscribe',
          ),
      ],
    );
  }

  void _showFullPost() {
    final date = widget.tweet.createdAt == null
        ? 'Date indisponible'
        : 'Publié le ${DateFormat('dd/MM/yyyy à HH:mm').format(widget.tweet.createdAt!.toLocal())}';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF171A1F),
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.tweet.userHandle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(date, style: const TextStyle(color: Color(0xFFE1E6EA), fontSize: 14)),
              const SizedBox(height: 22),
              SelectableText(
                widget.tweet.text,
                style: const TextStyle(fontSize: 17, height: 1.5, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTweetText() {
    final text = widget.tweet.text;
    final List<InlineSpan> spans = [];

    // Simple hashtag and mention parsing
    // We need to preserve whitespace, but Dart's split() with RegExp doesn't keep groups.
    final List<String> words = [];
    final matches = RegExp(r'(\s+)').allMatches(text);
    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        words.add(text.substring(lastEnd, match.start));
      }
      words.add(text.substring(match.start, match.end));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      words.add(text.substring(lastEnd));
    }

    for (final word in words) {
      if (word.startsWith('#') && word.length > 1) {
        spans.add(
          WidgetSpan(
            child: GestureDetector(
              onTap: () {
                ref.read(navigationProvider.notifier).selectHashtag(word);
              },
              child: Text(
                word,
                style: const TextStyle(
                  color: Colors.lightBlueAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        );
      } else if (word.startsWith('@') && word.length > 1) {
        spans.add(
          WidgetSpan(
            child: GestureDetector(
              onTap: () {
                final handle = word.replaceFirst('@', '');
                ref.read(navigationProvider.notifier).selectUser(handle);
              },
              child: Text(
                word,
                style: const TextStyle(
                  color: Colors.lightBlueAccent,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: word));
      }
    }

    return GestureDetector(
      onTap: _showFullPost,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              children: spans,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
                shadows: [
                  Shadow(
                      offset: Offset(0, 1), blurRadius: 2, color: Colors.black),
                ],
              ),
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.tweet.text.length > 100)
            const Padding(
              padding: EdgeInsets.only(top: 4.0),
              child: Text(
                'Lire le tweet complet',
                style: TextStyle(
                  color: Color(0xFF70F0CE),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    this.color = Colors.white,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
              ),
              child: Icon(
                icon,
                color: color,
                size: 32,
                shadows: const [
                  Shadow(
                      offset: Offset(0, 1), blurRadius: 4, color: Colors.black),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 2,
                      color: Colors.black54),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
