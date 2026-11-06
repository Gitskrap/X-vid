import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

import '../../core/models/tweet.dart';
import 'local_video_proxy.dart';
import 'cast_quality.dart';

/// The remote receiver fetches only MP4 bytes via an ephemeral LAN proxy.
/// It receives no tweet text, cookies, account data or mirrored phone screen.
final activeCastTweetProvider =
    NotifierProvider<ActiveCastTweetNotifier, String?>(
  ActiveCastTweetNotifier.new,
);

class ActiveCastTweetNotifier extends Notifier<String?> {
  StreamSubscription<GoogleCastSession?>? _sessionSubscription;
  LocalVideoCastProxy? _proxy;

  /// Public Google-hosted MP4 for distinguishing connection failures from
  /// failures specific to Twitter's CDN, permissions or codecs.
  static final Uri testVideo = Uri.parse(
    'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
  );

  @override
  String? build() {
    ref.onDispose(() {
      _sessionSubscription?.cancel();
      final proxy = _proxy;
      if (proxy != null) unawaited(proxy.close());
    });
    return null;
  }

  void _watchSession() {
    _sessionSubscription ??=
        GoogleCastSessionManager.instance.currentSessionStream.listen((session) {
      if (session == null ||
          session.connectionState == GoogleCastConnectState.disconnected) {
        // Initial connection transitions may briefly emit disconnected.
        // Don't tear down the proxy before the TV requests its video.
        final hadActivePlayback = state != null;
        state = null;
        if (hadActivePlayback) {
          final proxy = _proxy;
          _proxy = null;
          if (proxy != null) unawaited(proxy.close());
        }
      }
    });
  }

