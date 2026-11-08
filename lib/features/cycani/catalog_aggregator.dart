import 'catalog_lru.dart';
import 'catalog_http.dart';
import 'catalog_identity.dart';
export 'catalog_identity.dart';
import 'catalog_disk_cache.dart';
import 'catalog_read_retry.dart';
import 'dart:async';
import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:dio/dio.dart';
import 'cycani_api.dart';
import 'catalog_models.dart';
import 'catalog_paging.dart';
import 'cycani_remote_danmaku.dart';

CatalogSource catalogSource(CatalogJson row) =>
    CatalogSource.values
        .where((s) => s.name == row['catalog_source'])
        .firstOrNull ??
    CatalogSource.cycani;
String catalogRowKey(CatalogJson row) =>
    '${catalogSource(row).name}:${CatalogVideo(row).id}';

/// Only IDs already belonging to the detail page's matched group are carried
/// into playback. Ambiguous IDs from the same site are not silently selected.
Map<String, int> catalogDanmakuIds(
  Iterable<CatalogJson> members, {
  CatalogJson? selected,
}) {
  final result = <String, int>{};
  for (final source in CatalogSource.values) {
    final ids = members
        .where((r) => catalogSource(r) == source)
        .map((r) => CatalogVideo(r).id)
        .where((id) => id > 0 && id < 1000000000)
        .toSet();
    if (ids.length == 1) result[source.name] = ids.single;
  }
  if (selected != null && CatalogVideo(selected).id > 0) {
    result[catalogSource(selected).name] = CatalogVideo(selected).id;
  }
  return Map.unmodifiable(result);
}

/// Canonical IDs take precedence. Alias matching only joins an unambiguous
/// connected component with one row per provider and matching known year.
List<CatalogJson> mergeCatalogRows(List<CatalogJson> input) {
  String normalize(Object? value) => (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s!！?？。．·・:：]+'), '');
  String? format(CatalogJson row) {
    final raw = normalize(row['version']);
    if (const {'tv', '电视', '电视动画', 'tv动画'}.contains(raw)) return 'tv';
    if (const {'movie', 'film', '剧场', '剧场版', '电影'}.contains(raw))
      return 'movie';
    return const {'ova', 'ona', 'web'}.contains(raw) ? raw : null;
  }

  Iterable<String> names(CatalogJson row) sync* {
    yield CatalogVideo(row).title;
    for (final key in ['title_original', 'subtitle', 'aliases']) {
      final value = row[key];
      if (value is List) {
        yield* value.whereType<String>();
      } else if (value is String) {
        yield* value.split(RegExp(r'[,，、/|]'));
      }
    }
  }

  final rows = <String, CatalogJson>{
    for (final row in input) catalogRowKey(row): row,
  }.values.toList();
  final canonical = <int, List<int>>{}, aliases = <String, List<int>>{};
  final graph = List.generate(rows.length, (_) => <int>{});
  for (final (i, row) in rows.indexed) {
    final id = catalogInt(row['bangumi_id']);
    final year = catalogInt(row['year']);
    if (id > 0) (canonical[id] ??= []).add(i);
    if (year > 1900) {
      for (final name in names(
        row,
      ).map(normalize).where((n) => n.isNotEmpty).toSet()) {
        (aliases['$year:$name'] ??= []).add(i);
      }
    }
  }

  for (final list in [...canonical.values, ...aliases.values]) {
    if (list.length < 2) continue;
    final first = list.first;
    for (final index in list.skip(1)) {
      graph[first].add(index);
      graph[index].add(first);
    }
  }

  final seen = <int>{}, output = <List<int>>[];
  for (var i = 0; i < rows.length; i++) {
    if (!seen.add(i)) continue;
    final component = [i];
    for (var j = 0; j < component.length; j++) {
      component.addAll(graph[component[j]].where(seen.add));
    }
    component.sort();
    final group = component.map((j) => rows[j]).toList();
    final ids = group
        .map((r) => catalogInt(r['bangumi_id']))
        .where((id) => id > 0)
        .toSet();
    final years = group
        .map((r) => catalogInt(r['year']))
        .where((v) => v > 1900)
        .toSet();
    final formats = group.map(format).whereType<String>().toSet();
    final seasons = group
        .map((r) => catalogInt(r['season_number']))
        .where((v) => v > 0)
        .toSet();
    if (ids.length <= 1 &&
        years.length <= 1 &&
        formats.length <= 1 &&
        seasons.length <= 1 &&
        group.map(catalogSource).toSet().length == group.length) {
      output.add(component);
    } else {
      final trusted = <int, List<int>>{};
      for (final j in component) {
        final id = catalogInt(rows[j]['bangumi_id']);
        if (id > 0) {
          (trusted[id] ??= []).add(j);
        } else {
          output.add([j]);
        }
      }
      output.addAll(trusted.values);
    }
  }
  output.sort((a, b) => a.first.compareTo(b.first));
  return [
    for (final group in output)
      {
        ...rows[group.first],
        'catalog_members': [for (final i in group) rows[i]],
      },
  ];
}

