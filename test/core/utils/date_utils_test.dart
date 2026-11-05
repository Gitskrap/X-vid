import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/core/utils/date_utils.dart';
import 'package:xflow/core/models/tweet.dart';

void main() {
  test('classic Twitter UTC timestamp', () {
    expect(
      parseTwitterDateTime('Wed Oct 10 20:19:24 +0000 2018'),
      DateTime.utc(2018, 10, 10, 20, 19, 24),
    );
  });

  test('Twitter timestamp with offset', () {
    expect(
      parseTwitterDateTime('Thu Nov 05 12:00:00 +0100 2026'),
      DateTime.utc(2026, 11, 5, 11),
    );
  });

  test('ISO timestamp', () {
    expect(
      parseTwitterDateTime('2026-11-05T11:00:00Z'),
      DateTime.utc(2026, 11, 5, 11),
    );
  });

  test('Unix milliseconds', () {
    expect(
      parseTwitterDateTime('1793876400000'),
      DateTime.fromMillisecondsSinceEpoch(1793876400000, isUtc: true),
    );
  });

  test('Snowflake-derived date for old cached tweet with no timestamp', () {
    final when = DateTime.utc(2024, 3, 15, 17, 25, 30);
    final id = ((when.millisecondsSinceEpoch - 1288834974657) << 22)
        .toString();
    final tweet = Tweet(
      id: id,
      text: 'Example video',
      userHandle: '@example',
      mediaUrls: const ['https://video.example/video.mp4'],
      isVideo: true,
    );
    expect(tweet.createdAt, when);
  });

  test('Invalid IDs are not interpreted as dates', () {
    expect(tweetDateFromSnowflakeId('cursor-bottom-1234'), null);
    expect(parseTwitterDateTime('not a date'), null);
  });
}
