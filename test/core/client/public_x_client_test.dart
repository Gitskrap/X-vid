import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xflow/core/client/public_x_client.dart';

void main() {

  test('public keyword video search sends no authentication headers', () async {
    final client = PublicXClient(client: MockClient((request) async {
      expect(request.url.host, 'api.fxtwitter.com');
      expect(request.url.path, '/2/search');
      expect(request.url.queryParameters['q'], 'paris filter:videos');
      expect(request.url.queryParameters['feed'], 'top');
      expect(request.url.queryParameters['cursor'], 'previous');
      expect(request.headers.containsKey('Cookie'), false);
      expect(request.headers.containsKey('authorization'), false);
      return http.Response(jsonEncode({
        'code': 200,
        'results': [],
        'cursor': {'bottom': 'next'},
      }), 200);
    }));
    final response = await client.searchVideos(
      'paris', top: true, cursor: 'previous');
    expect(response.tweets, isEmpty);
    expect(response.cursorBottom, 'next');
  });

  test('public account discovery decodes real user fields', () {
    final users = PublicXClient.decodeSuggestions({
      'code': 200,
      'users': [
        {
          'id': '123',
          'screen_name': 'NASA',
          'name': 'NASA',
          'avatar_url': 'https://pbs.twimg.com/a.jpg',
          'followers': 100,
          'following': 12,
        },
        {
          'id': '123',
          'screen_name': 'nasa',
          'name': 'Duplicate',
        },
        {
          'screen_name': 'Private',
          'name': 'Not visible',
          'protected': true,
        },
      ],
    });
    expect(users, hasLength(1));
    expect(users.single.screenName, 'NASA');
    expect(users.single.followersCount, 100);
  });

  test('public media parser keeps actual MP4s, sorted by bitrate', () {
    final tweets = PublicXClient.decodeMediaResults({
      'code': 200,
      'results': [
        {
          'type': 'status',
          'id': '1721234567890123456',
          'text': 'Video',
          'created_timestamp': 1700000000,
          'likes': 42,
          'replies': 2,
          'author': {
            'screen_name': 'NASA',
            'avatar_url': 'https://pbs.twimg.com/a.jpg',
          },
          'media': {
            'videos': [
              {
                'thumbnail_url': 'https://pbs.twimg.com/thumb.jpg',
                'formats': [
                  {
                    'container': 'mp4',
                    'bitrate': 256000,
                    'url': 'https://video.twimg.com/low.mp4',
                  },
                  {
                    'container': 'mp4',
                    'bitrate': 832000,
                    'url': 'https://video.twimg.com/high.mp4',
                  },
                  {
                    'container': 'm3u8',
                    'url': 'https://video.twimg.com/video.m3u8',
                  },
                ],
              },
            ],
          },
        },
      ],
    });
    expect(tweets, hasLength(1));
    expect(tweets.first.mediaUrls, [
      'https://video.twimg.com/high.mp4',
      'https://video.twimg.com/low.mp4',
    ]);
    expect(tweets.first.favoriteCount, 42);
    expect(tweets.first.replyCount, 2);
    expect(tweets.first.favoriteCountKnown, true);
  });

  test('empty public video pages are distinct from malformed responses', () {
    expect(PublicXClient.decodeMediaResults({'results': []}), isEmpty);
    expect(
      () => PublicXClient.decodeMediaResults({'invalid': []}),
      throwsFormatException,
    );
  });
}
