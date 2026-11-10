import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository.dart';

/// Canonical form allows #Nature, nature and #NATURE to mean the same tag.
String normalizeBlockedHashtag(String input) {
  final value = input.trim().replaceFirst(RegExp(r'^#+'), '').toLowerCase();
  if (!RegExp(r'^[\wÀ-ÿ]{2,40}$').hasMatch(value)) {
    throw const FormatException(
        'Hashtag invalide : utilise 2 à 40 lettres, chiffres ou _.');
  }
  return value;
}

final hashtagBlacklistProvider =
    AsyncNotifierProvider<HashtagBlacklistNotifier, List<String>>(
  HashtagBlacklistNotifier.new,
);

class HashtagBlacklistNotifier extends AsyncNotifier<List<String>> {
  @override
  FutureOr<List<String>> build() => Repository.getBlockedHashtags();

  Future<void> add(String raw) async {
    final tag = normalizeBlockedHashtag(raw);
    await Repository.addBlockedHashtag(tag);
    if (!ref.mounted) return;
    final current = state.value ?? const <String>[];
    state = AsyncData([tag, ...current.where((e) => e != tag)]);
  }

  Future<void> remove(String raw) async {
    final tag = normalizeBlockedHashtag(raw);
    await Repository.removeBlockedHashtag(tag);
    if (!ref.mounted) return;
    state = AsyncData((state.value ?? const <String>[])
        .where((e) => e != tag).toList());
  }
}
