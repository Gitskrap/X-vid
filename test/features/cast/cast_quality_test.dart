import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/features/cast/cast_quality.dart';

void main() {
  final high = Uri.parse('https://video.twimg.com/1080.mp4');
  final medium = Uri.parse('https://video.twimg.com/720.mp4');
  final low = Uri.parse('https://video.twimg.com/360.mp4');

  test('auto prefers high quality and falls back down in order', () {
    expect(
      selectCastCandidates([high, medium, low], CastQualityMode.auto),
      [high, medium, low],
    );
  });

  test('high quality does not silently downgrade', () {
    expect(
      selectCastCandidates([high, medium, low], CastQualityMode.high),
      [high],
    );
  });

  test('economy chooses only lowest bitrate', () {
    expect(
      selectCastCandidates([high, medium, low], CastQualityMode.economy),
      [low],
    );
  });

  test('duplicates and sparse candidates are handled', () {
    expect(
      selectCastCandidates([high, high, medium], CastQualityMode.auto),
      [high, medium],
    );
    expect(selectCastCandidates([low], CastQualityMode.high), [low]);
    expect(selectCastCandidates([], CastQualityMode.auto), isEmpty);
  });
}
