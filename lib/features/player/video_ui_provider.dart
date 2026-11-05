import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hides the application's chrome without launching the player fullscreen
/// view or changing orientation. A second tap on the video restores it.
final videoUiHiddenProvider =
    NotifierProvider<VideoUiHiddenNotifier, bool>(VideoUiHiddenNotifier.new);

class VideoUiHiddenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void show() => state = false;
}