class CatalogAggregator {
  CatalogAggregator({CycaniApi? cycani, Dio? xifan, Dio? giri})
    : _cycani = cycani ?? CycaniApi.instance,
      _xifan =
          xifan ??
          _client('https://api.xifanacg.com', {
            'apikey': CycaniRemoteDanmaku.publicClientKey,
          }),
      _giri =
          giri ??
          _client('https://m3u8.girigirilove.com/api.php', {
            'Origin': 'https://ani.girigirilove.com',
            'Referer': 'https://ani.girigirilove.com/home',
          });
  static final instance = CatalogAggregator();
  final CycaniApi _cycani;
  final Dio _xifan, _giri;
  late final Dio _xifanWeb = _client('https://next.xifanacg.com', {});
  static Dio _client(String origin, Map<String, String> headers) =>
      CatalogHttp.client(origin, headers);

  CatalogJson _row(CatalogSource source, CatalogJson row) => switch (source) {
    CatalogSource.cycani => {...row, 'catalog_source': source.name},
    CatalogSource.xifan => {
      'video_id': row['id'],
      'title': row['title'],
      'cover_url': row['cover_url'],
      'year': row['release_year'],
      'title_original': row['title_original'],
      'aliases': row['aliases'],
      'season_number': row['season_number'],
      'bangumi_id': row['bangumi_id'],
      'description': row['description'],
      'score': row['bangumi_score'],
      'area': row['region'],
      'version': row['format'] == 'tv'
          ? 'TV'
          : row['format'] == 'movie'
          ? '剧场版'
          : row['format'],
      'catalog_source': source.name,
    },
    CatalogSource.giri => {
      'video_id': row['vod_id'],
      'title': row['vod_name'],
      'subtitle': row['vod_sub'],
      'cover_url': row['vod_pic'],
      'year': row['vod_year'],
      'description': row['vod_blurb'],
      'score': row['vod_score'],
      'area': row['vod_area'],
      // 周表行是 vod_time（更新至X集 / 时间），分类行是 vod_remarks（同义）。
      'air': row['vod_time'] ?? row['vod_remarks'],
      'catalog_source': source.name,
    },
  };
  List<CatalogJson> _rows(CatalogSource source, Object? data) => [
    for (final item in catalogList(data))
      if (CatalogVideo(_row(source, item)).id > 0) _row(source, item),
  ];
  dynamic _giriInfo(dynamic data) {
    final row = catalogMap(data);
    if (catalogInt(row['code']) != 1) throw StateError('GiriGiri 请求失败');
    return row['info'];
  }

  Future<List<CatalogJson>> _cycaniBanners() async {
    try {
      final payload = await _cycani.request(
        '/app/adverts',
        query: {'position': 'banner'},
      );
      return [
        for (final b in catalogList(payload))
          if (b['action_type'] == 'video' &&
              catalogInt(b['action_value']) > 0 &&
              Uri.tryParse('${b['content']}')?.scheme == 'https')
            {
              'catalog_source': CatalogSource.cycani.name,
              'video_id': catalogInt(b['action_value']),
              'title': b['name'],
              'cover_url': b['content'],
            },
      ];
    } catch (_) {
      return [];
    }
  }

