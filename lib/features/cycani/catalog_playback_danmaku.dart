import 'catalog_danmaku_cache.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'cycani_api.dart';
import 'catalog_aggregator.dart';
import 'catalog_danmaku_loader.dart';
import 'catalog_danmaku_options.dart';
import 'giri_danmaku.dart';
import 'catalog_models.dart';
import 'site_native_catalog.dart';
import 'cycani_remote_danmaku.dart';

/// Accept explicit episode labels only, never a list offset or a season number
/// embedded in a title. Fractional episodes remain fractional.
double? catalogEpisodeNumber(String title) {
  final normalized = title.trim();
  final pattern = RegExp(
    r'^(?:第\s*)?(\d+(?:\.\d+)?)\s*(?:集|话|話)?$',
    caseSensitive: false,
  );
  final prefixed = RegExp(
    r'^(?:EP|E|episode)\s*(\d+(?:\.\d+)?)$',
    caseSensitive: false,
  );
  final match =
      pattern.firstMatch(normalized) ?? prefixed.firstMatch(normalized);
  final value = match == null ? null : double.tryParse(match[1]!);
  return value != null && value.isFinite && value > 0 ? value : null;
}

String? catalogEpisodeUrl(List<Road> roads, double? episode) {
  if (episode == null) return null;
  for (final road in roads) {
    final matches = [
      for (var i = 0; i < road.identifier.length && i < road.data.length; i++)
        if (catalogEpisodeNumber(road.identifier[i]) == episode) road.data[i],
    ].toSet();
    if (matches.length == 1) return matches.single;
    // An ambiguous road cannot select an arbitrary episode.
  }
  return null;
}

class CatalogPlaybackDanmaku {
  CatalogPlaybackDanmaku({
    required this.source,
    required this.pageUrl,
    required String episodeTitle,
    required Map<String, int> videoIds,
    int bangumiId = 0,
    CycaniApi? cycani,
    NativeCatalogApi? native,
    CycaniRemoteDanmaku? remote,
    GiriDanmakuApi? giri,
  }) : episode = catalogEpisodeNumber(episodeTitle),
       ids = Map.unmodifiable(videoIds),
       seedBangumiId = bangumiId,
       api = cycani ?? CycaniApi.instance,
       catalog = native ?? NativeCatalogApi.instance,
       remote = remote ?? CycaniRemoteDanmaku.instance,
       giri = giri ?? GiriDanmakuApi.instance;

  final CatalogSource source;
  final String pageUrl;
  final double? episode;
  final Map<String, int> ids;
  final int seedBangumiId;
  final CycaniApi api;
  final NativeCatalogApi catalog;
  final CycaniRemoteDanmaku remote;
  final GiriDanmakuApi giri;
  Future<int>? _bgm;
  Future<int?>? _cycaniSection;
  Future<int?>? _xifanEpisode;
  Future<String?>? _giriPage;
  final _details = <CatalogSource, Future<NativeCatalogDetail>>{};

  Future<NativeCatalogDetail>? _detail(CatalogSource site) {
    final id = ids[site.name] ?? 0;
    if (id <= 0) return null;
    return _details.putIfAbsent(site, () => catalog.detail(site, id));
  }

  Future<int> _bangumiId() => _bgm ??= () async {
    if (seedBangumiId > 0) return seedBangumiId;
    final cycaniId = ids[CatalogSource.cycani.name] ?? 0;
    if (cycaniId > 0) {
      try {
        final id = (await api.detail(cycaniId)).bangumiId;
        if (id > 0) return id;
      } catch (_) {}
    }
    final xifan = _detail(CatalogSource.xifan);
    return xifan == null ? 0 : (await xifan).video.bangumiId;
  }();

  Future<int?> _section() => _cycaniSection ??= () async {
    if (source == CatalogSource.cycani) return cycaniSectionId(pageUrl);
    if (episode == null) return null;
    final id = ids[CatalogSource.cycani.name] ?? 0;
    if (id <= 0) return null;
    final roads = await api.episodes(id);
    final url = catalogEpisodeUrl(
      roads.map((r) => r.toRoad()).toList(),
      episode,
    );
    return url == null ? null : cycaniSectionId(url);
  }();

  Future<int?> _xifan() => _xifanEpisode ??= () async {
    if (source == CatalogSource.xifan) {
      return NativeCatalogApi.xifanEpisode(pageUrl)?.$2;
    }
    if (episode == null) return null;
    final detail = _detail(CatalogSource.xifan);
    if (detail != null) {
      final url = catalogEpisodeUrl((await detail).roads, episode);
      return url == null ? null : NativeCatalogApi.xifanEpisode(url)?.$2;
    }
    final number = episode;
    if (number == null || number != number.truncateToDouble()) return null;
    return (await remote.match(await _bangumiId(), number.toInt()))?.episodeId;
  }();

  Future<String?> _giriUrl() => _giriPage ??= () async {
    if (source == CatalogSource.giri) {
      return NativeCatalogApi.giriMedia(pageUrl)?.toString();
    }
    if (episode == null) return null;
    final detail = _detail(CatalogSource.giri);
    if (detail == null) return null;
    final url = catalogEpisodeUrl((await detail).roads, episode);
    return url == null ? null : NativeCatalogApi.giriMedia(url)?.toString();
  }();

  Future<DanmakuLoadResult> load({
    required CatalogDanmakuOptions options,
    int chConvert = 1,
    bool cache = false,
    bool refresh = false,
    Future<List<DanmakuEntry>?> Function()? loadCached,
    void Function(String source, Object error)? onSourceError,
  }) {
    final entries = ids.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final disk = CatalogDanmakuCache(
      '${source.name}:$pageUrl:$episode:$chConvert:${entries.map((e) => '${e.key}=${e.value}').join(',')}',
    );
    Future<List<DanmakuEntry>> channel(
      String name,
      Future<List<DanmakuEntry>> Function() fetch,
    ) => cache ? disk.readThrough(name, fetch, refresh: refresh) : fetch();
    return CatalogDanmakuLoader.loadCombined(
      options: options,
      onSourceError: onSourceError,
      loadCached: loadCached,
      timeout: const Duration(seconds: 40),
      loadExternal: () => channel('external', () async {
        final number = episode;
        if (number == null || number != number.truncateToDouble()) return [];
        return remote.external(
          await _bangumiId(),
          number.toInt(),
          chConvert: chConvert,
        );
      }),
      loadXifan: () => channel('xifan', () async {
        final id = await _xifan();
        return id == null ? [] : remote.siteEpisode(id);
      }),
      loadCycani: () => channel('cycani', () async {
        final id = await _section();
        return id == null
            ? []
            : CatalogDanmakuLoader.parse(await api.danmaku(id));
      }),
      loadGiri: () => channel('giri', () async {
        final url = await _giriUrl();
        return url == null ? [] : giri.internal(url);
      }),
      loadGiriExternal: () => channel('giriExternal', () async {
        final url = await _giriUrl();
        return url == null ? [] : giri.external(url);
      }),
    );
  }
}
