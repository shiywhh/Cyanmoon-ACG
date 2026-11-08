/// Only public cover/banner URLs are eligible for third-party acceleration.
abstract final class CatalogImageUrl {
  static String giriPublic(String url) {
    final value = url.trim();
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('upload/') || value.startsWith('/upload/')) {
      return Uri.parse(
        'https://jpg.girigirilove.com/',
      ).resolve(value).toString();
    }
    return value;
  }

  static bool eligible(Uri uri, {Map<String, String>? headers}) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment)
      return false;
    if (headers != null &&
        headers.keys.any(
          (key) => const {
            'authorization',
            'cookie',
            'apikey',
            'x-csrf-token',
          }.contains(key.toLowerCase()),
        ))
      return false;
    final path = uri.path.toLowerCase();
    if (path.contains('avatar') ||
        path.contains('user') ||
        path.contains('captcha'))
      return false;
    final host = uri.host;
    return RegExp(r'^img[0-9]+\.xfmanga\.top$').hasMatch(host) ||
        host == 'jpg.girigirilove.com' ||
        (host == 'm3u8.girigirilove.com' && path.startsWith('/upload/')) ||
        host == 'lain.bgm.tv';
  }

  static Uri? proxy(Uri uri, {Map<String, String>? headers}) {
    final list = proxies(uri, headers: headers);
    return list.isEmpty ? null : list.first;
  }

  /// Baidu gimg cache nodes; gimg2 is an independent node used as fallback
  /// when gimg1 misses, rate-limits or jitters.
  static List<Uri> proxies(Uri uri, {Map<String, String>? headers}) {
    if (!eligible(uri, headers: headers)) return const [];
    final src = '${uri.host}${uri.path}';
    return [
      Uri.parse('https://gimg1.baidu.com/gimg/app=2001&src=$src'),
      Uri.parse('https://gimg2.baidu.com/gimg/app=2001&src=$src'),
    ];
  }

  static String thumbnail(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !eligible(uri) ||
        !RegExp(r'^img[0-9]+\.xfmanga\.top$').hasMatch(uri.host))
      return url;
    return uri
        .replace(path: uri.path.replaceFirst('/r/1200/', '/r/600/'))
        .toString();
  }
}