  Future<void> play(
    Tweet tweet,
    GoogleCastDevice device, {
    CastQualityMode quality = CastQualityMode.auto,
  }) async {
    if (!tweet.isVideo || tweet.mediaUrls.isEmpty) {
      throw StateError('Cette publication ne comporte pas de vidéo.');
    }
    final urls = tweet.mediaUrls
        .map(Uri.tryParse)
        .whereType<Uri>()
        .where((url) => url.scheme == 'https' &&
            url.host == 'video.twimg.com' &&
            url.path.toLowerCase().endsWith('.mp4'))
        .toList();

    if (urls.isEmpty) {
      throw StateError('Aucun flux MP4 Twitter utilisable pour cette vidéo.');
    }
    // X returns MP4 files highest bitrate first. Auto attempts the
    // best variant, only trying lower quality if playback fails.
    final candidates = selectCastCandidates(urls, quality);
    Object? lastError;
    for (final candidate in candidates) {
      try {
        await _cast(device, candidate, tweetId: tweet.id);
        return;
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError(
      'Lecture impossible en mode ${quality.label} '
      '(${candidates.length} qualité(s) testée(s)). '
      'Dernière erreur : $lastError',
    );
  }

  Future<void> playTest(GoogleCastDevice device) =>
      _cast(device, testVideo, tweetId: null);

  Future<void> _cast(
    GoogleCastDevice device,
    Uri videoUrl, {
    required String? tweetId,
  }) async {
    _watchSession();
    final sessions = GoogleCastSessionManager.instance;

    // Starting a Cast receiver and establishing a connected media session are
    // separate operations. Previously LOAD was fired immediately after
    // startSessionWithDevice(), and the receiver could still be connecting.
    if (sessions.hasConnectedSession &&
        sessions.currentSession?.device?.deviceID != device.deviceID) {
      await sessions.endSessionAndStopCasting();
    }
    if (!sessions.hasConnectedSession) {
      final accepted = await sessions.startSessionWithDevice(device);
      if (!accepted) {
        throw StateError('Le Chromecast a refusé la connexion.');
      }
      if (!sessions.hasConnectedSession) {
        await sessions.currentSessionStream
            .timeout(
              const Duration(seconds: 25),
              onTimeout: (sink) => sink.addError(
                TimeoutException('La connexion au téléviseur a expiré.'),
              ),
            )
            .firstWhere(
              (session) =>
                  session?.connectionState == GoogleCastConnectState.connected,
            );
      }
    }

    // On the X route the television downloads from this phone, not from the
    // X CDN. HTTP Range and browser-compatible CORS are forwarded locally.
    Uri castUrl = videoUrl;
    if (tweetId != null) {
      final previous = _proxy;
      _proxy = null;
      if (previous != null) await previous.close();
      final proxy = LocalVideoCastProxy();
      _proxy = proxy;
      try {
        castUrl = await proxy.start(videoUrl);
      } catch (_) {
        _proxy = null;
        await proxy.close();
        rethrow;
      }
    } else {
      final previous = _proxy;
      _proxy = null;
      if (previous != null) await previous.close();
    }

    final client = GoogleCastRemoteMediaClient.instance;
    final previousMediaSessionId = client.mediaStatus?.mediaSessionID;
    // Never send user authentication headers to the Chromecast.
    await client.loadMedia(
      GoogleCastMediaInformationIOS(
        contentId: castUrl.toString(),
        contentUrl: castUrl,
        contentType: 'video/mp4',
        streamType: CastMediaStreamType.buffered,
        metadata: GoogleCastMovieMediaMetadata(
          title: tweetId == null ? 'Vidéo de test' : 'Vidéo',
          studio: 'Twitter vidéo',
          releaseDate: DateTime.now(),
        ),
      ),
      autoPlay: true,
      playPosition: Duration.zero,
    );

    // loadMedia only acknowledges sending a request. Do not report success or
    // pause the local player until the receiver confirms real playback.
    await client.mediaStatusStream
        .timeout(
          const Duration(seconds: 25),
          onTimeout: (sink) => sink.addError(
            TimeoutException(
              'Le téléviseur ne confirme pas la lecture. '
              '${_proxy?.diagnostics ?? 'Vérifie le réseau du Chromecast.'}',
            ),
          ),
        )
        .firstWhere((status) {
      if (status == null) return false;
      final info = status.mediaInformation;
      final matches = info?.contentId == castUrl.toString() ||
          info?.contentUrl?.toString() == castUrl.toString();
      final isNew = previousMediaSessionId == null ||
          status.mediaSessionID != previousMediaSessionId;

      if (!matches && !isNew) return false;
      if (status.idleReason == GoogleCastMediaIdleReason.error) {
        throw StateError(
          'Le Chromecast a refusé de lire la vidéo. '
          '${_proxy?.diagnostics ?? 'Source ou codec incompatible.'} '
          'Si aucune requête TV n’est indiquée, vérifie l’accès au '
          'réseau local ; sinon, la vidéo peut être incompatible.',
        );
      }
      return status.playerState == CastMediaPlayerState.playing;
    });

    state = tweetId ?? '__diagnostic__';
  }

  Future<void> stop() async {
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    } finally {
      state = null;
      final proxy = _proxy;
      _proxy = null;
      if (proxy != null) await proxy.close();
    }
  }
}

class CastVideoButton extends ConsumerWidget {
  const CastVideoButton({super.key, required this.tweet});
  final Tweet tweet;

  static Future<void>? _initializing;

