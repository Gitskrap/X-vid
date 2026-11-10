import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Human-readable elapsed / total time for the in-feed seek control.
String formatVideoTime(Duration value) {
  final total = value.inSeconds < 0 ? 0 : value.inSeconds;
  final seconds = (total % 60).toString().padLeft(2, '0');
  final minutes = ((total ~/ 60) % 60).toString().padLeft(2, '0');
  if (total >= 3600) return '${total ~/ 3600}:$minutes:$seconds';
  return '${total ~/ 60}:$seconds';
}

/// Allows both tapping and dragging to seek. The UI previews a time while
/// dragging; a single seek is sent to media_kit when the gesture ends.
class VideoSeekBar extends StatefulWidget {
  const VideoSeekBar({super.key, required this.player});

  final Player player;

  @override
  State<VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<VideoSeekBar> {
  double? _dragPositionMs;

  @override
  void didUpdateWidget(covariant VideoSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) _dragPositionMs = null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.duration,
      initialData: widget.player.state.duration,
      builder: (context, durationSnapshot) {
        final total = durationSnapshot.data ?? Duration.zero;
        if (total.inMilliseconds <= 0) return const SizedBox.shrink();

        return StreamBuilder<Duration>(
          stream: widget.player.stream.position,
          initialData: widget.player.state.position,
          builder: (context, positionSnapshot) {
            final maxMs = total.inMilliseconds.toDouble();
            final liveMs =
                (positionSnapshot.data ?? Duration.zero).inMilliseconds.toDouble();
            final current = (_dragPositionMs ?? liveMs).clamp(0.0, maxMs);
            final at = Duration(milliseconds: current.round());

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xE6191B20),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white30),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              child: Row(
                children: [
                  Text(
                    formatVideoTime(at),
                    style: const TextStyle(
                      fontSize: 12, color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 6,
                        activeTrackColor: const Color(0xFF70F0CE),
                        inactiveTrackColor: Colors.white38,
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 9,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 23,
                        ),
                        showValueIndicator: ShowValueIndicator.always,
                        valueIndicatorColor: const Color(0xFF273034),
                        valueIndicatorTextStyle:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      child: Slider(
                        min: 0,
                        max: maxMs,
                        value: current,
                        label: formatVideoTime(at),
                        semanticFormatterCallback: (value) =>
                            'Position ${formatVideoTime(Duration(milliseconds: value.round()))}'
                            ' sur ${formatVideoTime(total)}',
                        onChanged: (value) {
                          setState(() => _dragPositionMs = value);
                        },
                        onChangeEnd: (value) {
                          final target = value.clamp(0.0, maxMs).round();
                          unawaited(widget.player
                              .seek(Duration(milliseconds: target))
                              .catchError((Object error) {
                            debugPrint('Video seek failed: $error');
                          }));
                          if (mounted) setState(() => _dragPositionMs = null);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    formatVideoTime(total),
                    style: const TextStyle(
                      fontSize: 12, color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
