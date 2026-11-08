import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/cycani_api.dart';
import 'package:kazumi/features/cycani/catalog_aggregator.dart';
import 'package:kazumi/features/cycani/giri_danmaku.dart';
import 'package:kazumi/features/cycani/catalog_models.dart';
import 'package:kazumi/features/cycani/site_native_catalog.dart';
import 'package:kazumi/features/cycani/cycani_remote_danmaku.dart';
import 'package:kazumi/features/cycani/site_accounts.dart';

/// Read-only probe of every public API chain the app uses, one request each,
/// with per-request latency. Authenticated writes are never exercised;
/// "应被拒" chains expect an anonymous request to be rejected by the server.
/// Run: CYCANI_CHAIN_PROBE=1 flutter test test/cycani_api_chain_probe_test.dart
void main() {
  final enabled = Platform.environment['CYCANI_CHAIN_PROBE'] == '1';
  final skip = enabled ? false : 'Set CYCANI_CHAIN_PROBE=1 to probe live APIs.';
  // Keep real networking: the test binding swaps HttpOverrides for its own.
  final realHttp = HttpOverrides.current;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = realHttp;
  FlutterSecureStorage.setMockInitialValues({});

  final rows = <List<Object>>[]; // [host, chain, ms, status, detail]
  final swTotal = Stopwatch()..start();

  Future<T?> timed<T>(
    String host,
    String chain,
    Future<T> Function() job,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final value = await job();
      sw.stop();
      rows.add([host, chain, sw.elapsedMilliseconds, 'OK', '']);
      return value;
    } catch (error) {
      sw.stop();
      rows.add([host, chain, sw.elapsedMilliseconds, 'FAIL', '$error']);
      return null;
    }
  }

  /// Probe a chain that must be rejected anonymously; a CycaniException or
  /// HTTP-level rejection counts as the expected outcome, not a failure.
  Future<void> timedReject(
    String host,
    String chain,
    Future<Object?> Function() job,
  ) async {
    await timed<String>(host, chain, () async {
      try {
        await job();
      } catch (error) {
        return 'rejected: $error';
      }
      throw StateError('匿名请求未被拒绝');
    });
  }

  Dio client(String origin, Map<String, String> headers) {
    final dio = Dio(
      BaseOptions(
        baseUrl: origin,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0',
          ...headers,
        },
        followRedirects: false,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (s) => s != null && s < 600,
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient()..findProxy = (_) => 'DIRECT',
    );
    return dio;
  }

  final giriDio = client('https://m3u8.girigirilove.com', {
    'Origin': 'https://ani.girigirilove.com',
    'Referer': 'https://ani.girigirilove.com/home',
  });
  final xifanWeb = client('https://next.xifanacg.com', {});
  final cycani = CycaniApi.instance;
  final catalog = CatalogAggregator.instance;
  final native = NativeCatalogApi.instance;
  final remote = CycaniRemoteDanmaku.instance;
  final accounts = SourceAccounts.instance;

  test('all public API chains respond', () async {
    // ── 次元城站 ──────────────────────────────────────────────
    final recommend = await timed('次元城', 'GET /index/recommend', () async {
      final groups = await cycani.recommendations();
      for (final group in groups) {
        final first = catalogList(group['videos']).firstOrNull;
        if (first != null && CatalogVideo(first).id > 0) return first;
      }
      return null;
    });
    final entry = recommend is Map ? catalogMap(recommend) : null;
    final entryId = entry == null ? 0 : CatalogVideo(entry).id;
    final entryTitle = entry == null ? '' : CatalogVideo(entry).title;

    await timed('次元城', 'GET /app/adverts?position=banner',
        () => cycani.request('/app/adverts', query: {'position': 'banner'}));
    await timed('次元城', 'GET /video-zones', () => cycani.zones());
    await timed('次元城', 'GET /videos?page=1', () => cycani.videos());
    await timed('次元城', 'GET /videos/search?q=…',
        () => cycani.videos(keyword: entryTitle.isEmpty ? '少女' : entryTitle));
    final episodesData = entryId > 0
        ? await timed('次元城', 'GET /videos/{id} + /sections（详情链）',
            () => cycani.episodes(entryId))
        : null;
    if (entryId > 0) {
      await timed('次元城', 'GET /videos/{id}/recommendations',
          () => cycani.request('/videos/$entryId/recommendations', query: {'limit': 12}));
      final comments = await timed('次元城', 'GET /videos/{id}/comments',
          () => cycani.comments(entryId));
      final firstComment = catalogList(comments ?? {}).firstOrNull;
      if (firstComment != null && catalogInt(firstComment['reply_count']) > 0) {
        await timed('次元城', 'GET /comments/{id}/replies',
            () => cycani.replies(catalogInt(firstComment['id'])));
      }
      final sectionId = cycaniSectionId(
        (episodesData ?? const []).firstOrNull?.toRoad().data.firstOrNull ?? '',
      );
      if (sectionId != null) {
        await timed('次元城', 'GET /sections/{id}/danmaku',
            () => cycani.danmaku(sectionId));
        await timedReject('次元城', '播放链 GET /v2/sections/{id}/play-url（匿名应被拒）',
            () => cycani.request('/v2/sections/$sectionId/play-url'));
      }
    }
    final ranks = await timed('次元城', 'GET /ranks', () => cycani.ranks());
    final rankId = catalogInt(catalogList(ranks ?? {}).firstOrNull?['id']);
    if (rankId > 0) {
      await timed('次元城', 'GET /ranks/{id}/videos', () => cycani.rankVideos(rankId));
    }
    await timed('次元城', 'GET /index/weekday',
        () => cycani.schedule(DateTime.now().weekday));
    await timedReject('次元城', '账户链 GET /user/me（匿名应被拒）', () => cycani.request('/user/me'));

    // ── 稀饭 ──────────────────────────────────────────────────
    final browse = await timed('稀饭', 'GET /rest/v1/animes（分类）',
        () => catalog.browse(CatalogSource.xifan, 1, order: 'update_time'));
    final xifanId = CatalogVideo(catalogList(browse?.items ?? const []).firstOrNull ?? {}).id;
    NativeCatalogDetail? xifanDetail;
    if (xifanId > 0) {
      xifanDetail = await timed('稀饭', 'GET /rest/v1/animes?id= + /episodes（详情链）',
          () => native.detail(CatalogSource.xifan, xifanId));
    }
    await timed('稀饭', 'GET /rest/v1/animes（搜索 ilike）',
        () => catalog.searchSource(CatalogSource.xifan, '少女', 1));
    final bgmId = xifanDetail?.video.bangumiId ?? 0;
    final episodeOne = int.tryParse(
          (xifanDetail?.roads.firstOrNull?.identifier.firstOrNull ?? '')
              .replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        1;
    final matched = bgmId > 0
        ? await timed('稀饭', '弹幕匹配 GET /rest/v1/animes+episodes（bangumi_id 精确）',
            () => remote.match(bgmId, episodeOne))
        : null;
    if (matched != null) {
      await timed('稀饭', 'POST /rest/v1/rpc/get_danmaku_page',
          () => remote.siteEpisode(matched.episodeId));
    }
    await timed('稀饭', 'POST /rest/v1/rpc/get_comments（匿名）',
        () => accounts.readComments(false, xifanId > 0 ? xifanId : 1));
    if (xifanId > 0 && matched != null) {
      await timed('稀饭', 'POST /functions/v1/issue-web-playback',
          () => native.xifanPlayback(xifanId, matched.episodeId));
    }
    final homeDoc = await timed('稀饭', 'GET next.xifanacg.com/（HTML）',
        () => xifanWeb.get<String>('/', options: Options(responseType: ResponseType.plain)));
    await timed('稀饭', 'GET next.xifanacg.com/rankings（HTML）',
        () => xifanWeb.get<String>('/rankings', options: Options(responseType: ResponseType.plain)));
    final seriesRow = CatalogAggregator.xifanHomeSections(homeDoc?.data ?? '')
        .expand((g) => catalogList(g['videos']))
        .firstWhere((r) => r['xifan_series'] != null, orElse: () => const {});
    final seriesId = catalogInt(seriesRow['xifan_series']);
    if (seriesId > 0) {
      await timed('稀饭', 'GET next.xifanacg.com/series/{id}（HTML）',
          () => xifanWeb.get<String>('/series/$seriesId',
              options: Options(responseType: ResponseType.plain)));
    }

    // ── GiriGiri ─────────────────────────────────────────────
    final giriList = await timed('GiriGiri', 'GET /api.php/Vod/get_list（分类）',
        () => catalog.browse(CatalogSource.giri, 1, kind: 'tv'));
    final giriId = CatalogVideo(catalogList(giriList?.items ?? const []).firstOrNull ?? {}).id;
    if (giriId > 0) {
      final giriDetail = await timed('GiriGiri', 'GET /api.php/Vod/get_detail',
          () => native.detail(CatalogSource.giri, giriId));
      await timed('GiriGiri', 'GET /api.php/Comment/get_list',
          () => accounts.readComments(true, giriId));
      final playUrl = giriDetail?.roads.firstOrNull?.data.firstOrNull;
      if (playUrl != null) {
        await timed('GiriGiri', 'POST /api.php/Scrolling/getScrolling（站内弹幕）',
            () => GiriDanmakuApi.instance.internal(playUrl));
        await timed('GiriGiri', 'POST getVodOutScrolling + 外部 XML（含 CNAME 回退）',
            () => GiriDanmakuApi.instance.external(playUrl));
      }
    }
    await timed('GiriGiri', 'GET bannerList/appConfigData/famousList/likeList（主页聚合）',
        () => catalog.recommendations(CatalogSource.giri));
    await timed('GiriGiri', 'GET /api.php/App2/weekList',
        () => catalog.schedule(CatalogSource.giri, DateTime.now().weekday));
    final groups = await timed('GiriGiri', 'GET /api.php/App2/vodSortList',
        () => catalog.giriRankingGroups());
    final sortId = catalogInt(catalogList(groups ?? {}).firstOrNull?['id']);
    if (sortId > 0) {
      await timed('GiriGiri', 'GET /api.php/App2/vodSortSearch',
          () => catalog.giriRankingPage(sortId, 1));
    }
    await timed('GiriGiri', 'GET /api.php/Vod/get_year|area|class|getAllTagOption',
        () => catalog.giriBrowseFilters());
    await timed('GiriGiri', 'GET /index.php/sso/status（匿名）',
        () => giriDio.get<dynamic>('/index.php/sso/status'));
    await timed('GiriGiri', '登录链 GET /index.php/verify/index.html（取码图）',
        () => giriDio.get<List<int>>('/index.php/verify/index.html',
            queryParameters: {
              'id': 137,
              '_t': DateTime.now().millisecondsSinceEpoch,
            },
            options: Options(responseType: ResponseType.bytes)));

    // ── 外部弹幕中继 ──────────────────────────────────────────
    if (bgmId > 0) {
      await timed('外部弹幕', 'GET /api/v2/bangumi/bgmtv/{id} + /comment/{id}',
          () => remote.external(bgmId, episodeOne));
    }

    swTotal.stop();

    // ── 报告 ──────────────────────────────────────────────────
    final byHost = <String, List<int>>{};
    var failures = 0;
    for (final row in rows) {
      final host = '${row[0]}', ms = row[2] as int, ok = row[3] == 'OK';
      if (!ok) failures++;
      byHost.putIfAbsent(host, () => []).add(ms);
    }
    final buffer = StringBuffer('\n════ API 链路探测结果 ════\n');
    for (final row in rows) {
      final flag = row[3] == 'OK' ? ' ' : '!';
      buffer
        ..write('$flag ${'${row[2]}ms'.padLeft(7)}  [${row[0]}] ${row[1]}')
        ..write(row[3] == 'OK' ? '' : '  ← ${row[4]}')
        ..writeln();
    }
    buffer.writeln('---- 按主机 ----');
    for (final entry in byHost.entries) {
      final times = entry.value;
      buffer.writeln(
        '${entry.key.padRight(8)} ${times.length.toString().padLeft(2)} 条  '
        '合计 ${times.reduce((a, b) => a + b)}ms  '
        '最慢 ${times.reduce((a, b) => a > b ? a : b)}ms',
      );
    }
    buffer.writeln(
      '总请求 ${rows.length}，失败 $failures，总耗时 ${swTotal.elapsedMilliseconds}ms',
    );
    // ignore: avoid_print
    print(buffer);

    expect(rows, isNotEmpty, reason: '没有发出任何请求');
    for (final host in ['次元城', '稀饭', 'GiriGiri']) {
      final hostRows = rows.where((r) => r[0] == host).toList();
      expect(
        hostRows.any((r) => r[3] == 'OK'),
        isTrue,
        reason: '$host 没有任何成功链路',
      );
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 8)));
}
