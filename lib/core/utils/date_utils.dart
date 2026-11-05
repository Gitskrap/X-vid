/// Parse the timestamp formats returned by X/Twitter.
DateTime? parseTwitterDateTime(String? dateStr) {
  if (dateStr == null || dateStr.trim().isEmpty) return null;
  final value = dateStr.trim();

  final unix = int.tryParse(value);
  if (unix != null) {
    return _sensibleDate(value.length <= 10 ? unix * 1000 : unix);
  }
  final iso = DateTime.tryParse(value);
  if (iso != null) return iso.toUtc();

  // Standard Twitter format: "Wed Oct 10 20:19:24 +0000 2018".
  final match = RegExp(
    r'^\w{3}\s+([A-Za-z]{3})\s+(\d{1,2})\s+'
    r'(\d{2}):(\d{2}):(\d{2})\s+([+-]\d{4}|UTC|GMT)\s+(\d{4})$',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) return null;
  const months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,
    'may': 5, 'jun': 6, 'jul': 7, 'aug': 8,
    'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  final month = months[match.group(1)!.toLowerCase()];
  if (month == null) return null;

  final day = int.parse(match.group(2)!);
  final hour = int.parse(match.group(3)!);
  final minute = int.parse(match.group(4)!);
  final second = int.parse(match.group(5)!);
  final year = int.parse(match.group(7)!);
  if (day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) {
    return null;
  }
  final timestamp = DateTime.utc(year, month, day, hour, minute, second);
  if (timestamp.year != year || timestamp.month != month ||
      timestamp.day != day) return null;

  final zone = match.group(6)!.toUpperCase();
  if (zone == 'GMT' || zone == 'UTC') return timestamp;
  final offsetH = int.parse(zone.substring(1, 3));
  final offsetM = int.parse(zone.substring(3, 5));
  if (offsetH > 23 || offsetM > 59) return null;
  final offset = (offsetH * 60 + offsetM) *
      (zone.startsWith('-') ? -1 : 1);
  return timestamp.subtract(Duration(minutes: offset));
}

/// Twitter Snowflake IDs embed publication time in their top 42 bits.
/// Returns null for nonnumeric IDs or implausible timestamps.
DateTime? tweetDateFromSnowflakeId(String id) {
  if (!RegExp(r'^\d{16,20}$').hasMatch(id)) return null;
  final n = int.tryParse(id);
  if (n == null || n <= 0) return null;
  const epochMs = 1288834974657;
  return _sensibleDate((n >> 22) + epochMs);
}

DateTime? _sensibleDate(int ms) {
  try {
    final time = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    if (time.isBefore(DateTime.utc(2010, 11, 4)) ||
        time.isAfter(DateTime.now().toUtc().add(const Duration(days: 1)))) {
      return null;
    }
    return time;
  } catch (_) {
    return null;
  }
}
