import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/features/player/video_audio_provider.dart';

void main() {
  test('every new app provider container starts muted', () {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    expect(first.read(videoMutedProvider), isTrue);
    first.read(videoMutedProvider.notifier).toggle();
    expect(first.read(videoMutedProvider), isFalse);

    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    expect(restarted.read(videoMutedProvider), isTrue);
    restarted.read(videoMutedProvider.notifier).mute();
    expect(restarted.read(videoMutedProvider), isTrue);
  });
}
