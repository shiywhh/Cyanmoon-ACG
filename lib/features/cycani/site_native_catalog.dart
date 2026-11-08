import 'catalog_lru.dart';
import 'catalog_http.dart';
import 'catalog_read_retry.dart';
import 'dart:async';
import 'catalog_disk_cache.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'package:cyanmoon_acg/modules/roads/road_module.dart';
import 'catalog_models.dart';
import 'catalog_aggregator.dart';
import 'cycani_remote_danmaku.dart';

class NativeCatalogDetail {
  const NativeCatalogDetail(this.video, this.roads, {this.related = const []});
  final List<CatalogJson> related;
  final CatalogVideo video;
  final List<Road> roads;
  CatalogJson toSnapshot() => {
    'video': video.json,
    'related': related,
    'roads': [
      for (final r in roads)
        {'name': r.name, 'data': r.data, 'labels': r.identifier},
    ],
  };

  static NativeCatalogDetail? fromSnapshot(CatalogJson data) {
    final video = CatalogVideo(catalogMap(data['video']));
    if (video.id <= 0) return null;
    return NativeCatalogDetail(video, [
      for (final r in catalogList(data['roads']))
        if (r['data'] is List &&
            r['labels'] is List &&
            (r['data'] as List).length == (r['labels'] as List).length)
          Road(
            name: r['name'].toString(),
            data: (r['data'] as List).map((v) => v.toString()).toList(),
            identifier: (r['labels'] as List).map((v) => v.toString()).toList(),
          ),
    ], related: catalogList(data['related']));
  }
}

class NativeCatalogApi {
  NativeCatalogApi({Dio? xifan, Dio? giri})
    : _x =
          xifan ??
          _client('https://api.xifanacg.com', {
            'apikey': CycaniRemoteDanmaku.publicClientKey,
            'Origin': 'https://next.xifanacg.com',
          }),
      _g =
          giri ??
          _client('https://m3u8.girigirilove.com', {
            'Origin': 'https://ani.girigirilove.com',
            'Referer': 'https://ani.girigirilove.com/home',
          });
  static final instance = NativeCatalogApi();
  final Dio _x, _g;
  static Dio _client(String origin, Map<String, String> headers) =>
      CatalogHttp.client(origin, headers);

  static Uri? giriMedia(String text) {
    final u = Uri.tryParse(text);
    if (u == null ||
        u.scheme != 'https' ||
        u.userInfo.isNotEmpty ||
        u.port != 443 ||
        !const [
          'girigirilove.com',
          'girigirilove.top',
          'girigirilove.net',
        ].any((h) => u.host == h || u.host.endsWith('.$h')) ||
        !RegExp(r'\.(m3u8|mp4)$', caseSensitive: false).hasMatch(u.path))
      return null;
    return u;
  }

  static (int, int)? xifanEpisode(String text) {
    final u = Uri.tryParse(text);
    if (u == null ||
        u.scheme != 'https' ||
        u.host != 'next.xifanacg.com' ||
        u.port != 443 ||
        u.userInfo.isNotEmpty ||
        u.hasQuery)
      return null;
    final m = RegExp(r'^/anime/([1-9]\d*)/play/([1-9]\d*)$').firstMatch(u.path);
    if (m == null) return null;
    final a = int.tryParse(m[1]!);
    final e = int.tryParse(m[2]!);
    return a == null || e == null ? null : (a, e);
  }

  Future<String> xifanPlayback(
    int anime,
    int episode, {
    int preferCandidate = 0,
  }) async {
    final d = catalogMap(
      (await _x.post<dynamic>(
        '/functions/v1/issue-web-playback',
        data: {'action': 'fallback', 'episode_id': episode},
      )).data,
    );
    if (d['ok'] != true ||
        catalogInt(d['anime_id']) != anime ||
        catalogInt(d['episode_id']) != episode) {
      throw const FormatException('播放地址无效');
    }
    // Some issued CDN nodes reject the signs they were given ("sign invalid"),
    // so probe the primary URL and every candidate and serve the first node
    // that actually streams. If nothing responds, keep the primary URL and
    // let the player surface the error.
    final urls = <String>[
      for (final row in [d, ...catalogList(d['candidates'])])
        if (catalogMap(row)['url'] case final String url
            when url.startsWith('https://'))
          url,
    ];
    var usable = {
      for (final url in urls)
        if (Uri.tryParse(url) case final Uri u?
            when u.scheme == 'https' &&
                u.host.isNotEmpty &&
                u.userInfo.isEmpty)
          url,
    }.toList();
    // A source road selects which candidate to try first (roads carry
    // #src=K fragments); the rest remain as fallbacks in original order.
    if (usable.length > 1 && preferCandidate > 0) {
      final at = preferCandidate % usable.length;
      usable = [...usable.sublist(at), ...usable.take(at)];
    }
    for (final url in usable) {
      if (await _streams(url)) return url;
    }
    if (usable.isNotEmpty) return usable.first;
    throw const FormatException('播放地址无效');
  }