  static List<CatalogJson> xifanHomeSections(String document) {
    final page = html.parse(document);
    final groups = <CatalogJson>[];
    final names = {'追番周表', '热门の新番', '刚上架の旧番', '高分合集'};
    List<CatalogJson>? current;
    final seen = <int>{};
    for (final node in page.querySelectorAll(
      'body h1, body h2, body h3, body a[href]',
    )) {
      if (node.localName != 'a') {
        final heading = node.text.trim();
        final hero =
            node.classes.contains('line-clamp-3') &&
            node.classes.contains('motion-text-rise');
        if (hero || names.contains(heading)) {
          current = <CatalogJson>[];
          groups.add({
            'name': hero ? '焦点推荐' : heading,
            if (hero) 'layout': 'hero',
            'videos': current,
          });
          seen.clear();
        }
        continue;
      }
      if (current == null) continue;
      final match = RegExp(
        r'^/(anime|series)/(\d+)$',
      ).firstMatch(node.attributes['href'] ?? '');
      if (match == null) continue;
      final series = groups.last['name'] == '高分合集';
      if (series != (match[1] == 'series')) continue;
      final id = int.parse(match[2]!);
      if (!seen.add(id)) continue;
      final image = node.querySelector('img');
      final title =
          (image?.attributes['alt'] ??
                  node.attributes['aria-label'] ??
                  node.text)
              .trim();
      current.add({
        'video_id': id,
        if (match[1] == 'series') 'xifan_series': id,
        'title': title,
        'cover_url': image?.attributes['src'] ?? '',
        'catalog_source': CatalogSource.xifan.name,
      });
    }
    return groups.where((g) => catalogList(g['videos']).isNotEmpty).toList();
  }

  Future<String> _xifanDocument(String path) async =>
      (await retryPublicCatalogRead(
        () => _xifanWeb.get<String>(
          path,
          options: Options(responseType: ResponseType.plain),
        ),
      )).data ??
      '';

  Future<List<CatalogJson>> _xifanItems(List<int> ids) async {
    if (ids.isEmpty) return [];
    final result = await retryPublicCatalogRead(
      () => _xifan.get<dynamic>(
        '/rest/v1/animes',
        queryParameters: {'select': _xFields, 'id': 'in.(${ids.join(',')})'},
      ),
    );
    return _rows(CatalogSource.xifan, result.data);
  }

  Future<List<CatalogJson>> xifanSeries(int id) async {
    if (id <= 0) throw ArgumentError.value(id);
    final doc = html.parse(await _xifanDocument('/series/$id'));
    final ids = <int>{};
    void visit(Object? value) {
      if (value is List) {
        for (final item in value) {
          visit(item);
        }
      } else if (value is Map) {
        final url = Uri.tryParse('${value['url'] ?? ''}');
        if (url?.host == 'next.xifanacg.com' &&
            url?.pathSegments.length == 2 &&
            url?.pathSegments.first == 'anime') {
          final item = int.tryParse(url!.pathSegments.last);
          if (item != null) ids.add(item);
        }
        for (final item in value.values) {
          visit(item);
        }
      }
    }

    for (final script in doc.querySelectorAll(
      'script[type="application/ld+json"]',
    )) {
      try {
        visit(jsonDecode(script.text));
      } catch (_) {}
    }
    final rows = {
      for (final row in await _xifanItems(ids.take(100).toList()))
        catalogInt(row['video_id']): row,
    };
    return [
      for (final item in ids)
        if (rows[item] case final row?) row,
    ];
  }

  Future<List<CatalogJson>> _xifanHome() async {
    final groups = xifanHomeSections(await _xifanDocument('/'));
    final previous =
        await CatalogDiskCache.read('xifan-official-home-v1') ?? [];
    if (groups.isEmpty) {
      if (previous.isNotEmpty) return previous;
      throw StateError('稀饭主页加载失败');
    }
    final ids = {
      for (final group in groups)
        for (final row in catalogList(group['videos']))
          if (row['xifan_series'] == null) catalogInt(row['video_id']),
    };
    final rows = {
      for (final row in await _xifanItems(ids.toList()))
        catalogInt(row['video_id']): row,
    };
    final latest = <CatalogJson>[
      for (final group in groups)
        {
          ...group,
          'videos': [
            for (final row in catalogList(group['videos']))
              if (row['xifan_series'] != null)
                row
              else
                {
                  ...row,
                  ...?rows[catalogInt(row['video_id'])],
                  if (group['layout'] == 'hero' &&
                      '${row['cover_url']}'.startsWith('https://'))
                    'cover_url': row['cover_url'],
                },
          ],
        },
    ];
    final keyed = <String, CatalogJson>{
      for (final row in previous) row['name'].toString(): row,
      for (final row in latest) row['name'].toString(): row,
    };
    final result = [
      for (final name in ['焦点推荐', '追番周表', '热门の新番', '刚上架の旧番', '高分合集'])
        if (keyed[name] case final row?) row,
    ];
    await CatalogDiskCache.write('xifan-official-home-v1', result);
    return result;
  }

