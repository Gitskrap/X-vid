import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/entities.dart';
import '../models/tweet.dart';
import 'twitter_client.dart';

/// Read-only public metadata from FxEmbed. Never sends X cookies or tokens.
/// The service may be unavailable; saved handles remain locally accessible.
class PublicXClient {
  static const _host = 'api.fxtwitter.com';
  final http.Client _http;
  PublicXClient({http.Client? client}) : _http = client ?? http.Client();

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await _http.get(
      uri,
      headers: const {'accept': 'application/json'},
    ).timeout(const Duration(seconds: 16));
    if (response.statusCode != 200) {
      throw StateError(
        'Service public indisponible (HTTP ' +
            response.statusCode.toString() + ').',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Réponse inattendue du service public.');
    }
    final code = decoded['code'];
    if (code is num && code != 200) {
      throw StateError('Service public : ' +
          (decoded['message']?.toString() ?? code.toString()));
    }
    return decoded;
  }

  static Subscription? decodeProfile(Object? value) {
    if (value is! Map || value['protected'] == true) return null;
    final handle = value['screen_name']?.toString();
    if (handle == null ||
        !RegExp(r'^[A-Za-z0-9_]{1,15}$').hasMatch(handle)) {
      return null;
    }
    final id = value['id']?.toString();
    final avatar = value['avatar_url']?.toString();
    return Subscription(
      id: (id?.isNotEmpty ?? false) ? id! : 'public_' + handle.toLowerCase(),
      screenName: handle,
      name: value['name']?.toString() ?? handle,
      profileImageUrl: avatar?.isNotEmpty == true ? avatar : null,
      description: value['description']?.toString(),
      followersCount: value['followers'] is num
          ? (value['followers'] as num).toInt() : null,
      followingCount: value['following'] is num
          ? (value['following'] as num).toInt() : null,
    );
  }

  static List<Subscription> decodeSuggestions(Map<String, dynamic> body) {
    final users = body['users'];
    if (users is! List) {
      throw const FormatException('Liste de comptes publics manquante.');
    }
    final seen = <String>{};
    return [
      for (final raw in users)
        if (decodeProfile(raw) case final profile?)
          if (seen.add(profile.screenName.toLowerCase())) profile,
    ];
  }

  Future<List<Subscription>> searchAccounts(String query) async {
    final text = query.trim();
    if (text.isEmpty) return [];
    if (text.length > 80) {
      throw const FormatException('Recherche trop longue.');
    }
    final body = await _get(
      Uri.https(_host, '/2/typeahead', {
        'q': text,
        'result_type': 'users',
        'src': 'search_box',
      }),
    );
    return decodeSuggestions(body);
  }

  Future<Subscription?> profile(String screenName) async {
    if (!RegExp(r'^[A-Za-z0-9_]{1,15}$').hasMatch(screenName)) return null;
    try {
      final result = await _get(
        Uri.https(_host, '/2/profile/' + screenName),
      );
      return decodeProfile(result['user']);
    } catch (_) {
      return null;
    }
  }

  static List<Tweet> decodeMediaResults(Map<String, dynamic> body) {
    final results = body['results'];
    if (results is! List) {
      throw const FormatException('Liste de vidéos publiques manquante.');
    }
    final seen = <String>{};
    final tweets = <Tweet>[];
    for (final raw in results) {
      if (raw is! Map || raw['type'] != 'status') continue;
      final id = raw['id']?.toString();
      if (id == null || id.isEmpty || !seen.add(id)) continue;
      final media = raw['media'];
      if (media is! Map) continue;
      final videos = media['videos'];
      if (videos is! List) continue;
      final variants = <(int, String)>[];
      String? thumbnail;
      for (final entry in videos) {
        if (entry is! Map) continue;
        thumbnail ??= entry['thumbnail_url']?.toString();
        final formats = entry['formats'];
        if (formats is List) {
          for (final format in formats) {
            if (format is! Map) continue;
            final url = format['url']?.toString() ?? '';
            final uri = Uri.tryParse(url);
            if (uri == null || uri.scheme != 'https' ||
                !uri.path.toLowerCase().endsWith('.mp4')) continue;
            variants.add((
              format['bitrate'] is num
                  ? (format['bitrate'] as num).toInt() : 0,
              url,
            ));
          }
        }
        final url = entry['url']?.toString() ?? '';
        final uri = Uri.tryParse(url);
        if (uri != null && uri.scheme == 'https' &&
            uri.path.toLowerCase().endsWith('.mp4')) {
          variants.add((0, url));
        }
      }
      if (variants.isEmpty) continue;
      variants.sort((a, b) => b.$1.compareTo(a.$1));
      final urls = variants.map((v) => v.$2).toSet().toList();
      final author = raw['author'] is Map ? raw['author'] as Map : const {};
      final name = author['screen_name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final when = raw['created_timestamp'];
      final likes = raw['likes'], replies = raw['replies'];
      tweets.add(Tweet(
        id: id,
        text: raw['text']?.toString() ?? '',
        userHandle: '@' + name,
        userAvatarUrl: author['avatar_url']?.toString(),
        mediaUrls: urls,
        thumbnailUrl: thumbnail,
        isVideo: true,
        createdAt: when is num && when > 0
            ? DateTime.fromMillisecondsSinceEpoch(
                (when * 1000).toInt(), isUtc: true).toLocal()
            : null,
        source: 'FxEmbed',
        retrievedVia: 'Public',
        favoriteCount: likes is num ? likes.toInt() : 0,
        replyCount: replies is num ? replies.toInt() : 0,
        favoriteCountKnown: likes is num,
        replyCountKnown: replies is num,
      ));
    }
    return tweets;
  }

  /// Search public posts without sending X cookies or credentials.
  /// Uses the documented FxEmbed /2/search endpoint.
  Future<TweetResponse> searchVideos(
    String query, {
    String? cursor,
    int count = 30,
    bool top = false,
  }) async {
    final text = query.trim();
    if (text.isEmpty) return TweetResponse(tweets: []);
    if (text.length > 180) {
      throw const FormatException('Recherche trop longue.');
    }
    final filtered = text.contains('filter:videos')
        ? text : '$text filter:videos';
    final body = await _get(Uri.https(_host, '/2/search', {
      'q': filtered,
      'feed': top ? 'top' : 'latest',
      'count': count.clamp(1, 100).toString(),
      if (cursor?.isNotEmpty == true) 'cursor': cursor!,
    }));
    final cursorValue = body['cursor'];
    final bottom = cursorValue is Map
        ? cursorValue['bottom']?.toString() : null;
    return TweetResponse(
      tweets: decodeMediaResults(body),
      cursorBottom: bottom?.isEmpty == true ? null : bottom,
    );
  }

  Future<TweetResponse> userVideos(
    String screenName, {String? cursor, int count = 20}
  ) async {
    if (!RegExp(r'^[A-Za-z0-9_]{1,15}$').hasMatch(screenName)) {
      throw const FormatException('Identifiant X invalide.');
    }
    final body = await _get(
      Uri.https(_host, '/2/profile/' + screenName + '/media', {
        'count': count.clamp(1, 30).toString(),
        if (cursor?.isNotEmpty == true) 'cursor': cursor!,
      }),
    );
    final cursorValue = body['cursor'];
    final bottom = cursorValue is Map
        ? cursorValue['bottom']?.toString() : null;
    return TweetResponse(
      tweets: decodeMediaResults(body),
      cursorBottom: bottom?.isEmpty == true ? null : bottom,
    );
  }
}