  static Future<void> _ensureInitialized() async {
    _initializing ??= GoogleCastContext.instance.setSharedInstanceWithOptions(
      GoogleCastOptionsAndroid(
        appId: GoogleCastDiscoveryCriteria.kDefaultApplicationId,
        stopCastingOnAppTerminated: false,
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
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cast non disponible : $error')),
      );
      return;
    }
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171A1F),
      builder: (sheetContext) {
        var busy = false;
        String? message;
        var isError = false;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> castTo(
              GoogleCastDevice device, {
              required bool diagnostic,
            }) async {
              if (busy) return;
              setSheetState(() {
                busy = true;
                isError = false;
                message = diagnostic
                    ? 'Connexion et lecture de la vidéo de test…'
                    : 'Connexion puis chargement de la vidéo X…';
              });
              try {
                if (diagnostic) {
                  await ref.read(activeCastTweetProvider.notifier).playTest(device);
                } else {
                  final quality =
                      await ref.read(castQualityModeProvider.future);
                  await ref.read(activeCastTweetProvider.notifier).play(
                    tweet,
                    device,
                    quality: quality,
                  );
                }
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  message = diagnostic
                      ? 'Test réussi : le Cast fonctionne. Si la vidéo X échoue, '
                          'le problème vient probablement de son URL ou de son codec.'
                      : 'Lecture confirmée par le téléviseur.';
                  isError = false;
                });
              } catch (error) {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  isError = true;
                  message = diagnostic
                      ? 'Test Cast échoué : $error'
                      : 'Vidéo X non lue : $error\n\n'
                          'Teste le bouton de contrôle sur le même appareil pour '
                          'distinguer la connexion Cast de la lecture du flux X.';
                });
              } finally {
                if (sheetContext.mounted) setSheetState(() => busy = false);
              }
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Caster uniquement la vidéo',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Sans texte, commentaires ni copie de l’écran.',
                      style: TextStyle(color: Color(0xFFD0D8DD)),
                    ),
                    if (busy) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(minHeight: 3),
                    ],
                    if (message != null) ...[
                      const SizedBox(height: 16),
                      SelectableText(
                        message!,
                        style: TextStyle(
                          color: isError
                              ? const Color(0xFFFFB4AB)
                              : const Color(0xFF70F0CE),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Consumer(
                      builder: (context, qualityRef, _) {
                        final qualityAsync =
                            qualityRef.watch(castQualityModeProvider);
                        final selected =
                            qualityAsync.value ?? CastQualityMode.auto;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Qualité du Cast',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<CastQualityMode>(
                              key: ValueKey(selected),
                              initialValue: selected,
                              isExpanded: true,
                              decoration: InputDecoration(
                                prefixIcon:
                                    const Icon(Icons.high_quality_rounded),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                isDense: true,
                              ),
                              items: CastQualityMode.values.map((mode) {
                                return DropdownMenuItem(
                                  value: mode,
                                  child: Text(mode.label),
                                );
                              }).toList(),
                              onChanged: busy || qualityAsync.isLoading
                                  ? null
                                  : (mode) {
                                      if (mode != null) {
                                        unawaited(
                                          qualityRef
                                              .read(castQualityModeProvider.notifier)
                                              .select(mode),
                                        );
                                      }
                                    },
                            ),
                            const SizedBox(height: 6),
                            Text(
                              selected.description,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFB5BEC3),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    StreamBuilder<List<GoogleCastDevice>>(
                      stream: GoogleCastDiscoveryManager.instance.devicesStream,
                      builder: (context, snapshot) {
                        final devices = snapshot.data ?? const <GoogleCastDevice>[];
                        if (devices.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                              'Aucun Chromecast trouvé. Vérifie le même Wi-Fi.',
                              style: TextStyle(color: Color(0xFFD0D8DD)),
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
                                  enabled: !busy,
                                  leading: const Icon(Icons.cast_connected_rounded),
                                  title: Text(device.friendlyName),
                                  subtitle: const Text('Lire la vidéo X'),
                                  onTap: () => castTo(device, diagnostic: false),
                                  trailing: IconButton(
                                    onPressed: busy
                                        ? null
                                        : () => castTo(device, diagnostic: true),
                                    tooltip: 'Tester avec une vidéo MP4 publique',
                                    icon: const Icon(Icons.science_outlined),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const Text(
                      'Le bouton fiole teste le Cast avec une vidéo publique. '
                      'Aucun compte X n’est nécessaire pour ce test.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFB5BEC3)),
                    ),
                    Consumer(
                      builder: (context, innerRef, _) {
                        final active = innerRef.watch(activeCastTweetProvider);
                        if (active == null) return const SizedBox.shrink();
                        return TextButton.icon(
                          onPressed: () async {
                            await innerRef.read(activeCastTweetProvider.notifier).stop();
                            if (sheetContext.mounted) {
                              setSheetState(() {
                                message = 'Diffusion arrêtée.';
                                isError = false;
                              });
                            }
                          },
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Arrêter la diffusion'),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCastingThis = ref.watch(activeCastTweetProvider) == tweet.id;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
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
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
            ),
            const SizedBox(height: 4),
            const Text(
              'Caster',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