  Future<List<CatalogJson>> recommendations(CatalogSource source) async {
    if (source == CatalogSource.cycani) {
      final groups = await Future.wait([
        _cycani.recommendations(),
        _cycaniBanners(),
      ]);
      return [
        if (groups[1].isNotEmpty)
          {'name': '焦点推荐', 'layout': 'hero', 'videos': groups[1]},
        ...groups[0],
      ];
    }
    if (source == CatalogSource.xifan) return _xifanHome();
    Future<List<CatalogJson>> recommended() async {
      final response = await retryPublicCatalogRead(
        () => _giri.post<dynamic>(
          '/App2/likeList',
          data: {'user_id': '', 'pageSize': '24'},
        ),
      );
      return _rows(source, _giriInfo(response.data));
    }

    Future<CatalogJson?> section(
      String name,
      Future<List<CatalogJson>> Function() load,
    ) async {
      try {
        final videos = await load();
        return videos.isEmpty ? null : {'name': name, 'videos': videos};
      } catch (_) {
        return null;
      }
    }

    Future<List<CatalogJson>> list(
      String order, {
      String kind = '',
      String? year,
    }) async => (await browse(
      source,
      1,
      kind: kind,
      order: order,
      year: year,
    )).items.take(12).toList();
    Future<List<CatalogJson>> giriFeatured() async {
      final banners = catalogList(
        _giriInfo(
          (await retryPublicCatalogRead(
            () => _giri.get<dynamic>('/App2/bannerList'),
          )).data,
        ),
      );
      return [
        for (final b in banners)
          if (int.tryParse('${b['video_key'] ?? ''}') case final int id
              when id > 0)
            {
              'catalog_source': source.name,
              'video_id': id,
              'title': b['title'],
              'cover_url': b['cover'],
            },
      ];
    }

    Future<CatalogJson?> giriNotice() async {
      try {
        final data = catalogMap(
          _giriInfo(
            (await retryPublicCatalogRead(
              () => _giri.get<dynamic>(
                '/App2/appConfigData',
                queryParameters: {'key': 'notice_home'},
              ),
            )).data,
          ),
        );
        final message = '${data['art_content'] ?? ''}'.trim();
        if (catalogInt(data['state']) != 1 || message.isEmpty) return null;
        return {
          'name': '公告',
          'layout': 'text',
          'text': html.parseFragment(message).text,
        };
      } catch (_) {
        return null;
      }
    }

    Future<List<CatalogJson>>? tvRequest;
    Future<List<CatalogJson>> tv() =>
        tvRequest ??= list('update_time', kind: 'tv');
    final extra = await Future.wait([
      section('精选番剧', () async {
        try {
          final banners = await giriFeatured();
          if (banners.isNotEmpty) return banners;
        } catch (_) {
          // The rest of the homepage does not depend on the banner endpoint.
        }
        return (await tv()).take(5).toList();
      }),
      giriNotice(),
      section('新番发现', tv),
      section('日番', tv),
      section('剧场版', () => list('update_time', kind: 'movie')),
      section(
        '为你推荐',
        recommended,
      ).then((r) => r ?? {'name': '为你推荐', 'videos': <CatalogJson>[]}),
    ]);
    return [
      for (final (index, group) in extra.indexed) ...[
        if (group != null)
          {
            ...group,
            if (index == 0) 'layout': 'hero',
            if (group['name'] == '为你推荐') 'layout': 'personalized',
          },
      ],
    ];
  }

  static const _xFields =
      'id,title,title_original,aliases,season_number,cover_url,release_year,bangumi_id,description,format,bangumi_score,region';

  static const giriKinds = <String, String>{
    '': '全部',
    '2': '日番',
    '3': '美番',
    '21': '剧场版',
    '20': '真人番剧',
    '24': 'BD副音轨',
    '26': '演唱会及其他',
  };
  static const xifanKinds = <String, String>{
    '': '全部',
    'tv': 'TV 动画',
    'movie': '剧场版',
    'ova': 'OVA',
    'oad': 'OAD',
    'web': 'Web 动画',
    'other': '其他',
  };
  static const xifanTags = [
    '冒险',
    '原创',
    '后宫',
    '喜剧',
    '奇幻',
    '小说改',
    '少女向',
    '少年向',
    '恋爱',
    '悬疑',
    '战斗',
    '推理',
    '日常',
    '机战',
    '校园',
    '游戏改',
    '漫画改',
    '百合',
    '科幻',
    '穿越',
    '美食',
    '职场',
  ];

