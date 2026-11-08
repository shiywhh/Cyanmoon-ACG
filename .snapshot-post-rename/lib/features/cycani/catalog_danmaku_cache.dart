import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'catalog_disk_cache.dart';

class CatalogDanmakuCache {
  CatalogDanmakuCache(this.identity);
  final String identity;
  Future<List<DanmakuEntry>> readThrough(
    String channel,
    Future<List<DanmakuEntry>> Function() fetch, {
    bool refresh = false,
  }) async {
    final key = 'danmaku.channel.v1:$identity:$channel';
    final rows = await CatalogDiskCache.read(key);
    List<DanmakuEntry>? cached;
    DateTime? stamp;
    if (rows != null && rows.isNotEmpty) {
      try {
        stamp = DateTime.tryParse('${rows.first['saved_at']}');
        cached = (rows.first['entries'] as List)
            .map(
              (r) => DanmakuEntry.fromJson(Map<String, dynamic>.from(r as Map)),
            )
            .toList();
      } catch (_) {
        cached = null;
      }
    }
    if (!refresh &&
        cached != null &&
        stamp != null &&
        DateTime.now().difference(stamp) < const Duration(minutes: 5))
      return cached;
    try {
      final entries = await fetch();
      await CatalogDiskCache.write(key, [
        {
          'saved_at': DateTime.now().toIso8601String(),
          'entries': entries.map((e) => e.toJson()).toList(),
        },
      ]);
      return entries;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }
}
