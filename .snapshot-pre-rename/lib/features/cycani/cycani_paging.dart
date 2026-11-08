import 'package:flutter/foundation.dart';
import 'cycani_models.dart';

class CycaniPage {
  const CycaniPage(
    this.items, {
    required this.hasMore,
    this.cursor,
    this.total,
  });
  final List<CycaniJson> items;
  final bool hasMore;
  final String? cursor;
  final int? total;
  factory CycaniPage.fromJson(
    CycaniJson data, {
    required int page,
    int size = 36,
    bool cursorBased = false,
  }) {
    final items = cycaniList(data),
        pager = cycaniMap(data['pager']),
        cursor = cycaniMap(data['cursor']);
    final total = pager['total'] == null ? null : cycaniInt(pager['total']);
    final next = cursor['next_cursor']?.toString();
    final more = cursorBased
        ? cursor['has_more'] == true && next != null && next.isNotEmpty
        : pager['has_more'] is bool
        ? pager['has_more'] == true
        : total != null
        ? page * size < total
        : items.length >= size;
    return CycaniPage(
      items,
      hasMore: more && items.isNotEmpty,
      cursor: next,
      total: total,
    );
  }
}

/// Shared append-only paging, including opaque server history cursors.
class CycaniFeed extends ChangeNotifier {
  CycaniFeed(this.loader, {Object? Function(CycaniJson)? keyOf})
    : keyOf = keyOf ?? ((v) => v['id'] ?? v['video_id']);
  final Future<CycaniPage> Function(int page, String? cursor) loader;
  final Object? Function(CycaniJson) keyOf;
  final List<CycaniJson> items = [];
  final Set<Object> _seen = {};
  int _generation = 0, page = 0;
  String? cursor;
  int? total;
  bool loading = false, hasMore = true, _disposed = false;
  Object? error;
  void clear() {
    if (_disposed) return;
    _generation++;
    items.clear();
    _seen.clear();
    page = 0;
    cursor = null;
    total = null;
    loading = false;
    hasMore = false;
    error = null;
    notifyListeners();
  }

  Future<void> reset() {
    _generation++;
    items.clear();
    _seen.clear();
    page = 0;
    cursor = null;
    total = null;
    loading = false;
    hasMore = true;
    error = null;
    return loadMore();
  }

  void showCached(List<CycaniJson> rows) {
    if (_disposed || page != 0 || items.isNotEmpty || rows.isEmpty) return;
    for (final item in rows) {
      final key = keyOf(item);
      if (key == null || _seen.add(key)) items.add(item);
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await loader(1, null);
      if (_disposed || generation != _generation) return;
      items.clear();
      _seen.clear();
      for (final item in result.items) {
        final key = keyOf(item);
        if (key == null || _seen.add(key)) items.add(item);
      }
      page = 1;
      total = result.total;
      cursor = result.cursor;
      hasMore = result.hasMore && result.items.isNotEmpty;
    } catch (e) {
      if (!_disposed && generation == _generation) error = e;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (_disposed || loading || !hasMore) return;
    final generation = _generation, nextPage = page + 1, oldCursor = cursor;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await loader(nextPage, oldCursor);
      if (_disposed || generation != _generation) return;
      for (final item in result.items) {
        final key = keyOf(item);
        if (key == null || _seen.add(key)) items.add(item);
      }
      page = nextPage;
      total = result.total ?? total;
      cursor = result.cursor;
      hasMore =
          result.hasMore &&
          result.items.isNotEmpty &&
          !(result.cursor != null && result.cursor == oldCursor);
    } catch (e) {
      if (!_disposed && generation == _generation) error = e;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