  Future<Map<String, List<String>>> giriBrowseFilters() async {
    List<String> values(Object? data) =>
        data is List ? data.whereType<String>().toSet().toList() : [];
    Future<CatalogJson> load(String path) async {
      try {
        final data = await retryPublicCatalogRead(
          () => _giri.get<dynamic>(
            path,
            queryParameters: path.endsWith('getAllTagOption')
                ? null
                : {'type_id_1': '0'},
          ),
        );
        return catalogMap(_giriInfo(data.data));
      } catch (_) {
        return {};
      }
    }

    final data = await Future.wait(
      [
        '/Vod/get_year',
        '/Vod/get_area',
        '/Vod/get_class',
        '/Vod/getAllTagOption',
      ].map(load),
    );
    final fresh = <String, List<String>>{
      'year': values(data[0]['rows']),
      'area': values(data[1]['rows']),
      'genre': values(data[2]['rows']),
      'version': values(data[3]['vod_version']),
      'state': values(data[3]['vod_state']),
    };
    final previous =
        (await CatalogDiskCache.read('giri-browse-filters'))?.firstOrNull ?? {};
    for (final key in fresh.keys.toList()) {
      if (fresh[key]!.isEmpty) fresh[key] = values(previous[key]);
    }
    if (fresh.values.any((v) => v.isNotEmpty)) {
      await CatalogDiskCache.write('giri-browse-filters', [fresh]);
    }
    return fresh;
  }

  Future<CatalogPage> browse(
    CatalogSource source,
    int page, {
    String kind = '',
    String? year,
    String order = 'update_time',
    String? finished,
    genre,
    area,
    version,
    state,
    CancelToken? cancelToken,
  }) async {
    const size = 36;
    if (source == CatalogSource.cycani) {
      return CatalogPage.fromJson(
        await _cycani.videos(
          page: page,
          year: year,
          order: order,
          cancelToken: cancelToken,
        ),
        page: page,
      );
    }
    if (source == CatalogSource.xifan) {
      final rows = _rows(
        source,
        (await retryPublicCatalogRead(
          () => _xifan.get<dynamic>(
            '/rest/v1/animes',
            queryParameters: {
              'select': _xFields,
              'is_published': 'eq.true',
              if (kind.isNotEmpty) 'format': 'eq.$kind',
              if (year == 'older')
                'release_year': 'lt.2007'
              else if (year != null)
                'release_year': 'eq.$year',
              if (finished == '0' || finished == '1')
                'is_finished': 'eq.${finished == '1'}',
              if (genre != null && xifanTags.contains(genre))
                'meta_tags': 'cs.{"$genre"}',
              'order': switch (order) {
                'hits' => 'view_count.desc,id.desc',
                'score' => 'bangumi_score.desc.nullslast,id.desc',
                'release_date' => 'release_date.desc.nullslast,id.desc',
                _ => 'updated_at.desc,id.desc',
              },
              'limit': size,
              'offset': (page - 1) * size,
            },
            cancelToken: cancelToken,
          ),
        )).data,
      );
      return CatalogPage(rows, hasMore: rows.length == size);
    }
    final info = catalogMap(
      _giriInfo(
        (await retryPublicCatalogRead(
          () => _giri.get<dynamic>(
            '/Vod/get_list',
            queryParameters: {
              if (kind.isNotEmpty)
                'type_id': kind == 'movie'
                    ? 21
                    : kind == 'tv'
                    ? 2
                    : int.tryParse(kind),
              if (area != null) 'vod_area': area,
              if (genre != null) 'vod_class': genre,
              if (version != null) 'vod_version': version,
              if (state != null) 'vod_state': state,
              if (year != null) 'vod_year': year,
              'orderby': switch (order) {
                'hits' => 'hits',
                'score' => 'score',
                _ => 'pubdate',
              },
              'offset': (page - 1) * size,
              'limit': size,
              'user_id': '',
            },
            cancelToken: cancelToken,
          ),
        )).data,
      ),
    );
    final rows = _rows(source, info['rows']);
    final total = catalogInt(info['total']);
    return CatalogPage(
      rows,
      hasMore: rows.isNotEmpty && page * size < total,
      total: total,
    );
  }

