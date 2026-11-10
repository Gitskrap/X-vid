import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immersive mode belongs to the feed, not to an individual media_kit player.
/// It therefore survives moving to the next video in the vertical PageView.
class PersistentFullscreenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => setActive(!state);

  void setActive(bool active) {
    if (active == state) return;
    state = active;
    unawaited(SystemChrome.setEnabledSystemUIMode(
      active ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    ));
  }
}

final persistentFullscreenProvider =
    NotifierProvider<PersistentFullscreenNotifier, bool>(
  PersistentFullscreenNotifier.new,
);
