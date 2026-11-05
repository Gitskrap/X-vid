/// Converts X's integer or numeric-string engagement counts. A missing or
/// malformed value is *unknown*, not zero.
int? readXCount(Object? raw) {
  if (raw is int) return raw >= 0 ? raw : null;
  if (raw is num && raw.isFinite && raw >= 0 && raw == raw.truncateToDouble()) {
    return raw.toInt();
  }
  if (raw is String) {
    final parsed = int.tryParse(raw.trim());
    return parsed != null && parsed >= 0 ? parsed : null;
  }
  return null;
}
