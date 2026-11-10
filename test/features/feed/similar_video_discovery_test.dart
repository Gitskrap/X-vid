import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/feed/similar_video_discovery.dart';

Tweet clip(String id, String caption, {String author = '@saved'}) => Tweet(
  id: id,
  text: caption,
  userHandle: author,
  isVideo: true,
  mediaUrls: const ['https://video.twimg.com/a.mp4'],
);

void main() {
  test('hashtags of subscribed videos drive related-topic discovery', () {
    final topics = topicsFromSubscribedVideos([
      clip('1', 'Match du soir #Babyfoot #Sport'),
      clip('2', 'Tournoi #Babyfoot incroyable'),
      clip('3', 'Une vidéo sans rapport'),
    ]);
    expect(topics.first, 'babyfoot');
    expect(topics, isNot(contains('http')));
  });

  test('repeated meaningful caption terms work without hashtags', () {
    final topics = topicsFromSubscribedVideos([
      clip('4', 'Belles compétitions internationales'),
      clip('5', 'Préparation des compétitions à venir'),
    ]);
    expect(topics, contains('compétitions'));
  });

  test('unrelated single captions are insufficient to suggest a genre', () {
    final topics = topicsFromSubscribedVideos([
      clip('6', 'Hibiscus extraordinaire'),
    ]);
    expect(topics, isEmpty);
  });

  test('mix respects one discovery for every three followed videos', () {
    final following = [
      for (var i = 0; i < 6; i++) clip('a$i', 'sports #babyfoot'),
    ];
    final related = [
      for (var i = 0; i < 5; i++)
        clip('b$i', 'related', author: '@unfollowed'),
    ];
    final mixed = mixRelatedVideos(following, related);
    expect(mixed.length, 8);
    expect(mixed[3].source, 'Découverte');
    expect(mixed[7].source, 'Découverte');
    expect(mixed.take(3).every((t) => t.userHandle == '@saved'), isTrue);
  });

  test('duplicates suppressed; interests can suggest without subscriptions', () {
    final saved = [clip('7', '#babyfoot')];
    expect(mixRelatedVideos(saved, [saved.single]), saved);
    final discovered = mixRelatedVideos([], [clip('8', '#babyfoot')]);
    expect(discovered.map((t) => t.id), ['8']);
    expect(discovered.first.source, 'Découverte');
  });
}
