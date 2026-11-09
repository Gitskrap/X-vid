import '../../core/models/tweet.dart';

/// Infers search keywords from captions of videos published by locally saved
/// creators. It never uses X's followed accounts or generic trending topics.
List<String> topicsFromSubscribedVideos(
  Iterable<Tweet> followedVideos, {
  int limit = 2,
}) {
  final scores = <String, int>{};
  const ignored = <String>{
    'video', 'videos', 'vidéo', 'vidéos', 'watch', 'follow', 'subscribe',
    'twitter', 'https', 'http', 'today', 'demain', 'avec', 'pour', 'dans',
    'vous', 'nous', 'tous', 'tout', 'cette', 'comme', 'plus', 'moins',
    'from', 'this', 'that', 'with', 'have', 'your', 'just', 'new', 'next',
    'what', 'when', 'where', 'pourquoi', 'merci', 'bonjour', 'because',
    'here', 'there', 'part', 'dont', 'dont', 'about', 'the', 'and',
    'regarde', 'regardez', 'voir', 'bien', 'bonne', 'great', 'fresh',
    'original', 'posting', 'viral', 'latest',
  };
  for (final tweet in followedVideos) {
    if (!tweet.isVideo || tweet.text.trim().isEmpty) continue;
    final text = tweet.text.replaceAll(RegExp(r'https?://\S+'), ' ');
    final hashtags = RegExp(r'#[\wÀ-ÿ]{3,25}')
        .allMatches(text)
        .map((m) => m.group(0)!.substring(1).toLowerCase())
        .toSet();
    for (final tag in hashtags) {
      if (!ignored.contains(tag)) scores[tag] = (scores[tag] ?? 0) + 4;
    }
    // Repeat meaningful caption terms are weaker signals than hashtags.
    final words = RegExp(r'[A-Za-zÀ-ÿ]{5,24}')
        .allMatches(text.replaceAll(RegExp(r'@[A-Za-z0-9_]+'), ' '))
        .map((m) => m.group(0)!.toLowerCase())
        .where((word) => !ignored.contains(word) && !hashtags.contains(word))
        .toSet();
    for (final word in words) {
      scores[word] = (scores[word] ?? 0) + 1;
    }
  }
  final ranked = scores.entries.where((entry) => entry.value >= 2).toList()
    ..sort((a, b) {
      final score = b.value.compareTo(a.value);
      return score != 0 ? score : a.key.compareTo(b.key);
    });
  return ranked.take(limit).map((entry) => entry.key).toList();
}

/// Feed remains primarily the local subscriptions: one discovery video after
/// every three local videos. Old recommendations cannot crowd out followees.
List<Tweet> mixRelatedVideos(
  List<Tweet> subscriptions,
  List<Tweet> recommendations, {
  int interval = 3,
}) {
  if (subscriptions.isEmpty || recommendations.isEmpty) return subscriptions;
  final seen = subscriptions.map((t) => t.id).toSet();
  final suggested = recommendations
      .where((t) => t.isVideo && t.mediaUrls.isNotEmpty && seen.add(t.id))
      .toList();
  if (suggested.isEmpty) return subscriptions;
  final output = <Tweet>[];
  var index = 0;
  for (final item in subscriptions) {
    output.add(item);
    if (output.length > 0 &&
        output.where((t) => t.source != 'Découverte').length % interval == 0 &&
        index < suggested.length) {
      output.add(suggested[index++].copyWith(source: 'Découverte'));
    }
  }
  return output;
}