  Future<List<CatalogJson>> giriRankingGroups() async {
    final data = (await retryPublicCatalogRead(
      () => _giri.get<dynamic>('/App2/vodSortList'),
    )).data;
    return catalogList(_giriInfo(data))
        .where(
          (r) =>
              catalogInt(r['id']) > 0 && '${r['title'] ?? ''}'.trim().isNotEmpty,
        )
        .toList();
  }

  Future<List<CatalogJson>> giriRanking(int id) async =>
      (await giriRankingPage(id, 1)).items;

  Future<CatalogPage> giriRankingPage(int id, int page) async {
    const pageSize = 20;
    final data = (await retryPublicCatalogRead(
      () => _giri.get<dynamic>(
        '/App2/vodSortSearch',
        queryParameters: {
          'id': id,
          'page': page,
          'pageSize': pageSize,
          'user_id': '',
        },
      ),
    )).data;
    final info = catalogMap(_giriInfo(data));
    final items = _rows(CatalogSource.giri, info['rows']);
    final total = catalogInt(info['total']);
    return CatalogPage(
      items,
      total: total,
      hasMore: items.isNotEmpty && page * pageSize < total,
    );
  }

  static List<int> xifanRankingIds(String document) {
    final ids = <int, int>{};
    for (final link
        in html.parse(document).querySelectorAll('a[aria-label][href]')) {
      final rank = RegExp(
        r'^第\s*(\d+)\s*名',
      ).firstMatch(link.attributes['aria-label'] ?? '');
      final anime = RegExp(
        r'^/anime/(\d+)$',
      ).firstMatch(link.attributes['href'] ?? '');
      if (rank != null && anime != null) {
        ids.putIfAbsent(int.parse(rank[1]!), () => int.parse(anime[1]!));
      }
    }
    return (ids.keys.toList()..sort())
        .map((rank) => ids[rank]!)
        .toSet()
        .take(50)
        .toList();
  }

  Future<List<CatalogJson>> xifanWeeklyRanking() async {
    final ids = xifanRankingIds(await _xifanDocument('/rankings'));
    if (ids.isEmpty) throw StateError('稀饭周热榜加载失败');
    final rows = {
      for (final row in await _xifanItems(ids)) catalogInt(row['video_id']): row,
    };
    return [
      for (final id in ids)
        if (rows[id] case final row?) row,
    ];
  }

  Future<List<CatalogJson>> ranking(
    CatalogSource source, {
    required bool movie,
    CancelToken? cancelToken,
  }) async {
    if (source == CatalogSource.xifan)
      return _rows(
        source,
        (await retryPublicCatalogRead(
          () => _xifan.get<dynamic>(
            '/rest/v1/animes',
            queryParameters: {
              'select': _xFields,
              'format': movie ? 'eq.movie' : 'eq.tv',
              'is_published': 'eq.true',
              'order': 'view_count.desc,id.desc',
              'limit': 50,
            },
            cancelToken: cancelToken,
          ),
        )).data,
      );
    if (source == CatalogSource.giri) {
      final info = catalogMap(
        _giriInfo(
          (await retryPublicCatalogRead(
            () => _giri.get<dynamic>(
              '/Vod/get_list',
              queryParameters: {
                'type_id': movie ? 21 : 2,
                'orderby': 'hits_week',
                'limit': 50,
                'offset': 0,
                'user_id': '',
              },
              cancelToken: cancelToken,
            ),
          )).data,
        ),
      );
      return _rows(source, info['rows']);
    }
    final ranks = await _cycani.ranks();
    final name = movie ? '剧场番组' : 'TV番组';
    final row = ranks
        .where((r) => '${r['name']}'.replaceAll(' ', '') == name)
        .firstOrNull;
    return row == null ? [] : _cycani.rankVideos(catalogInt(row['id']));
  }