  /// Cheap ranged GET: 200/206 means the signed node accepts this URL.
  Future<bool> _streams(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl('GET', Uri.parse(url))
        ..headers.set('Range', 'bytes=0-1');
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == 200 || response.statusCode == 206;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static List<Road> giriRoads(CatalogJson info) {
    final names = '${info['vod_play_from'] ?? ''}'.split(r'$$$');
    final groups = '${info['vod_play_url'] ?? ''}'.split(r'$$$');
    final roads = <Road>[];
    for (var i = 0; i < groups.length; i++) {
      final data = <String>[], labels = <String>[];
      for (final item in groups[i].split('#')) {
        final sep = item.indexOf(r'$');
        if (sep < 1) continue;
        final u = giriMedia(item.substring(sep + 1).trim());
        if (u == null) continue;
        data.add(u.toString());
        labels.add(item.substring(0, sep));
      }
      if (data.isNotEmpty) {
        final name = i < names.length ? names[i] : '';
        roads.add(
          Road(
            name: switch (name) {
              'cht' => '繁体',
              'chs' => '简体',
              _ => '线路 ${i + 1}',
            },
            data: data,
            identifier: labels,
          ),
        );
      }
    }
    return roads;
  }

  static String _episodeLabel(Object? value) {
    final n = double.tryParse('$value');
    return n != null && n.isFinite && n == n.truncateToDouble()
        ? '${n.toInt()}'
        : '$value';
  }

  String _detailKey(CatalogSource source, int id) =>
      'detail:${source.name}:$id';

  Future<NativeCatalogDetail?> cachedDetail(
    CatalogSource source,
    int id,
  ) async {
    final rows = await CatalogDiskCache.read(_detailKey(source, id));
    return rows == null || rows.isEmpty
        ? null
        : NativeCatalogDetail.fromSnapshot(rows.first);
  }

  final _details =
      CatalogLru<(CatalogSource, int), Future<NativeCatalogDetail>>();

  Future<NativeCatalogDetail> detail(
    CatalogSource source,
    int id, {
    bool refresh = false,
  }) {
    final key = (source, id);
    if (refresh) _details.remove(key);
    return _details.putIfAbsent(key, () {
      final future = _fetchDetail(source, id).then((value) {
        unawaited(
          CatalogDiskCache.write(_detailKey(source, id), [value.toSnapshot()]),
        );
        return value;
      });
      future.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {
          if (identical(_details[key], future)) _details.remove(key);
        },
      );
      return future;
    });
  }

  Future<List<CatalogJson>> _relatedGiri(CatalogJson info, int id) async {
    final ids = RegExp(r'\d+')
        .allMatches('${info['vod_rel_vod'] ?? ''}')
        .map((m) => int.parse(m[0]!))
        .where((v) => v > 0 && v != id)
        .toSet()
        .take(8);
    final results = await Future.wait(
      ids.map((item) async {
        try {
          final response = await _g.get<dynamic>(
            '/api.php/Vod/get_detail',
            queryParameters: {'vod_id': item, 'user_id': ''},
          );
          final r = catalogMap(catalogMap(response.data)['info']);
          if (catalogInt(r['vod_id']) != item) return null;
          return <String, dynamic>{
            'video_id': item,
            'title': r['vod_name'],
            'cover_url': r['vod_pic'],
            'year': r['vod_year'],
            'catalog_source': 'giri',
          };
        } catch (_) {
          return null;
        }
      }),
    );
    return results.whereType<CatalogJson>().toList();
  }

  Future<List<CatalogJson>> _relatedXifan(CatalogJson anime, int id) async {
    final series = catalogInt(anime['series_id']);
    if (series <= 0) return [];
    try {
      final response = await _x.get<dynamic>(
        '/rest/v1/animes',
        queryParameters: {
          'series_id': 'eq.$series',
          'id': 'neq.$id',
          'is_published': 'eq.true',
          'select': 'id,title,cover_url,release_year,bangumi_id',
          'order': 'season_number.asc.nullslast,id.asc',
          'limit': 12,
        },
      );
      return [
        for (final row in catalogList(response.data))
          {
            ...row,
            'video_id': row['id'],
            'year': row['release_year'],
            'catalog_source': 'xifan',
          },
      ];
    } catch (_) {
      return [];
    }
  }

