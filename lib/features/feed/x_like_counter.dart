import '../../core/models/tweet.dart';

/// Public likes returned by X (or last known X metadata cached locally).
/// The app's private likes/dislikes are stored in a separate table and must
/// NEVER change this displayed public counter.
String publicXLikeCountLabel(Tweet tweet) {
  if (!tweet.favoriteCountKnown) return 'X · —';
  final count = tweet.favoriteCount;
  if (count >= 1000000) {
    return 'X · ${(count / 1000000).toStringAsFixed(1)}M';
  }
  if (count >= 1000) {
    return 'X · ${(count / 1000).toStringAsFixed(1)}K';
  }
  return 'X · $count';
}
