import 'cycani_api.dart';
import 'catalog_models.dart';

class CycaniAccountStats {
  const CycaniAccountStats({
    required this.watchedVideos,
    required this.favorites,
  });
  final int watchedVideos, favorites;
}

Future<CycaniAccountStats> loadCycaniAccountStats(CycaniApi api) async {
  final epoch = api.sessionEpoch;
  final videos = <int>{}, seenCursors = <String>{};
  String? cursor;
  while (true) {
    final data = await api.histories(cursor: cursor);
    if (api.sessionEpoch != epoch) throw StateError('账户已切换');
    for (final item in catalogList(data)) {
      final id = catalogInt(item['video_id'] ?? catalogMap(item['video'])['id']);
      if (id > 0) videos.add(id);
    }
    for (final id in data['deleted_video_ids'] as List? ?? []) {
      videos.remove(catalogInt(id));
    }
    final paging = catalogMap(data['cursor']);
    if (paging['has_more'] != true) break;
    final next = paging['next_cursor']?.toString();
    if (next == null || next.isEmpty || !seenCursors.add(next))
      throw StateError('历史游标无效');
    cursor = next;
  }
  final first = await api.favorites();
  if (api.sessionEpoch != epoch) throw StateError('账户已切换');
  final pager = catalogMap(first['pager']);
  int favorites;
  if (pager['total'] != null) {
    favorites = catalogInt(pager['total']);
  } else {
    final ids = <int>{};
    var data = first, page = 1;
    while (true) {
      final items = catalogList(data);
      for (final item in items) {
        final id = catalogInt(
          item['video_id'] ?? catalogMap(item['video'])['id'] ?? item['id'],
        );
        if (id > 0) ids.add(id);
      }
      if (items.length < 36) break;
      data = await api.favorites(page: ++page);
      if (api.sessionEpoch != epoch) throw StateError('账户已切换');
      if (page > 1000) throw StateError('追番分页异常');
    }
    favorites = ids.length;
  }
  return CycaniAccountStats(watchedVideos: videos.length, favorites: favorites);
}