  Future<List<CatalogJson>>? _giriWeek;
  DateTime? _giriWeekLoaded;
  Future<List<CatalogJson>> _giriSchedule() async {
    final now = DateTime.now();
    if (_giriWeek != null &&
        _giriWeekLoaded != null &&
        now.difference(_giriWeekLoaded!) < const Duration(minutes: 1))
      return _giriWeek!;
    _giriWeekLoaded = now;
    final request = () async => catalogList(
      _giriInfo(
        (await retryPublicCatalogRead(
          () => _giri.get<dynamic>('/App2/weekList'),
        )).data,
      ),
    );
    final pending = request();
    _giriWeek = pending;
    try {
      return await pending;
    } catch (_) {
      if (identical(_giriWeek, pending)) {
        _giriWeek = null;
        _giriWeekLoaded = null;
      }
      rethrow;
    }
  }

  final _scheduleSnapshots = <(CatalogSource, int), List<CatalogJson>>{};

  Future<List<CatalogJson>> mergedSchedule(int day) async {
    if (day < 1 || day > 7) throw ArgumentError.value(day);
    final sections = await Future.wait(
      CatalogSource.values.map((source) async {
        final key = (source, day);
        final diskKey = 'schedule-source:${source.name}:$day';
        try {
          final groups = await schedule(source, day);
          final rows = groups
              .expand((g) => catalogList(g['videos']))
              .map((row) => {...row, 'catalog_source': source.name})
              .toList();
          _scheduleSnapshots[key] = rows;
          if (identical(this, instance)) {
            await CatalogDiskCache.write(diskKey, rows);
          }
          return rows;
        } catch (_) {
          return _scheduleSnapshots[key] ??
              (identical(this, instance)
                  ? await CatalogDiskCache.read(diskKey)
                  : null);
        }
      }),
    );
    if (sections.every((rows) => rows == null)) throw StateError('周表加载失败');
    final rows = mergeCatalogRows(
      sections.whereType<List<CatalogJson>>().expand((rows) => rows).toList(),
    );
    return [
      {'name': '周表', 'videos': rows},
    ];
  }

  // weekList 的行不带评分；当年条目的 vod_id→vod_score 索引按天缓存，
  // 供周表卡片显示 GiriGiri 评分（数据来自 get_list，多数条目 > 0）。
  final _giriScores = <int, double>{};
  String? _giriScoresDay;
  Future<void>? _giriScoresRefresh;

  Future<void> _ensureGiriScores() {
    final now = DateTime.now();
    final day = '${now.year}-${now.month}-${now.day}';
    if (_giriScoresDay == day) return Future.value();
    // 并发去重（single-flight）：周表多个入口同时触发时共享同一次刷新，
    // 避免重复发起最多 20 次分页请求、后进入者 clear 掉先进入者已填充的数据。
    return _giriScoresRefresh ??= () async {
      try {
        await _loadGiriScores(day);
      } finally {
        _giriScoresRefresh = null;
      }
    }();
  }

  Future<void> _loadGiriScores(String day) async {
    final now = DateTime.now();
    final diskKey = 'giri-score-index:${now.year}';
    _giriScores.clear();

    final cached = await CatalogDiskCache.read(diskKey);
    if (cached != null &&
        cached.isNotEmpty &&
        '${cached.first['day']}' == day) {
      for (final row in cached) {
        final score = double.tryParse('${row['score']}');
        if (score != null && score > 0) {
          _giriScores[catalogInt(row['id'])] = score;
        }
      }
      _giriScoresDay = day;
      return;
    }

    final diskRows = <CatalogJson>[];
    try {
      for (var offset = 0; offset < 1000; offset += 50) {
        final data = await retryPublicCatalogRead(
          () => _giri.get<dynamic>(
            '/Vod/get_list',
            queryParameters: {
              'vod_year': '${now.year}',
              'limit': 50,
              'offset': offset,
              'user_id': '',
            },
          ),
        );
        final rows = catalogList(catalogMap(_giriInfo(data))['rows']);
        for (final row in rows) {
          final id = catalogInt(row['vod_id']);
          final score = double.tryParse('${row['vod_score']}');
          if (id > 0) {
            if (score != null && score > 0) _giriScores[id] = score;
            diskRows.add({'id': id, 'score': score ?? 0, 'day': day});
          }
        }
        if (rows.length < 50) break;
      }
    } catch (_) {
      // 拉取失败时仍写空索引标记到当天，避免每次周表刷新都重试。
    }
    if (diskRows.isNotEmpty) {
      unawaited(CatalogDiskCache.write(diskKey, diskRows));
    }
    _giriScoresDay = day;
  }

