import 'cycani_api.dart';
import 'catalog_identity.dart';
import 'catalog_models.dart';
import 'site_accounts.dart';

/// One merged favorites/history list across every signed-in site. Rows are
/// normalized so a single UI can render and route writes per row's site.
class CatalogLibraryEntry {
  const CatalogLibraryEntry({
    required this.source,
    required this.rawId,
    required this.title,
    required this.cover,
    required this.raw,
    this.subtitle,
    this.followStatus,
  });
  final CatalogSource source;
  final int rawId;
  final String title;
  final String cover;
  final CatalogJson raw;
  final String? subtitle;

  /// Normalized follow state: 1 watching, 2 want, 3 watched; null for history.
  final int? followStatus;

  String get identity => '${source.name}:$rawId';

  CatalogJson toRow() => {
    'video_id': rawId,
    'title': title,
    'cover_url': cover,
    'catalog_source': source.name,
    if (subtitle != null) 'subtitle': subtitle,
  };
}

int? _normalizeFollow(CatalogSource source, CatalogJson row) {
  final value = row['status'] ?? row['follow_status'] ?? row['category'];
  if (value == null) return null;
  final byName = const {
    'watching': 1,
    'want': 2,
    'watched': 3,
  }[value.toString()];
  if (byName != null) return byName;
  final status = catalogInt(value, -1);
  if (status < 0) return null;
  return switch (source) {
    CatalogSource.xifan => switch (status) {
      1 => 1,
      0 => 2,
      _ => 3,
    },
    _ => status.clamp(1, 3),
  };
}

/// Full per-site fetch (capped) so one merged page needs no cross-site cursor.
class CatalogLibrarySource {
  CatalogLibrarySource({this.capPerSite = 300});
  final int capPerSite;

  CatalogLibraryEntry? _entry(
    CatalogSource source,
    CatalogJson row, {
    required bool history,
  }) {
    final rawVideo = row['video'] is Map ? catalogMap(row['video']) : null;
    final animes = catalogMap(row['animes']);
    final id = catalogInt(
      rawVideo?['video_id'] ?? rawVideo?['id'] ??
          row['video_id'] ?? row['anime_id'] ?? row['vod_id'],
    );
    if (id <= 0) return null;
    final cover =
        '${rawVideo?['cover_url'] ?? row['cover_url'] ?? animes['cover_url'] ?? row['vod_pic'] ?? ''}';
    final title =
        '${rawVideo?['title'] ?? row['anime_title'] ?? animes['title'] ?? row['vod_name'] ?? row['title'] ?? ''}';
    String? subtitle;
    if (history) {
      final progress = catalogInt(row['progress']);
      if (progress > 0) {
        subtitle = '${row['section_title'] ?? ''} · ${progress ~/ 60000} 分钟'
            .trim();
      } else if (row['episode_number'] != null) {
        subtitle =
            '第${'${row['episode_number']}'.replaceFirst(RegExp(r'\.0+$'), '')}集';
      } else if (row['time'] != null) {
        subtitle = '${row['time']}';
      }
    }
    return CatalogLibraryEntry(
      source: source,
      rawId: id,
      title: title,
      cover: cover,
      raw: row,
      subtitle: subtitle,
      followStatus: history ? null : _normalizeFollow(source, row),
    );
  }

  Future<List<CatalogLibraryEntry>> _siteRows(
    CatalogSource source,
    CycaniApi api,
    SourceAccounts accounts, {
    required bool history,
    required int? want,
    required int cap,
  }) async {
    try {
      final rows = <CatalogJson>[];
      switch (source) {
        case CatalogSource.cycani:
          if (!api.loggedIn) {
            return const [];
          }
          if (history) {
            String? cursor;
            while (rows.length < cap) {
              final data = await api.histories(cursor: cursor);
              final batch = catalogList(data);
              rows.addAll(batch);
              final paging = catalogMap(data['cursor']);
              if (paging['has_more'] != true) break;
              final next = paging['next_cursor']?.toString();
              if (next == null || next.isEmpty) break;
              cursor = next;
            }
          } else {
            for (var page = 1; rows.length < cap; page++) {
              final data = await api.favorites(category: '', page: page);
              final batch = catalogList(data);
              rows.addAll(batch);
              final pager = catalogMap(data['pager']);
              if (batch.isEmpty || pager['has_more'] == false) break;
              final total = pager['total'];
              if (total != null && page * 36 >= catalogInt(total)) break;
            }
          }
        case CatalogSource.xifan:
          for (var page = 1; rows.length < cap; page++) {
            final batch = history
                ? await accounts.xifanHistory(page: page)
                : await accounts.xifanFollows(page: page);
            rows.addAll(batch);
            if (batch.length < (history ? 30 : 100)) break;
          }
        case CatalogSource.giri:
          if (history) {
            for (var page = 1; rows.length < cap; page++) {
              final batch = await accounts.giriHistory(page: page);
              rows.addAll(batch);
              if (batch.length < 20) break;
            }
          } else {
            // giriFollows 无分页参数、单次返回全量，循环重拉只是重复请求。
            rows.addAll(await accounts.giriFollows());
          }
      }
      return [
        for (final row in rows)
          if (_entry(source, row, history: history) case final entry?)
            if (want == null || entry.followStatus == want) entry,
      ];
    } catch (e) {
      return const [];
    } finally {
    }
  }

  Future<List<CatalogLibraryEntry>> load({
    required bool history,
    String category = '',
    CycaniApi? api,
    SourceAccounts? accounts,
  }) async {
    final want = switch (category) {
      'watching' => 1,
      'want' => 2,
      'watched' => 3,
      _ => null,
    };
    final cycani = api ?? CycaniApi.instance;
    final sites = accounts ?? SourceAccounts.instance;
    final results = await Future.wait([
      for (final source in CatalogSource.values)
        _siteRows(
          source,
          cycani,
          sites,
          history: history,
          want: want,
          cap: capPerSite,
        ),
    ]);
    final merged = <CatalogLibraryEntry>[];
    final seen = <String>{};
    for (final rows in results) {
      for (final entry in rows) {
        if (seen.add(entry.identity)) merged.add(entry);
      }
    }
    return merged;
  }

  /// Routes a follow-state write to the entry's own site.
  static Future<void> writeFollow(
    CatalogLibraryEntry entry,
    int? status,
  ) async {
    switch (entry.source) {
      case CatalogSource.cycani:
        if (status == null) {
          await CycaniApi.instance.removeFavorites([entry.rawId]);
        } else {
          await CycaniApi.instance.moveFavorites([entry.rawId], '$status');
        }
      case CatalogSource.xifan:
        await SourceAccounts.instance.setXifanFollow(entry.rawId, status);
      case CatalogSource.giri:
        await SourceAccounts.instance.setGiriFollow(entry.rawId, status ?? 0);
    }
  }

  /// Routes a history delete to the entry's own site.
  static Future<void> deleteHistory(CatalogLibraryEntry entry) async {
    if (entry.source == CatalogSource.cycani) {
      await CycaniApi.instance.removeHistories([entry.rawId]);
    } else {
      await SourceAccounts.instance.removeHistory(
        entry.source == CatalogSource.giri,
        entry.rawId,
      );
    }
  }
}
