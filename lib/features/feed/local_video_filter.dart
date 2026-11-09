import '../../core/database/entities.dart';
import '../../core/models/tweet.dart';

/// Only the locally saved Twitter vidéo subscriptions define the home feed.
/// These are independent of the accounts followed on X.
Set<String> localVideoHandles(Iterable<Subscription> subscriptions) =>
    subscriptions
        .map((sub) => sub.screenName.replaceFirst('@', '').trim().toLowerCase())
        .where((handle) => handle.isNotEmpty)
        .toSet();

List<Tweet> onlyLocalSubscriptionVideos(
  Iterable<Tweet> tweets,
  Set<String> savedHandles,
) {
  if (savedHandles.isEmpty) return const [];
  return tweets.where((tweet) {
    final handle = tweet.userHandle
        .replaceFirst('@', '')
        .trim()
        .toLowerCase();
    return tweet.isVideo &&
        tweet.mediaUrls.isNotEmpty &&
        savedHandles.contains(handle);
  }).toList();
}
