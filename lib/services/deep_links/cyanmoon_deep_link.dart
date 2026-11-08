sealed class CyanmoonDeepLink {
  const CyanmoonDeepLink();

  static CyanmoonDeepLink? parse(Uri uri) {
    // cyanmoon 为新方案名，kazumi 兼容历史外部链接/快捷方式。
    if (uri.scheme != 'cyanmoon' && uri.scheme != 'kazumi') return null;
    try {
      if (uri.host == 'bangumi' && uri.pathSegments.length == 1) {
        final raw = uri.pathSegments.single;
        final id = int.tryParse(raw);
        // Plain digits only: no sign, whitespace or leading zeros.
        if (id != null && id > 0 && '$id' == raw) return BangumiDeepLink(id);
      }
      if (uri.host == 'search') {
        final query = uri.queryParameters['query']?.trim() ?? '';
        if (query.isNotEmpty) return SearchDeepLink(query);
      }
    } on FormatException {
      // Malformed percent-encoding.
    }
    return null;
  }
}

final class BangumiDeepLink extends CyanmoonDeepLink {
  const BangumiDeepLink(this.id);
  final int id;
}

final class SearchDeepLink extends CyanmoonDeepLink {
  const SearchDeepLink(this.query);
  final String query;
}
