import 'package:dio/dio.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/cycani_api.dart';
import 'package:kazumi/features/cycani/catalog_models.dart';
import 'package:kazumi/features/cycani/catalog_aggregator.dart';
import 'package:kazumi/features/cycani/site_native_catalog.dart';
import 'package:kazumi/features/cycani/cycani_remote_danmaku.dart';
import 'package:kazumi/features/cycani/giri_danmaku.dart';
import 'package:kazumi/features/cycani/catalog_danmaku_options.dart';
import 'package:kazumi/features/cycani/catalog_playback_danmaku.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'cycani_api_test.dart' show MemoryVault;

DanmakuEntry row(String source, double time) => DanmakuEntry(
  message: source,
  time: time,
  type: 1,
  color: const Color(0xFFFFFFFF),
  source: source,
);

class _Cycani extends CycaniApi {
  _Cycani() : super(vault: MemoryVault());
  final requested = <int>[];
  @override
  Future<CatalogVideo> detail(int id) async =>
      CatalogVideo({'id': id, 'bangumi_id': 777});
  @override
  Future<List<CatalogEpisodes>> episodes(int id, {CatalogVideo? video}) async => [
    const CatalogEpisodes(
      name: 'road',
      code: 'main',
      items: [
        {'id': 12, 'title': '第02集'},
        {'id': 11, 'title': '第01集'},
      ],
    ),
  ];
  @override
  Future<List<CatalogJson>> danmaku(int id) async {
    requested.add(id);
    return [
      {'content': 'cycani', 'time_point': 3},
    ];
  }
}

class _Native extends NativeCatalogApi {
  final requested = <CatalogSource>[];
  @override
  Future<NativeCatalogDetail> detail(
    CatalogSource source,
    int id, {
    bool refresh = false,
  }) async {
    requested.add(source);
    return NativeCatalogDetail(
      const CatalogVideo({'id': 2, 'bangumi_id': 777}),
      [
        Road(
          name: 'road',
          data: source == CatalogSource.giri
              ? [
                  'https://g.girigirilove.com/e2.m3u8',
                  'https://g.girigirilove.com/e1.m3u8',
                ]
              : [
                  'https://next.xifanacg.com/anime/20/play/202',
                  'https://next.xifanacg.com/anime/20/play/201',
                ],
          identifier: ['第02集', '第01集'],
        ),
      ],
    );
  }
}

class _Remote extends CycaniRemoteDanmaku {
  final episodes = <int>[], externalEpisodes = <int>[];
  @override
  Future<List<DanmakuEntry>> siteEpisode(int id) async {
    episodes.add(id);
    return [row(CatalogDanmakuOptions.xifanSource, 2)];
  }

  @override
  Future<List<DanmakuEntry>> external(
    int id,
    int ep, {
    int chConvert = 1,
  }) async {
    expect(id, 777);
    externalEpisodes.add(ep);
    return [row(CatalogDanmakuOptions.externalSource, 1)];
  }
}

class _Giri extends GiriDanmakuApi {
  final requested = <String>[];
  bool fail = false;
  @override
  Future<List<DanmakuEntry>> internal(String url) async {
    requested.add(url);
    if (fail) throw StateError('offline');
    return [row(CatalogDanmakuOptions.giriSource, 4)];
  }

  @override
  Future<List<DanmakuEntry>> external(String url) async {
    requested.add(url);
    return [row(CatalogDanmakuOptions.giriExternalSource, 5)];
  }
}