  Future<List<CatalogJson>> schedule(CatalogSource source, int day) async {
    if (day < 1 || day > 7) throw ArgumentError.value(day);
    if (source == CatalogSource.cycani) return _cycani.schedule(day);
    final rows = source == CatalogSource.xifan
        ? _rows(
            source,
            (await retryPublicCatalogRead(
              () => _xifan.get<dynamic>(
                '/rest/v1/animes',
                queryParameters: {
                  'select': _xFields,
                  'is_published': 'eq.true',
                  'is_finished': 'eq.false',
                  'update_weekday': 'eq.$day',
                  'order': 'updated_at.desc,id.desc',
                  'limit': 100,
                },
              ),
            )).data,
          )
        : _rows(
            source,
            (await _giriSchedule())
                .where((r) => catalogInt(r['week']) == day)
                .firstOrNull?['video'],
          );
    if (source == CatalogSource.giri) {
      try {
        await _ensureGiriScores();
        for (final row in rows) {
          final score = _giriScores[catalogInt(row['video_id'])];
          if (score != null && score > 0) row['score'] = score;
        }
      } catch (_) {
        // 评分索引失败不影响周表本身。
      }
    }
    return [
      {'name': '周表', 'videos': rows},
    ];
  }

  Future<CatalogPage> searchSource(
    CatalogSource source,
    String keyword,
    int page,
  ) async {
    const size = 36;
    if (source == CatalogSource.cycani) {
      final result = CatalogPage.fromJson(
        await _cycani.videos(keyword: keyword, page: page),
        page: page,
      );
      return CatalogPage(
        _rows(source, result.items),
        hasMore: result.hasMore,
        total: result.total,
      );
    }
    if (source == CatalogSource.giri) {
      final info = catalogMap(
        _giriInfo(
          (await retryPublicCatalogRead(
            () => _giri.get<dynamic>(
              '/Vod/get_list',
              queryParameters: {
                'vod_name': keyword,
                'limit': size,
                'offset': (page - 1) * size,
                'user_id': '',
              },
            ),
          )).data,
        ),
      );
      final rows = _rows(source, info['rows']);
      return CatalogPage(
        rows,
        hasMore: rows.isNotEmpty && page * size < catalogInt(info['total']),
      );
    }
    final safe = keyword.replaceAll(RegExp(r'["\\*%]'), ' ').trim();
    if (safe.isEmpty) return const CatalogPage([], hasMore: false);
    final rows = _rows(
      source,
      (await retryPublicCatalogRead(
        () => _xifan.get<dynamic>(
          '/rest/v1/animes',
          queryParameters: {
            'select': _xFields,
            'or': '(title.ilike."*$safe*",title_original.ilike."*$safe*")',
            'is_published': 'eq.true',
            'order': 'view_count.desc,id.desc',
            'limit': size,
            'offset': (page - 1) * size,
          },
        ),
      )).data,
    );
    return CatalogPage(rows, hasMore: rows.length == size);
  }

  final _searchSnapshots = CatalogLru<(CatalogSource, String), CatalogPage>();

  Future<CatalogPage> search(String keyword, int page) async {
    final results = await Future.wait(
      CatalogSource.values.map((source) async {
        final key = (source, keyword);
        final diskKey = 'search-source:${source.name}:$keyword';
        try {
          final result = await searchSource(source, keyword, page);
          if (page == 1) {
            _searchSnapshots.remove(key);
            _searchSnapshots[key] = result;
            if (identical(this, instance)) {
              await CatalogDiskCache.write(diskKey, [
                {'rows': result.items, 'more': result.hasMore},
              ]);
            }
          }
          return result;
        } catch (_) {
          if (page != 1) return null;
          final cached = _searchSnapshots[key];
          if (cached != null) return cached;
          if (!identical(this, instance)) return null;
          final saved = (await CatalogDiskCache.read(diskKey))?.firstOrNull;
          if (saved == null) return null;
          return CatalogPage(
            catalogList(saved['rows']),
            hasMore: saved['more'] == true,
          );
        }
      }),
    );
    final available = results.whereType<CatalogPage>().toList();
    if (available.isEmpty) throw StateError('搜索失败');
    return CatalogPage(
      available.expand((r) => r.items).toList(),
      hasMore: available.any((r) => r.hasMore),
    );
  }
}
