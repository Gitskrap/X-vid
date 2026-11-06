import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// X's MP4 variants are already sorted by bitrate, highest first.
enum CastQualityMode {
  auto('Auto', 'Meilleure qualité, puis qualité inférieure si la TV refuse'),
  high('Haute qualité', 'Meilleure qualité uniquement, sans réduction'),
  economy('Économie de données', 'Qualité la plus légère disponible');

  const CastQualityMode(this.label, this.description);
  final String label;
  final String description;
}

/// No transcoding: choose an existing MP4 variant, high bitrate first.
List<Uri> selectCastCandidates(Iterable<Uri> highToLow, CastQualityMode mode) {
  final distinct = <String, Uri>{};
  for (final url in highToLow) {
    distinct.putIfAbsent(url.toString(), () => url);
  }
  final candidates = distinct.values.toList();
  if (candidates.isEmpty) return [];
  switch (mode) {
    case CastQualityMode.auto:
      return candidates;
    case CastQualityMode.high:
      return [candidates.first];
    case CastQualityMode.economy:
      return [candidates.last];
  }
}

final castQualityModeProvider =
    AsyncNotifierProvider<CastQualityNotifier, CastQualityMode>(
  CastQualityNotifier.new,
);

class CastQualityNotifier extends AsyncNotifier<CastQualityMode> {
  static const _key = 'twitter_video_cast_quality';

  @override
  Future<CastQualityMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    for (final mode in CastQualityMode.values) {
      if (mode.name == name) return mode;
    }
    return CastQualityMode.auto;
  }

  Future<void> select(CastQualityMode mode) async {
    state = AsyncData(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
