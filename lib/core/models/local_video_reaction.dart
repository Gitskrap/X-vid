/// A private preference stored only on this device, never sent to X.
class LocalVideoReaction {
  const LocalVideoReaction({
    required this.videoId,
    required this.value,
    required this.caption,
    required this.author,
  });

  final String videoId;
  /// 1 = liked, -1 = disliked. Neutral videos have no stored row.
  final int value;
  final String caption;
  final String author;
}