void main() {
  test('matched identities carry only unique provider IDs', () {
    expect(
      catalogDanmakuIds([
        {'id': 10, 'catalog_source': 'cycani'},
        {'id': 20, 'catalog_source': 'xifan'},
        {'id': 21, 'catalog_source': 'xifan'},
        {'id': 30, 'catalog_source': 'giri'},
      ]),
      {'cycani': 10, 'giri': 30},
    );
  });

  test(
    'episode matching rejects list offsets, seasons, specials and fractional rounding',
    () {
      for (final label in ['第2季', 'SP01', '总集篇', '2026 第1集', 'episode x']) {
        expect(catalogEpisodeNumber(label), isNull);
      }
      expect(catalogEpisodeNumber('第01.5集'), 1.5);
      expect(catalogEpisodeNumber('EP02'), 2);
      expect(
        catalogEpisodeUrl([
          Road(name: 'a', data: ['two', 'one'], identifier: ['第02集', '第01集']),
        ], 1),
        'one',
      );
    },
  );

  // Bangumi 条目不是播放目标（播放经合并后的站点成员解析），不参与该组用例。
  for (final source in const [
    CatalogSource.cycani,
    CatalogSource.xifan,
    CatalogSource.giri,
  ]) {
    test(
      'five-way merge from ${source.name} uses exact linked episode and stable IDs',
      () async {
        final api = _Cycani(),
            native = _Native(),
            remote = _Remote(),
            giri = _Giri();
        final current = switch (source) {
          CatalogSource.cycani => 'https://www.cycani.org/section/12',
          CatalogSource.xifan => 'https://next.xifanacg.com/anime/20/play/202',
          CatalogSource.giri => 'https://g.girigirilove.com/e2.m3u8',
          CatalogSource.bangumi => '',
        };
        final result = await CatalogPlaybackDanmaku(
          source: source,
          pageUrl: current,
          episodeTitle: '第02集',
          videoIds: {'cycani': 10, 'xifan': 20, 'giri': 30},
          bangumiId: 777,
          cycani: api,
          native: native,
          remote: remote,
          giri: giri,
        ).load(options: const CatalogDanmakuOptions());
        expect(result.allSourcesLoaded, isTrue);
        expect(result.danmakus.map((r) => r.time), [1, 2, 3, 4, 5]);
        expect(api.requested, [12]);
        expect(remote.episodes, [202]);
        expect(remote.externalEpisodes, [2]);
        expect(giri.requested, [
          'https://g.girigirilove.com/e2.m3u8',
          'https://g.girigirilove.com/e2.m3u8',
        ]);
        expect(
          native.requested.where((s) => s == CatalogSource.giri).length,
          source == CatalogSource.giri ? 0 : 1,
        );
        api.dispose();
      },
    );
  }

  test(
    'an unnumbered episode loads only its own exact section, never other list offsets',
    () async {
      final api = _Cycani(),
          native = _Native(),
          remote = _Remote(),
          giri = _Giri();
      final result = await CatalogPlaybackDanmaku(
        source: CatalogSource.cycani,
        pageUrl: 'https://www.cycani.org/section/99',
        episodeTitle: 'SP01',
        videoIds: {'cycani': 10, 'xifan': 20, 'giri': 30},
        cycani: api,
        native: native,
        remote: remote,
        giri: giri,
      ).load(options: const CatalogDanmakuOptions());
      expect(result.danmakus.single.source, CatalogDanmakuOptions.cycaniSource);
      expect(remote.episodes, isEmpty);
      expect(remote.externalEpisodes, isEmpty);
      expect(giri.requested, isEmpty);
      api.dispose();
    },
  );

  test(
    'live matched detail group combines all five real source readers',
    () async {
      final sources = CatalogAggregator.instance;
      final found = await sources.search('学生会也有洞', 1);
      final group = mergeCatalogRows(found.items).firstWhere(
        (r) => catalogList(
          r['catalog_members'],
        ).any((m) => catalogRowKey(m) == 'cycani:3943'),
      );
      final members = catalogList(group['catalog_members']);
      final ids = catalogDanmakuIds(members);
      expect(ids.keys.toSet(), {'cycani', 'xifan', 'giri'});
      final api = CycaniApi();
      final video = await api.detail(ids['cycani']!);
      final roads = await api.episodes(video.id, video: video);
      final section = roads.first.items.firstWhere(
        (r) => catalogEpisodeNumber('${r['title']}') == 1,
      );
      final result =
          await CatalogPlaybackDanmaku(
            source: CatalogSource.cycani,
            pageUrl: 'https://www.cycani.org/section/${section['id']}',
            episodeTitle: '${section['title']}',
            videoIds: ids,
            bangumiId: video.bangumiId,
            cycani: api,
          ).load(
            options: const CatalogDanmakuOptions(),
            onSourceError: (source, error) {
              final endpoint = error is DioException
                  ? '${error.requestOptions.uri.host}${error.requestOptions.uri.path}'
                  : error.runtimeType.toString();
              print('Failed provider $source at $endpoint: $error');
            },
          );
      print(
        'Loaded source tags: ${result.danmakus.map((r) => r.source).toSet()}',
      );
      expect(result.allSourcesLoaded, isTrue);
      final counts = <String, int>{};
      for (final item in result.danmakus) {
        counts.update(item.source, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(
        counts.keys,
        containsAll([
          CatalogDanmakuOptions.cycaniSource,
          CatalogDanmakuOptions.xifanSource,
          CatalogDanmakuOptions.externalSource,
          CatalogDanmakuOptions.giriExternalSource,
        ]),
      );
      print('Real linked source counts: $counts');
      api.dispose();
    },
    skip: Platform.environment['CATALOG_FIVE_DANMAKU_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
