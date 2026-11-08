import 'catalog_http.dart';
import 'package:dio/dio.dart';
import 'catalog_danmaku_codec.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'cycani_models.dart';
import 'cycani_danmaku_options.dart';

class XifanEpisodeMatch {
  const XifanEpisodeMatch(this.animeId, this.episodeId, this.dandanEpisodeId);
  final int animeId;
  final int episodeId;
  final int dandanEpisodeId;
}

/// Separate, fixed-origin clients: never forward Cycani user sessions, signed
/// media URLs, or Dandan application secrets to another provider.
class CycaniRemoteDanmaku {
  CycaniRemoteDanmaku({Dio? xifanDio, Dio? relayDio})
    : _xifan = xifanDio ?? _client(xifanOrigin, {'apikey': publicClientKey}),
      _relay = relayDio ?? _client(relayOrigin, const {}) {
    _xifan.options.headers.removeWhere(
      (key, _) => const ['authorization', 'cookie'].contains(key.toLowerCase()),
    );
    _relay.options.headers.removeWhere(
      (key, _) => const [
        'authorization',
        'cookie',
        'apikey',
        'x-appid',
        'x-appsecret',
        'x-signature',
      ].contains(key.toLowerCase()),
    );
    _xifan.options.followRedirects = false;
    _relay.options.followRedirects = false;
    _xifan.options.baseUrl = xifanOrigin;
    _xifan.options.headers['apikey'] = publicClientKey;
    _relay.options.baseUrl = relayOrigin;
  }
  static final instance = CycaniRemoteDanmaku();
  static const xifanOrigin = 'https://api.xifanacg.com';
  static const relayOrigin = 'https://ext-danmaku.moedot.net';
  // Publishable browser client key served by next.xifanacg.com, not a user JWT.
  static const publicClientKey =
      'sb_publishable_OBIVAWACIX6lPXrO98_z24_HcsmalkA';
  final Dio _xifan;
  final Dio _relay;
  final _matches = <String, Future<XifanEpisodeMatch?>>{};
  final _relayEpisodes = <int, Future<Map<int, int>>>{};

  static Dio _client(String origin, Map<String, String> headers) =>
      CatalogHttp.client(origin, headers);

  /// Exact identity only. A title resemblance or list index is not enough to
  /// combine comments belonging to a different season or a special episode.
  Future<XifanEpisodeMatch?> match(int bangumiId, int episode) {
    if (bangumiId <= 0 || episode <= 0) return Future.value(null);
    final key = '$bangumiId:$episode';
    return _matches.putIfAbsent(key, () async {
      try {
        final rows = cycaniList(
          (await _xifan.get<dynamic>(
            '/rest/v1/animes',
            queryParameters: {
              'bangumi_id': 'eq.$bangumiId',
              'select': 'id,bangumi_id',
              'limit': 2,
            },
          )).data,
        );
        if (rows.length != 1 ||
            cycaniInt(rows.single['bangumi_id']) != bangumiId) {
          _matches.remove(key);
          return null;
        }
        final animeId = cycaniInt(rows.single['id']);
        final eps = cycaniList(
          (await _xifan.get<dynamic>(
            '/rest/v1/episodes',
            queryParameters: {
              'anime_id': 'eq.$animeId',
              'episode_number': 'eq.$episode',
              'kind': 'eq.main',
              'select': 'id,episode_number,dandan_episode_id',
              'limit': 2,
            },
          )).data,
        );
        if (eps.length != 1 ||
            double.tryParse('${eps.single['episode_number']}') != episode) {
          _matches.remove(key);
          return null;
        }
        final id = cycaniInt(eps.single['id']);
        if (id <= 0) {
          _matches.remove(key);
          return null;
        }
        return XifanEpisodeMatch(
          animeId,
          id,
          cycaniInt(eps.single['dandan_episode_id']),
        );
      } catch (_) {
        _matches.remove(key);
        rethrow;
      }
    });
  }

