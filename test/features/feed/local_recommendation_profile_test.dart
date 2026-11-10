import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/core/models/local_video_reaction.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/feed/local_recommendation_profile.dart';

Tweet video(String id, String caption) => Tweet(
  id: id,
  text: caption,
  userHandle: '@creator',
  isVideo: true,
  mediaUrls: const ['https://video.twimg.com/demo.mp4'],
);

LocalVideoReaction feedback(String id, int value, String caption) =>
    LocalVideoReaction(
      videoId: id, value: value, caption: caption, author: '@creator',
    );

void main() {
  test('local likes seed personalized topics without a subscribed hashtag', () {
    final reactions = {
      'liked': feedback('liked', 1, '#Babyfoot #Kickertournament super match'),
    };
    final topics = personalizedVideoTopics([], reactions);
    expect(topics, contains('babyfoot'));
    expect(topics, contains('kickertournament'));
  });

  test('dislikes stop querying rejected hashtags', () {
    final reactions = {
      'liked': feedback('liked', 1, '#Babyfoot #Cats amazing'),
      'disliked': feedback('disliked', -1, '#Cats #Animals'),
    };
    final topics = personalizedVideoTopics([], reactions);
    expect(topics, contains('babyfoot'));
    expect(topics, isNot(contains('cats')));
  });

  test('disliked video and related hashtag clips are excluded', () {
    final reactions = {
      'bad': feedback('bad', -1, 'Impossible de voir ce #Horror trailer'),
    };
    expect(excludedByFeedback(video('bad', 'No information'), reactions), isTrue);
    expect(excludedByFeedback(video('next', 'New #Horror movie'), reactions), isTrue);
    expect(excludedByFeedback(video('other', '#Babyfoot match'), reactions), isFalse);
  });

  test('two matching descriptive words suppress a genre without hashtags', () {
    final reactions = {
      'bad': feedback('bad', -1, 'Boring underwater cave exploration'),
    };
    expect(
      excludedByFeedback(video('a', 'underwater cave expedition'), reactions),
      isTrue,
    );
    expect(
      excludedByFeedback(video('b', 'underwater football match'), reactions),
      isFalse,
    );
  });

  test('liked exact video stays visible even if it overlaps a rejected genre', () {
    final reactions = {
      'bad': feedback('bad', -1, '#Surfing tonight'),
      'good': feedback('good', 1, '#Surfing special'),
    };
    expect(excludedByFeedback(video('good', '#Surfing special'), reactions),
        isFalse);
  });

  test('dislikes remove only matching videos, likes do not change X data', () {
    final reactions = {
      'bad': feedback('bad', -1, '#Horror bad'),
    };
    final items = filterByFeedback([
      video('b', '#Horror games'),
      video('c', '#Babyfoot games'),
    ], reactions);
    expect(items.map((t) => t.id), ['c']);
  });
}
