import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../../core/models/tweet.dart';
import '../../../core/database/repository.dart';
import '../../../core/utils/media_cache_manager.dart';
import '../../../core/utils/app_logger.dart';
import '../../feed/widgets/text_tweet_card.dart';
import '../player_pool_provider.dart';
import '../../settings/settings_provider.dart';
import '../../feed/local_video_reactions_provider.dart';
import '../video_ui_provider.dart';
import 'video_seek_bar.dart';

class TiktokMediaContainer extends ConsumerStatefulWidget {
  final Tweet tweet;
  final bool isVisible;
  final bool autoFullscreen;
  /// Only the home Videos tab enforces the 15-second minimum.
  final bool requireLongVideo;
  final Widget Function(
          BuildContext context, VoidCallback? onFullscreen, bool isFullscreen)?
      overlayBuilder;
  final VoidCallback? onPlaybackError;

  const TiktokMediaContainer({
    super.key,
    required this.tweet,
    required this.isVisible,
    this.autoFullscreen = false,
    this.requireLongVideo = false,
    this.overlayBuilder,
    this.onPlaybackError,
  });

  @override
  ConsumerState<TiktokMediaContainer> createState() =>
      _TiktokMediaContainerState();
}

class _TiktokMediaContainerState extends ConsumerState<TiktokMediaContainer> {
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  int _imageIndex = 0;
  int _retryCount = 0;
  bool _isAutoFullscreenDone = false;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _completedSubscription;
  StreamSubscription<Duration>? _watchPositionSubscription;
  Player? _watchedPlayer;
  Duration? _previousWatchPosition;
  int _watchedMs = 0;
  bool _watchRecorded = false;
  int? _resolvedDurationMs;
  int? _persistedDurationMs;
  Timer? _durationValidationTimer;
  bool _shortSkipped = false;

