import '../../core/models/local_video_reaction.dart';
import '../../core/models/tweet.dart';
import 'similar_video_discovery.dart';

/// Lightweight, on-device recommendation signals from captions/hashtags.
/// No personal like/dislike data is sent to X or to a recommendation server.
const _stopWords = <String>{
  'video', 'videos', 'vidéo', 'vidéos', 'watch', 'follow', 'subscribe',
  'twitter', 'https', 'http', 'today', 'demain', 'avec', 'pour', 'dans',
  'vous', 'nous', 'tous', 'tout', 'cette', 'comme', 'plus', 'moins',
  'from', 'this', 'that', 'with', 'have', 'your', 'just', 'next',
  'what', 'when', 'where', 'pourquoi', 'merci', 'bonjour', 'because',
  'here', 'there', 'part', 'dont', 'about', 'the', 'and', 'regarde',
  'regardez', 'voir', 'bien', 'bonne', 'great', 'fresh', 'original',
  'posting', 'viral', 'latest', 'youtu', 'com',
};

Set<String> captionHashtags(String caption) => RegExp(r'#[\wÀ-ÿ]{3,30}')
    .allMatches(caption)
    .map((match) => match.group(0)!.substring(1).toLowerCase())
    .where((word) => !_stopWords.contains(word))
    .toSet();

Set<String> captionKeywords(String caption) {
  final cleaned = caption
      .replaceAll(RegExp(r'https?://\S+'), ' ')
      .replaceAll(RegExp(r'@[A-Za-z0-9_]+'), ' ');
  return RegExp(r'[A-Za-zÀ-ÿ]{4,30}')
      .allMatches(cleaned)
      .map((match) => match.group(0)!.toLowerCase())
      .where((word) => !_stopWords.contains(word))
      .toSet();
}

/// Disliking a clip removes that exact video and suppresses recommendations
/// with matching hashtags or sufficiently overlapping descriptive keywords.
/// A single generic shared word is not usually evidence of the same genre.
bool excludedByFeedback(
    Tweet candidate, Map<String, LocalVideoReaction> reactions) {
  if (reactions[candidate.id]?.value == -1) return true;
  if (reactions[candidate.id]?.value == 1) return false;
  final tags = captionHashtags(candidate.text);
  final words = captionKeywords(candidate.text);
  if (tags.isEmpty && words.isEmpty) return false;

  for (final feedback in reactions.values) {
    if (feedback.value != -1) continue;
    final dislikedTags = captionHashtags(feedback.caption);
    if (tags.intersection(dislikedTags).isNotEmpty) return true;
    final negativeWords = captionKeywords(feedback.caption);
    final common = words.intersection(negativeWords);
    if (common.length >= 2) return true;
    if (common.length == 1 &&
        common.first.length >= 7 &&
        (words.length <= 2 || negativeWords.length <= 2)) {
      return true;
    }
  }
  return false;
}

List<Tweet> filterByFeedback(
        Iterable<Tweet> videos, Map<String, LocalVideoReaction> reactions) =>
    videos.where((video) => !excludedByFeedback(video, reactions)).toList();

/// Local liked videos become stronger genre signals than passive follows.
/// A negative signal is never used to generate a search query.
List<String> personalizedVideoTopics(
  Iterable<Tweet> savedSubscriptionVideos,
  Map<String, LocalVideoReaction> reactions, {
  int limit = 3,
  Iterable<String> followedHashtags = const <String>[],
  Iterable<Tweet> watchedVideos = const <Tweet>[],
}) {
  final scores = <String, int>{};
  for (final topic in topicsFromSubscribedVideos(savedSubscriptionVideos,
      limit: 8)) {
    scores[topic] = (scores[topic] ?? 0) + 2;
  }

  // Videos actually watched for several seconds are evidence of interest,
  // not just an incidental swipe. They are softer signals than explicit likes.
  for (final video in watchedVideos) {
    if (!video.isVideo || video.text.trim().isEmpty) continue;
    for (final tag in captionHashtags(video.text)) {
      scores[tag] = (scores[tag] ?? 0) + 4;
    }
    for (final word in captionKeywords(video.text)) {
      scores[word] = (scores[word] ?? 0) + 1;
    }
  }

  // Explicitly followed hashtags are stronger than passive subscriptions.
  // A negative reaction still overrides them below.
  final distinctTags = <String>{};
  for (final hashtag in followedHashtags) {
    final topic = hashtag.trim().replaceFirst(RegExp(r'^#+'), '').toLowerCase();
    if (RegExp(r'^[\wÀ-ÿ]{2,40}$').hasMatch(topic) &&
        !_stopWords.contains(topic) && distinctTags.add(topic)) {
      scores[topic] = (scores[topic] ?? 0) + 6;
    }
  }

  final rejectedTags = <String>{};
  final rejectedWords = <String>{};
  for (final feedback in reactions.values) {
    if (feedback.value == -1) {
      rejectedTags.addAll(captionHashtags(feedback.caption));
      rejectedWords.addAll(captionKeywords(feedback.caption));
    }
  }
  for (final feedback in reactions.values) {
    if (feedback.value != 1) continue;
    for (final tag in captionHashtags(feedback.caption)) {
      scores[tag] = (scores[tag] ?? 0) + 8;
    }
    for (final word in captionKeywords(feedback.caption)) {
      scores[word] = (scores[word] ?? 0) + 3;
    }
  }
  // Rejected themes should not initiate new discovery requests.
  scores.removeWhere((topic, score) =>
      rejectedTags.contains(topic) ||
      (rejectedWords.contains(topic) && score <= 8));
  final ranked = scores.entries.toList()
    ..sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      return byScore == 0 ? a.key.compareTo(b.key) : byScore;
    });
  return ranked.take(limit).map((entry) => entry.key).toList();
}