  Future<Map<int, int>> _episodeIds(int bgmId) =>
      _relayEpisodes.putIfAbsent(bgmId, () async {
        try {
          final data = cycaniMap(
            (await _relay.get<dynamic>('/api/v2/bangumi/bgmtv/$bgmId')).data,
          );
          if (data['success'] == false) throw StateError('外部弹幕匹配失败');
          final episodes = cycaniList(cycaniMap(data['bangumi'])['episodes']);
          final result = <int, int>{};
          for (final row in episodes) {
            final n = double.tryParse('${row['episodeNumber']}');
            final id = cycaniInt(row['episodeId']);
            if (n != null &&
                n.isFinite &&
                n > 0 &&
                n == n.truncateToDouble() &&
                id > 0) {
              final number = n.toInt();
              // Ambiguous episode numbers must not silently select one variant.
              result[number] = result.containsKey(number) ? 0 : id;
            }
          }
          if (result.isEmpty) _relayEpisodes.remove(bgmId);
          return result;
        } catch (_) {
          _relayEpisodes.remove(bgmId);
          rethrow;
        }
      });

  Future<List<DanmakuEntry>> external(
    int bangumiId,
    int episode, {
    int chConvert = 1,
  }) async {
    if (bangumiId <= 0 || episode <= 0) return [];
    XifanEpisodeMatch? mapped;
    try {
      mapped = await match(bangumiId, episode);
    } catch (_) {}
    final id = mapped?.dandanEpisodeId ?? 0;
    final episodeId = id > 0
        ? id
        : (await _episodeIds(bangumiId))[episode] ?? 0;
    if (episodeId <= 0) {
      _relayEpisodes.remove(bangumiId);
      return [];
    }
    final data = cycaniMap(
      (await _relay.get<dynamic>(
        '/api/v2/comment/$episodeId',
        queryParameters: {'withRelated': 'true', 'chConvert': '$chConvert'},
      )).data,
    );
    if (data['success'] == false) throw StateError('外部弹幕加载失败');
    final rows = data['comments'];
    if (rows is! List) throw const FormatException('外部弹幕格式无效');
    final result = <DanmakuEntry>[];
    for (final row in rows.whereType<Map>()) {
      try {
        final item = DanmakuEntry.fromJson(Map<String, dynamic>.from(row));
        if (item.message.trim().isEmpty || !item.time.isFinite || item.time < 0)
          continue;
        item.source = CycaniDanmakuOptions.externalSource;
        result.add(item);
      } catch (_) {
        /* A malformed comment must not discard a whole provider. */
      }
    }
    return result;
  }

  Future<List<DanmakuEntry>> site(int bangumiId, int episode) async {
    final mapped = await match(bangumiId, episode);
    if (mapped == null) return [];
    return siteEpisode(mapped.episodeId);
  }

  Future<List<DanmakuEntry>> siteEpisode(int episodeId) async {
    if (episodeId <= 0) throw ArgumentError.value(episodeId);
    final result = <DanmakuEntry>[];
    final seen = <int>{};
    var after = 0;
    while (true) {
      final data = (await _xifan.post<dynamic>(
        '/rest/v1/rpc/get_danmaku_page',
        data: {'p_episode_id': episodeId, 'p_after_id': after, 'p_limit': 500},
      )).data;
      if (data is! List) throw const FormatException('稀饭弹幕格式无效');
      final rows = cycaniList(data);
      var next = after;
      for (final row in rows) {
        final id = cycaniInt(row['id']);
        if (id > next) next = id;
        if (id <= 0 || !seen.add(id)) continue;
        final time = double.tryParse('${row['v_time']}');
        final message = row['content'];
        if (time == null ||
            !time.isFinite ||
            time < 0 ||
            message is! String ||
            message.trim().isEmpty)
          continue;
        final color =
            int.tryParse('${row['color']}'.replaceFirst('#', ''), radix: 16) ??
            0xFFFFFF;
        result.add(
          DanmakuEntry(
            message: message,
            time: time,
            type: CatalogDanmakuCodec.namedMode(row['mode']),
            color: CatalogDanmakuCodec.color(color),
            source: CycaniDanmakuOptions.xifanSource,
          ),
        );
      }
      if (rows.length < 500) break;
      if (next <= after) throw const FormatException('稀饭弹幕分页未前进');
      after = next;
    }
    return result;
  }
}