  Future<NativeCatalogDetail> _fetchDetail(CatalogSource source, int id) async {
    if (id <= 0) throw ArgumentError('无效的番剧');
    if (source == CatalogSource.giri) {
      final d = catalogMap(
        (await retryPublicCatalogRead(
          () => _g.get<dynamic>(
            '/api.php/Vod/get_detail',
            queryParameters: {'vod_id': id, 'user_id': ''},
          ),
        )).data,
      );
      final info = catalogMap(d['info']);
      if (catalogInt(d['code']) != 1 || catalogInt(info['vod_id']) != id)
        throw StateError('番剧加载失败');
      return NativeCatalogDetail(
        CatalogVideo({
          'video_id': 2000000000 + id,
          'catalog_source': 'giri',
          'title': info['vod_name'],
          'cover_url': info['vod_pic'],
          'year': info['vod_year'],
          'score': info['vod_score'],
          'subtitle': info['vod_sub'],
          'area': info['vod_area'],
          'version': info['vod_state'],
          'director': info['vod_director'],
          'actor': info['vod_actor'],
          'writer': info['vod_writer'],
          'language': info['vod_lang'],
          'tags': catalogUniqueLabels(
            '${info['vod_tag'] ?? ''},${info['vod_class'] ?? ''}'.split(
              RegExp('[,，、]'),
            ),
          ),

          'description': '${info['vod_content'] ?? info['vod_blurb'] ?? ''}'
              .replaceAll(RegExp(r'<[^>]*>'), ''),
        }),
        giriRoads(info),
        related: await _relatedGiri(info, id),
      );
    }
    if (source != CatalogSource.xifan) throw ArgumentError('无效来源');
    final parts = await Future.wait([
      _x.get<dynamic>(
        '/rest/v1/animes',
        queryParameters: {
          'id': 'eq.$id',
          'select':
              'id,title,title_original,cover_url,description,bangumi_id,release_year,bangumi_score,format,series_id,director,actors,aliases,region,meta_tags',
          'limit': 1,
        },
      ),
      _x.get<dynamic>(
        '/rest/v1/episodes',
        queryParameters: {
          'anime_id': 'eq.$id',
          'select': 'id,episode_number,title',
          'kind': 'eq.main',
          'order': 'episode_number.asc,id.asc',
          'limit': 1000,
        },
      ),
    ]);
    final a = catalogList(parts[0].data).single;
    final e = catalogList(
      parts[1].data,
    ).where((e) => catalogInt(e['id']) > 0).toList();
    final labels = [
      for (final item in e) '第${_episodeLabel(item['episode_number'])}集',
    ];
    final pageUrls = [
      for (final item in e)
        'https://next.xifanacg.com/anime/$id/play/${item['id']}',
    ];
    // 播放源线路：向播放接口问一次首集，拿候选源数量与名称。多余的源各成
    // 一条线路，页地址带 #src=K 片段，解析时优先使用第 K 个候选源。
    final sourceRoads = <Road>[];
    if (e.isNotEmpty) {
      try {
        final first = catalogMap(
          (await _x.post<dynamic>(
            '/functions/v1/issue-web-playback',
            data: {'action': 'fallback', 'episode_id': e.first['id']},
          )).data,
        );
        if (first['ok'] == true) {
          final candidates = catalogList(first['candidates']);
          for (var k = 1; k < candidates.length; k++) {
            final name = '${catalogMap(candidates[k])['source_name'] ?? ''}'
                .trim();
            sourceRoads.add(
              Road(
                name: name.isEmpty ? '稀饭·线路${k + 1}' : name,
                data: [
                  for (final item in e)
                    'https://next.xifanacg.com/anime/$id/play/${item['id']}#src=$k',
                ],
                identifier: labels,
              ),
            );
          }
        }
      } catch (_) {
        // 拿不到候选线路时退回单线路，解析仍会按节点探测可用地址。
      }
    }
    return NativeCatalogDetail(
      CatalogVideo({
        ...a,
        'video_id': 1000000000 + id,
        'catalog_source': 'xifan',
        'year': a['release_year'],
        'subtitle': a['title_original'] == a['title']
            ? null
            : a['title_original'],
        'version': a['format'] == 'tv'
            ? 'TV'
            : a['format'] == 'movie'
            ? '剧场版'
            : null,
        'score': a['bangumi_score'],
        'area': a['region'],
        'actor': a['actors'],
        'tags': a['meta_tags'],
      }),
      [
        if (e.isNotEmpty) ...[
          Road(name: '稀饭', data: pageUrls, identifier: labels),
          ...sourceRoads,
        ],
      ],
      related: await _relatedXifan(a, id),
    );
  }
}
