import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/core/models/tweet.dart';
import 'package:xflow/features/search/video_search_utils.dart';

void main() {
  test('search terms accept keywords and hashtags', () {
    expect(normalizeVideoSearch('  football   féminin '), 'football féminin');
    expect(normalizeVideoSearch(' #Paris\n spectacle '), '#Paris spectacle');
    expect(normalizeVideoSearch('   '), isEmpty);
  });
  test('all public accounts can appear, but only playable MP4s are kept', () {
    final video = Tweet(
      id: '123', text: 'Football', userHandle: '@not_followed',
      isVideo: true,
      mediaUrls: const ['https://video.twimg.com/clip.mp4?tag=12'],
    );
    final image = Tweet(
      id: '124', text: 'Image', userHandle: '@other',
      mediaUrls: const ['https://pbs.twimg.com/image.jpg'],
    );
    final hls = Tweet(
      id: '125', text: 'HLS', userHandle: '@other',
      isVideo: true, mediaUrls: const ['https://video.twimg.com/clip.m3u8'],
    );
    expect(videoSearchResults([video, image, hls, video]), [video]);
  });
}
