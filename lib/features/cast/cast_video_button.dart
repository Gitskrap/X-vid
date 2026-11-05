import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

import '../../core/models/tweet.dart';

/// A successful Cast session plays only an MP4 URL on Google's Default Media
/// Receiver. No phone screen, comments, post body or account credentials are
/// sent to the TV. The receiving device downloads the URL on its own.
final activeCastTweetProvider =
    NotifierProvider<ActiveCastTweetNotifier, String?>(
  ActiveCastTweetNotifier.new,
);

class ActiveCastTweetNotifier extends Notifier<String?> {
  StreamSubscription<GoogleCastSession?>? _sessionSubscription;

  @override
  String? build() {
    ref.onDispose(() => _sessionSubscription?.cancel());
    return null;
  }

  void watchSession() {
    _sessionSubscription ??= GoogleCastSessionManager
        .instance.currentSessionStream.listen((session) {
      if (session == null) state = null;
    });
  }

  Future<void> play(Tweet tweet, GoogleCastDevice device) async {
    if (!tweet.isVideo || tweet.mediaUrls.isEmpty) {
      throw StateError('Aucun fichier vidéo disponible.');
    }
    final videoUrl = Uri.tryParse(tweet.mediaUrls.first);
    if (videoUrl == null || videoUrl.scheme != 'https') {
      throw StateError('URL de vidéo incompatible avec Google Cast.');
    }
    watchSession();

    // The TV makes a separate HTTPS request to X's CDN. No auth cookies.
    await GoogleCastSessionManager.instance.startSessionWithDevice(device);
    await GoogleCastRemoteMediaClient.instance.loadMedia(
      GoogleCastMediaInformationIOS(
        contentId: videoUrl.toString(),
        streamType: CastMediaStreamType.BUFFERED,
        contentUrl: videoUrl,
        contentType: 'video/mp4',
        metadata: GoogleCastMovieMediaMetadata(
          title: 'Vidéo',
          studio: 'Twitter vidéo',
          releaseDate: tweet.createdAt ?? DateTime.now(),
        ),
      ),
      autoPlay: true,
      playPosition: Duration.zero,
    );

    state = tweet.id;
  }

  Future<void> stop() async {
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    } finally {
      state = null;
    }
  }
}

/// Google Cast is Android-only for this fork.
class CastVideoButton extends ConsumerWidget {
  const CastVideoButton({super.key, required this.tweet});

  final Tweet tweet;

  static Future<void>? _initializing;

  static Future<void> _ensureInitialized() async {
    _initializing ??= GoogleCastContext.instance.setSharedInstanceWithOptions(
      GoogleCastOptionsAndroid(
        appId: GoogleCastDiscoveryCriteria.kDefaultApplicationId,
        stopCastingOnAppTerminated: true,
      ),
    );
    try {
      await _initializing;
      GoogleCastDiscoveryManager.instance.startDiscovery();
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  Future<void> _openCastPicker(BuildContext context, WidgetRef ref) async {
    if (!tweet.isVideo || tweet.mediaUrls.isEmpty) return;
    try {
      await _ensureInitialized();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Cast indisponible sur cet appareil.')),
      );
      return;
    }
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF171A1F),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Caster la vidéo',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Seule la vidéo sera envoyée au téléviseur, sans les textes ni les commentaires.',
                style: TextStyle(fontSize: 13, color: Color(0xFFD0D8DD)),
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<GoogleCastDevice>>(
                stream: GoogleCastDiscoveryManager.instance.devicesStream,
                builder: (context, snapshot) {
                  final devices = snapshot.data ?? const <GoogleCastDevice>[];
                  if (devices.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Aucun Chromecast détecté. Vérifie que le téléphone et le téléviseur sont sur le même Wi-Fi.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFFD0D8DD)),
                        ),
                      ),
                    );
                  }
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final device in devices)
                          ListTile(
                            leading: const Icon(Icons.cast_connected_rounded),
                            title: Text(device.friendlyName),
                            subtitle: const Text('Google Cast'),
                            onTap: () async {
                              Navigator.pop(sheetContext);
                              try {
                                await ref.read(activeCastTweetProvider.notifier)
                                    .play(tweet, device);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Lecture envoyée au téléviseur.',
                                      ),
                                    ),
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'La vidéo n’a pas pu être diffusée. '
                                        'Certaines URL de X ne sont pas lisibles sur Chromecast.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                      ],
                    ),
                  );
                },
              ),
              Consumer(
                builder: (context, innerRef, _) {
                  final active = innerRef.watch(activeCastTweetProvider);
                  if (active == null) return const SizedBox.shrink();
                  return TextButton.icon(
                    onPressed: () async {
                      await innerRef.read(activeCastTweetProvider.notifier).stop();
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Arrêter la diffusion'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeCastTweetProvider);
    final isCastingThis = activeId == tweet.id;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openCastPicker(context, ref),
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCastingThis ? Icons.cast_connected_rounded : Icons.cast_rounded,
              color: isCastingThis ? const Color(0xFF70F0CE) : Colors.white,
              size: 32,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 4),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Caster',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
