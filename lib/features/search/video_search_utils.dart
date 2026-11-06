import '../../core/models/tweet.dart';

String normalizeVideoSearch(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Preserve only unique playable MP4 videos; exclude X search photo results.
List<Tweet> videoSearchResults(Iterable<Tweet> source) {
  final seen = <String>{};
  return [
    for (final tweet in source)
      if (tweet.isVideo &&
          tweet.mediaUrls.any((url) =>
              Uri.tryParse(url)?.path.toLowerCase().endsWith('.mp4') == true) &&
          seen.add(tweet.id))
        tweet,
  ];
}
