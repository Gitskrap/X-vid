import 'package:flutter/material.dart';

/// The selected X session is the account used for authenticated X actions,
/// including likes. It is not necessarily the account that fetched a video.
String activeSessionLabel(String? screenName) {
  final normalized = screenName?.trim().replaceFirst(RegExp(r'^@'), '');
  if (normalized == null || normalized.isEmpty) return 'Sans compte X';
  return '@$normalized';
}

/// Small header chip: replaces the Twitter vidéo wordmark on the feed.
/// Kept separate from the video's provenance indicator (Cache/Public).
class ActiveSessionChip extends StatelessWidget {
  const ActiveSessionChip({super.key, required this.screenName});

  final String? screenName;

  @override
  Widget build(BuildContext context) {
    final label = activeSessionLabel(screenName);
    return Tooltip(
      message: screenName == null || screenName!.trim().isEmpty
          ? 'Connecte un compte X pour aimer les vidéos sur X.'
          : 'Session X actuellement sélectionnée pour les likes et les '
              'requêtes authentifiées.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xEB142621),
          border: Border.all(color: const Color(0xFF70F0CE)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_circle_rounded,
                size: 20, color: Color(0xFF70F0CE)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
