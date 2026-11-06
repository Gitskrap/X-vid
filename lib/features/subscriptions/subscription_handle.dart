/// A local follow is a stored X username, not an X follow operation.
String? normalizeSubscriptionHandle(String raw) {
  var handle = raw.trim();
  if (handle.isEmpty) return null;
  if (handle.contains('://') ||
      handle.toLowerCase().startsWith('x.com/') ||
      handle.toLowerCase().startsWith('twitter.com/') ||
      handle.toLowerCase().startsWith('www.x.com/') ||
      handle.toLowerCase().startsWith('www.twitter.com/')) {
    final uri = Uri.tryParse(
      handle.contains('://') ? handle : 'https://' + handle,
    );
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        !{
          'x.com',
          'www.x.com',
          'twitter.com',
          'www.twitter.com',
          'mobile.twitter.com',
        }.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      return null;
    }
    final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.length != 1) return null;
    handle = parts.first;
  }
  if (handle.startsWith('@')) handle = handle.substring(1);
  return RegExp(r'^[A-Za-z0-9_]{1,15}$').hasMatch(handle) ? handle : null;
}
