import 'catalog_danmaku_codec.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'catalog_models.dart';
import 'catalog_danmaku_options.dart';

/// Keeps the original provider when available; an unavailable provider must not
/// prevent loading the site's public section comments.
class CatalogDanmakuLoader {
  static const source = '[次元城]';

  static Future<DanmakuLoadResult> loadCombined({
    required CatalogDanmakuOptions options,
    required Future<List<DanmakuEntry>> Function() loadExternal,
    required Future<List<DanmakuEntry>> Function() loadXifan,
    required Future<List<DanmakuEntry>> Function() loadCycani,
    Future<List<DanmakuEntry>> Function()? loadGiri,
    Future<List<DanmakuEntry>> Function()? loadGiriExternal,
    Future<List<DanmakuEntry>?> Function()? loadCached,
    Duration timeout = const Duration(seconds: 20),
    void Function(String source, Object error)? onSourceError,
  }) async {
    final jobs = <Future<List<DanmakuEntry>> Function()>[
      if (options.external) loadExternal,
      if (options.xifan) loadXifan,
      if (options.cycani) loadCycani,
      if (options.giri && loadGiri != null) loadGiri,
      if (options.giriExternal && loadGiriExternal != null) loadGiriExternal,
    ];
    if (jobs.isEmpty)
      return DanmakuLoadResult.success(danmakus: [], bangumiID: 0);
    if (loadCached != null) {
      try {
        final cached = await loadCached();
        final cachedFiltered =
            cached?.where((e) => options.includes(e.source)).toList() ?? [];
        if (cachedFiltered.isNotEmpty) {
          return DanmakuLoadResult.success(
            danmakus: cachedFiltered,
            bangumiID: 0,
          );
        }
        // 缓存存在但按当前来源设置过滤后为空（如旧缓存不含新增来源），
        // 继续在线加载而不是返回空 success。
      } catch (_) {}
    }
    final names = [
      if (options.external) CatalogDanmakuOptions.externalSource,
      if (options.xifan) CatalogDanmakuOptions.xifanSource,
      if (options.cycani) CatalogDanmakuOptions.cycaniSource,
      if (options.giri && loadGiri != null) CatalogDanmakuOptions.giriSource,
      if (options.giriExternal && loadGiriExternal != null)
        CatalogDanmakuOptions.giriExternalSource,
    ];
    var successes = 0;
    final batches = await Future.wait(
      jobs.indexed.map((entry) async {
        final (index, job) = entry;
        try {
          final entries = await job().timeout(timeout);
          successes++;
          return entries;
        } catch (error) {
          try {
            onSourceError?.call(names[index], error);
          } catch (_) {
            // Diagnostic observers cannot cancel healthy providers.
          }
          return <DanmakuEntry>[];
        }
      }),
    );
    final entries =
        batches
            .expand((e) => e)
            .where(
              (e) =>
                  e.time.isFinite && e.time >= 0 && e.message.trim().isNotEmpty,
            )
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));
    return successes > 0
        ? DanmakuLoadResult.success(
            danmakus: entries,
            bangumiID: 0,
            allSourcesLoaded: successes == jobs.length,
          )
        : DanmakuLoadResult.failed(bangumiID: 0);
  }

  static Future<DanmakuLoadResult> load({
    Future<List<DanmakuEntry>?> Function()? loadCached,
    required bool originalAvailable,
    required bool mergeSiteDanmaku,
    required Future<DanmakuLoadResult> Function() loadOriginal,
    required Future<List<CatalogJson>> Function() loadSite,
  }) async {
    if (loadCached != null) {
      try {
        final cached = await loadCached();
        if (cached != null && cached.isNotEmpty) {
          return DanmakuLoadResult.success(danmakus: cached, bangumiID: 0);
        }
      } catch (_) {
        // A corrupt cache must not prevent retrying the current section online.
      }
    }
    var original = DanmakuLoadResult.failed(bangumiID: 0);
    if (originalAvailable) {
      try {
        original = await loadOriginal();
      } catch (_) {
        // The site is independent of the external provider's authentication.
      }
    }
    if (original.hasDanmakus && !mergeSiteDanmaku) return original;
    try {
      final site = parse(await loadSite());
      return DanmakuLoadResult.success(
        bangumiID: original.bangumiID,
        danmakus: [...original.danmakus, ...site],
      );
    } catch (_) {
      return original;
    }
  }

  static List<DanmakuEntry> parse(List<CatalogJson> items) {
    final result = <DanmakuEntry>[];
    for (final item in items) {
      final content = item['content'];
      final seconds = double.tryParse('${item['time_point']}');
      if (content is! String ||
          content.trim().isEmpty ||
          seconds == null ||
          !seconds.isFinite ||
          seconds < 0) {
        continue;
      }
      result.add(
        DanmakuEntry(
          message: content,
          time: seconds,
          type: CatalogDanmakuCodec.namedMode(item['mode']),
          color: CatalogDanmakuCodec.color(item['color']),
          source: source,
        ),
      );
    }
    return result;
  }
}
