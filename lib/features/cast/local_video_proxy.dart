import 'dart:async';
import 'dart:io';
import 'dart:math';

/// LAN-only read-only bridge for a single publicly accessible X MP4.
/// The URL has an unpredictable token; no X cookies or user data go to TV.
class LocalVideoCastProxy {
  HttpServer? _server;
  HttpClient? _client;
  Uri? _source;
  String? _token;
  int requests = 0;
  int successResponses = 0;
  String lastStatus = 'Aucune requête du téléviseur';

  String get diagnostics =>
      'Requêtes TV : $requests ; réponses vidéo : $successResponses ; '
      'dernier état : $lastStatus';

  Future<Uri> start(Uri source) async {
    if (source.scheme != 'https' ||
        (source.host != 'video.twimg.com' &&
            !source.host.endsWith('.video.twimg.com'))) {
      throw StateError('Seules les vidéos HTTPS de X sont autorisées.');
    }
    await close();

    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final wifi = interfaces.where((iface) {
      final name = iface.name.toLowerCase();
      return name.startsWith('wlan') ||
          name.startsWith('wifi') ||
          name.startsWith('eth');
    });
    final candidates = wifi.isNotEmpty ? wifi : interfaces;
    InternetAddress? address;
    for (final network in candidates) {
      for (final candidate in network.addresses) {
        if (_isPrivateIPv4(candidate.address)) {
          address = candidate;
          break;
        }
      }
      if (address != null) break;
    }
    if (address == null) {
      throw StateError('Adresse Wi-Fi introuvable sur le téléphone. '
          'Vérifie le réseau local ou désactive un éventuel VPN.');
    }

    _source = source;
    _token = _newToken();
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 20);
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    } catch (_) {
      await close();
      throw StateError('Impossible de démarrer le relais vidéo local.');
    }
    requests = 0;
    successResponses = 0;
    lastStatus = 'En attente du téléviseur';
    _server!.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object _) => lastStatus = 'Erreur réseau locale',
    );
    return Uri(
      scheme: 'http',
      host: address.address,
      port: _server!.port,
      path: '/cast/$_token/stream.mp4',
    );
  }

  static bool _isPrivateIPv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 || (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31);
  }

  static String _newToken() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Range, Origin, Accept, Content-Type',
    );
    response.headers.set(
      'Access-Control-Expose-Headers',
      'Accept-Ranges, Content-Length, Content-Range, Content-Type',
    );
    response.headers.set('Cache-Control', 'no-store');
    try {
      if (request.uri.path != '/cast/$_token/stream.mp4') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.noContent;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final source = _source;
      final client = _client;
      if (source == null || client == null) {
        response.statusCode = HttpStatus.serviceUnavailable;
        return;
      }

      requests++;
      final upstream = await client.openUrl(request.method, source);
      upstream.followRedirects = true;
      upstream.headers.set(HttpHeaders.acceptHeader, '*/*');
      upstream.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/125.0 Mobile Safari/537.36',
      );
      upstream.headers.set(HttpHeaders.refererHeader, 'https://x.com/');
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        upstream.headers.set(HttpHeaders.rangeHeader, range);
      }
      final upstreamResponse = await upstream.close();
      response.statusCode = upstreamResponse.statusCode;
      for (final header in [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.lastModifiedHeader,
        HttpHeaders.etagHeader,
      ]) {
        final value = upstreamResponse.headers.value(header);
        if (value != null) response.headers.set(header, value);
      }
      final length = upstreamResponse.contentLength;
      if (length >= 0) response.contentLength = length;
      if (upstreamResponse.statusCode >= 200 &&
          upstreamResponse.statusCode < 300) {
        successResponses++;
      }
      lastStatus = 'HTTP ' + upstreamResponse.statusCode.toString() +
          (range == null ? '' : ' (Range)');
      if (request.method == 'HEAD') return;
      await response.addStream(upstreamResponse);
    } catch (_) {
      lastStatus = 'Transfert X → téléphone → TV interrompu';
      try {
        response.statusCode = HttpStatus.badGateway;
        response.headers.set(HttpHeaders.contentTypeHeader, 'text/plain');
        response.write('Relais video indisponible.');
      } catch (_) {
        // The receiver can close a partial video download during seeking.
      }
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    final client = _client;
    _client = null;
    _source = null;
    _token = null;
    if (server != null) await server.close(force: true);
    client?.close(force: true);
  }
}