  void _skipShortOrUnknownVideo() {
    if (!mounted || !widget.isVisible || _shortSkipped) return;
    _shortSkipped = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isVisible) widget.onPlaybackError?.call();
    });
  }

  void _trackActualWatchTime(Player player) {
    if (identical(_watchedPlayer, player)) return;
    _watchPositionSubscription?.cancel();
    _watchedPlayer = player;
    _watchedMs = 0;
    _previousWatchPosition = null;
    _watchRecorded = false;
    _watchPositionSubscription = player.stream.position.listen((position) {
      if (!mounted || !widget.isVisible || !player.state.playing ||
          _watchRecorded) {
        _previousWatchPosition = position;
        return;
      }
      final durationMs = _resolvedDurationMs ??
          widget.tweet.durationMs ?? player.state.duration.inMilliseconds;
      if (durationMs <= 15000) {
        _previousWatchPosition = position;
        return;
      }
      final delta = _previousWatchPosition == null
          ? 0
          : position.inMilliseconds - _previousWatchPosition!.inMilliseconds;
      _previousWatchPosition = position;
      // Count only contiguous actual playback: seeking doesn't fake watching.
      if (delta > 0 && delta <= 2000) _watchedMs += delta;
      if (_watchedMs >= 7000) {
        _watchRecorded = true;
        final watched = widget.tweet.copyWith(durationMs: durationMs);
        unawaited(Repository.recordMeaningfulVideoWatch(
            watched, watchedSeconds: 7));
      }
    });
  }

  @override
  void didUpdateWidget(TiktokMediaContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tweet.id != widget.tweet.id) {
      _errorSubscription?.cancel();
      _completedSubscription?.cancel();
      _watchPositionSubscription?.cancel();
      _durationValidationTimer?.cancel();
      _errorSubscription = null;
      _completedSubscription = null;
      _watchPositionSubscription = null;
      _watchedPlayer = null;
      _previousWatchPosition = null;
      _watchedMs = 0;
      _watchRecorded = false;
      _resolvedDurationMs = null;
      _persistedDurationMs = null;
      _shortSkipped = false;
      _retryCount = 0;
    }
    if (!oldWidget.isVisible && widget.isVisible) {
      _isAutoFullscreenDone = false;
      _shortSkipped = false;
      _previousWatchPosition = null;
      _watchedMs = 0;
    } else if (oldWidget.isVisible && !widget.isVisible) {
      _durationValidationTimer?.cancel();
      _durationValidationTimer = null;
      _previousWatchPosition = null;
      _watchedMs = 0;
    }
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _completedSubscription?.cancel();
    _watchPositionSubscription?.cancel();
    _durationValidationTimer?.cancel();
    super.dispose();
  }

  void _handleCompleted() async {
    if (!mounted || !widget.isVisible) return;

    // Exit fullscreen if active when video completes
    final state = _videoKey.currentState;
    if (state != null && state.isFullscreen()) {
      await state.exitFullscreen();
    }

    final settings = ref.read(settingsProvider);
    switch (settings.videoEndAction) {
      case VideoEndAction.pause:
        // Already stopped at the end
        break;
      case VideoEndAction.replay:
        final pool = ref.read(playerPoolProvider);
        final instance = pool[widget.tweet.id];
        instance?.player.seek(Duration.zero);
        instance?.player.play();
        break;
      case VideoEndAction.playNext:
        widget.onPlaybackError
            ?.call(); // Re-use the same callback for auto-advance
        break;
    }
  }

  void _handleError(dynamic error) async {
    final settings = ref.read(settingsProvider);

    // Exit fullscreen on error
    final state = _videoKey.currentState;
    if (state != null && state.isFullscreen()) {
      await state.exitFullscreen();
    }

    if (_retryCount < settings.playbackRetryLimit) {
      _retryCount++;
      AppLogger.log(
          'XFLOW: Video playback error. Retrying ($_retryCount/${settings.playbackRetryLimit})... Error: $error');

      final pool = ref.read(playerPoolProvider);
      final instance = pool[widget.tweet.id];
      if (instance != null) {
        // Re-open media to retry
        instance.player
            .open(Media(widget.tweet.mediaUrls.first), play: widget.isVisible);
      }
    } else {
      AppLogger.log('XFLOW: Video playback failed after retry. Skipping item.');
      widget.onPlaybackError?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tweet.mediaUrls.isEmpty) {
      return Stack(
        children: [
          TextTweetCard(text: widget.tweet.text),
          if (widget.overlayBuilder != null)
            Positioned.fill(child: widget.overlayBuilder!(context, null, false)),
        ],
      );
    }

    if (!widget.tweet.isVideo) {
      return Stack(
        children: [
          _buildImageGallery(),
          if (widget.tweet.mediaUrls.length > 1)
            Positioned(
              bottom: 120, // Above the text overlay
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.tweet.mediaUrls.length, (index) {
                  return Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _imageIndex == index
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                  );
                }),
              ),
            ),
          if (widget.overlayBuilder != null)
            Positioned.fill(child: widget.overlayBuilder!(context, null, false)),
        ],
      );
    }

    final pool = ref.watch(playerPoolProvider);
    final instance = pool[widget.tweet.id];

    if (instance == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Subscribe to events if not already doing so
    _errorSubscription ??= instance.player.stream.error.listen(_handleError);
    _completedSubscription ??=
        instance.player.stream.completed.listen((completed) {
      if (completed) _handleCompleted();
    });

    final settings = ref.watch(settingsProvider);
    final videoUiHidden = ref.watch(videoUiHiddenProvider);
    _trackActualWatchTime(instance.player);
    return StreamBuilder<Duration>(
      stream: instance.player.stream.duration,
      initialData: instance.player.state.duration,
      builder: (context, durationSnapshot) {
        final actualMs = (durationSnapshot.data ?? Duration.zero).inMilliseconds;
        if (actualMs > 0) _resolvedDurationMs = actualMs;
        final durationMs = actualMs > 0 ? actualMs : widget.tweet.durationMs;
        final isValidatedLong = !widget.requireLongVideo ||
            (durationMs != null && durationMs > 15000);

        if (widget.requireLongVideo && !isValidatedLong) {
          if (durationMs != null && durationMs > 0 &&
              durationMs <= 15000) {
            _durationValidationTimer?.cancel();
            _durationValidationTimer = null;
            _skipShortOrUnknownVideo();
          } else if (widget.isVisible && _durationValidationTimer == null) {
            // Unknown durations are not allowed through on faith. Give
            // media_kit time to probe the file, otherwise skip it.
            _durationValidationTimer = Timer(const Duration(seconds: 12), () {
              _durationValidationTimer = null;
              _skipShortOrUnknownVideo();
            });
          }
          if (instance.player.state.playing) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(instance.player.pause());
            });
          }
          return const Center(child: CircularProgressIndicator());
        }

        _durationValidationTimer?.cancel();
        _durationValidationTimer = null;
        if (actualMs > 0 && widget.tweet.durationMs != actualMs &&
            _persistedDurationMs != actualMs) {
          _persistedDurationMs = actualMs;
          unawaited(Repository.saveResolvedVideoDuration(
              widget.tweet.id, actualMs));
        }
        final shouldPlay = widget.isVisible && settings.autoplay;
        if (instance.player.state.playing != shouldPlay) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final nowShouldPlay =
                widget.isVisible && ref.read(settingsProvider).autoplay;
            if (nowShouldPlay && !instance.player.state.playing) {
              unawaited(instance.player.play());
            } else if (!nowShouldPlay && instance.player.state.playing) {
              unawaited(instance.player.pause());
            }
          });
        }
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        final state = _videoKey.currentState;
        if (state != null && state.isFullscreen()) {
          await state.exitFullscreen();
        }
      },
      child: StreamBuilder(
        stream: instance.player.stream.error,
        builder: (context, snapshot) {
          if (snapshot.hasData && _retryCount >= settings.playbackRetryLimit) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.white70, size: 48),
                  const SizedBox(height: 16),
                  const Text('Playback failed. Moving to next...',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Text('Error: ${snapshot.data}',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            );
          }

          // Determine orientation based on current player state
          Future<void> onFullscreen() async {
            final state = _videoKey.currentState;
            if (state != null) {
              try {
                if (state.isFullscreen()) {
                  await state.exitFullscreen();
                } else {
                  // 1. Get latest dimensions
                  final width = instance.player.state.width;
                  final height = instance.player.state.height;
                  
                  // Use aspect ratio for better detection. 
                  // Default to portrait (isLandscape = false) if dimensions are missing or invalid.
                  final double aspectRatio = (width != null && height != null && height != 0) 
                      ? width / height 
                      : 0.0;
                  final isLandscape = aspectRatio > 1.0;

                  AppLogger.log('XFLOW: Fullscreen toggle. ID: ${widget.tweet.id} W: $width H: $height AR: $aspectRatio Landscape: $isLandscape');

                  // 2. Start orientation change immediately
                  if (isLandscape) {
                    await SystemChrome.setPreferredOrientations([
                      DeviceOrientation.landscapeLeft,
                      DeviceOrientation.landscapeRight,
                    ]);
                  } else {
                    await SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                    ]);
                  }

                  // 3. Enter fullscreen
                  await state.enterFullscreen();
                }
              } catch (e) {
                AppLogger.log('XFLOW: Error toggling fullscreen: $e');
              }
            }
          }

          // Handle auto-fullscreen if requested
          if (widget.isVisible && widget.autoFullscreen && !_isAutoFullscreenDone) {
            _isAutoFullscreenDone = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                final state = _videoKey.currentState;
                if (state != null && !state.isFullscreen()) {
                  onFullscreen();
                }
              }
            });
          }

          return Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: RepaintBoundary(
                    child: MaterialVideoControlsTheme(
                      normal: const MaterialVideoControlsThemeData(
                        displaySeekBar: false,
                        automaticallyImplySkipNextButton: false,
                        automaticallyImplySkipPreviousButton: false,
                      ),
                      fullscreen: MaterialVideoControlsThemeData(
                        displaySeekBar: false, // Custom layout below
                        automaticallyImplySkipNextButton: false,
                        automaticallyImplySkipPreviousButton: false,
                        buttonBarHeight: widget.tweet.createdAt == null
                            ? 100.0
                            : 100.0 +
                                MediaQuery.textScalerOf(context).scale(12) +
                                8,
                        bottomButtonBarMargin: EdgeInsets.zero,
                        primaryButtonBar: [
                          const Spacer(),
                          const MaterialPlayOrPauseButton(iconSize: 64),
                          const Spacer(),
                        ],
                        bottomButtonBar: [
                          Expanded(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.5),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (widget.tweet.createdAt != null)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Posted ${DateFormat.yMMMd().add_Hm().format(widget.tweet.createdAt!.toLocal())}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  const MaterialSeekBar(),
                                  Row(
                                    children: [
                                      const MaterialPositionIndicator(),
                                      const Spacer(),
                                      // Private like: never sends X API calls.
                                      MaterialCustomButton(
                                        onPressed: () => unawaited(
                                          ref.read(localVideoReactionsProvider.notifier)
                                              .toggle(widget.tweet, 1)),
                                        icon: Consumer(
                                          builder: (context, ref, child) {
                                            final value = ref.watch(
                                              localVideoReactionsProvider)
                                                .value?[widget.tweet.id]?.value ?? 0;
                                            return Icon(
                                              value == 1
                                                  ? Icons.favorite
                                                  : Icons.favorite_border,
                                              color: value == 1
                                                  ? const Color(0xFFFF637E)
                                                  : Colors.white,
                                            );
                                          },
                                        ),
                                      ),
                                      // Private dislike, available in fullscreen.
                                      MaterialCustomButton(
                                        onPressed: () => unawaited(
                                          ref.read(localVideoReactionsProvider.notifier)
                                              .toggle(widget.tweet, -1)),
                                        icon: Consumer(
                                          builder: (context, ref, child) {
                                            final value = ref.watch(
                                              localVideoReactionsProvider)
                                                .value?[widget.tweet.id]?.value ?? 0;
                                            return Icon(
                                              value == -1
                                                  ? Icons.thumb_down
                                                  : Icons.thumb_down_outlined,
                                              color: value == -1
                                                  ? const Color(0xFFFFB47E)
                                                  : Colors.white,
                                            );
                                          },
                                        ),
                                      ),
                                      // Exit Fullscreen Button
                                      MaterialCustomButton(
                                        onPressed: onFullscreen,
                                        icon: const Icon(Icons.fullscreen_exit),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      child: Video(
                        key: _videoKey,
                        controller: instance.controller,
                        fit: BoxFit.contain,
                        controls: (state) {
                          if (state.isFullscreen()) {
                            return MaterialVideoControls(state);
                          }
                          return Stack(
                            children: [
                              // Tapping the video hides only the UI chrome.
                              // No fullscreen player route or rotation is triggered.
                              Positioned.fill(
                                child: Semantics(
                                  button: true,
                                  label: videoUiHidden
                                      ? 'Réafficher les informations'
                                      : 'Masquer les informations',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      ref.read(videoUiHiddenProvider.notifier)
                                          .toggle();
                                    },
                                  ),
                                ),
                              ),
                              if (!videoUiHidden && widget.overlayBuilder != null)
                                Positioned.fill(
                                  child: widget.overlayBuilder!(
                                    context,
                                    onFullscreen,
                                    false,
                                  ),
                                ),
                            ],
                          );
                        },
                        onExitFullscreen: () async {
                           await SystemChrome.setPreferredOrientations([
                             DeviceOrientation.portraitUp,
                             DeviceOrientation.landscapeLeft,
                             DeviceOrientation.landscapeRight,
                           ]);
                         },
                      ),
                    ),
                  ),
                ),
              ),
              // A visible, interactive timeline sits above Android's
              // gesture-navigation inset and takes horizontal drag gestures.
              if (!videoUiHidden && widget.isVisible)
                Positioned(
                  bottom: MediaQuery.paddingOf(context).bottom + 6,
                  left: 9,
                  right: 9,
                  child: VideoSeekBar(player: instance.player),
                ),
            ],
          );
        },
      ),
    );
      },
    );
  }

  Widget _buildImageGallery() {
    if (widget.tweet.mediaUrls.length == 1) {
      return SizedBox.expand(
        child: Center(
          child: CachedNetworkImage(
            cacheManager: CustomMediaCacheManager.getInstance(),
            imageUrl: widget.tweet.mediaUrls.first,
            fit: BoxFit.contain,
            placeholder: (context, url) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          ),
        ),
      );
    }

    return PageView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: widget.tweet.mediaUrls.length,
      onPageChanged: (index) {
        setState(() {
          _imageIndex = index;
        });
      },
      itemBuilder: (context, index) {
        return SizedBox.expand(
          child: Center(
            child: CachedNetworkImage(
              cacheManager: CustomMediaCacheManager.getInstance(),
              imageUrl: widget.tweet.mediaUrls[index],
              fit: BoxFit.contain,
              placeholder: (context, url) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            ),
          ),
        );
      },
    );
  }
}
