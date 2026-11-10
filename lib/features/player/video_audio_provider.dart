import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every new application process starts muted. The choice is intentionally
/// session-only: previous sound-on usage must never autoplay loudly on launch.
class VideoAudioNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
  void mute() => state = true;
}

final videoMutedProvider =
    NotifierProvider<VideoAudioNotifier, bool>(VideoAudioNotifier.new);
