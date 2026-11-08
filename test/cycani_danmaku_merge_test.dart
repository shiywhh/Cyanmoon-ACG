import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyanmoon_acg/features/cycani/cycani_api.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_danmaku_loader.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_danmaku_options.dart';
import 'package:cyanmoon_acg/features/cycani/cycani_remote_danmaku.dart';
import 'package:cyanmoon_acg/modules/danmaku/danmaku_module.dart';
import 'package:cyanmoon_acg/pages/player/controller/player_danmaku_controller.dart';
import 'cycani_api_test.dart' show FakeAdapter;

ResponseBody bare(Object? value) => ResponseBody.fromString(
  jsonEncode(value),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
DanmakuEntry entry(String source, double second) => DanmakuEntry(
  message: source,
  time: second,
  type: 1,
  color: const Color(0xFFFFFFFF),
  source: source,
);
Dio fake(Future<ResponseBody> Function(RequestOptions) handler) =>
    Dio()..httpClientAdapter = FakeAdapter(handler);
void main() {
  test(
    'all three providers start in parallel and merge by timestamp',
    () async {
      var started = 0;
      final gate = Completer<void>();
      Future<List<DanmakuEntry>> job(String source, double second) async {
        started++;
        if (started == 3) gate.complete();
        await gate.future;
        return [entry(source, second)];
      }

      final result = await CatalogDanmakuLoader.loadCombined(
        options: const CatalogDanmakuOptions(),
        loadExternal: () => job(CatalogDanmakuOptions.externalSource, 3),
        loadXifan: () => job(CatalogDanmakuOptions.xifanSource, 1),
        loadCycani: () => job(CatalogDanmakuOptions.cycaniSource, 2),
      );
      expect(started, 3);
      expect(result.allSourcesLoaded, isTrue);
      expect(result.hasDanmakus, true);
      expect(result.danmakus.map((e) => e.time), [1, 2, 3]);
      expect(result.danmakus.map((e) => e.source).toSet().length, 3);
    },
  );
  test('failed source does not discard two healthy sources', () async {
    final result = await CatalogDanmakuLoader.loadCombined(
      options: const CatalogDanmakuOptions(),
      loadExternal: () async => throw StateError('offline'),
      loadXifan: () async => [entry(CatalogDanmakuOptions.xifanSource, 1)],
      loadCycani: () async => [entry(CatalogDanmakuOptions.cycaniSource, 2)],
    );
    expect(result.danmakus.length, 2);
    expect(result.allSourcesLoaded, isFalse);
    expect(result.hasDanmakus, true);
  });
  test(
    'source timeout is isolated and late completion cannot replace results',
    () async {
      final slow = Completer<List<DanmakuEntry>>();
      final result = await CatalogDanmakuLoader.loadCombined(
        options: const CatalogDanmakuOptions(),
        timeout: const Duration(milliseconds: 15),
        loadExternal: () => slow.future,
        loadXifan: () async => [],
        loadCycani: () async => [entry(CatalogDanmakuOptions.cycaniSource, 2)],
      );
      slow.complete([entry(CatalogDanmakuOptions.externalSource, 3)]);
      await Future<void>.delayed(Duration.zero);
      expect(result.danmakus.single.source, CatalogDanmakuOptions.cycaniSource);
    },
  );
  test('disabled sources neither load nor appear from offline cache', () async {
    var calls = 0;
    final result = await CatalogDanmakuLoader.loadCombined(
      options: const CatalogDanmakuOptions(external: false, xifan: false),
      loadCached: () async => [
        entry(CatalogDanmakuOptions.externalSource, 1),
        entry(CatalogDanmakuOptions.cycaniSource, 2),
      ],
      loadExternal: () async {
        calls++;
        return [];
      },
      loadXifan: () async {
        calls++;
        return [];
      },
      loadCycani: () async {
        calls++;
        return [];
      },
    );
    expect(calls, 0);
    expect(result.danmakus.single.source, CatalogDanmakuOptions.cycaniSource);
  });
  test('all disabled is empty, never an error or network request', () async {
    Future<List<DanmakuEntry>> fail() async => throw StateError('must not run');
    final result = await CatalogDanmakuLoader.loadCombined(
      options: const CatalogDanmakuOptions(
        external: false,
        xifan: false,
        cycani: false,
      ),
      loadExternal: fail,
      loadXifan: fail,
      loadCycani: fail,
    );
    expect(result.status, DanmakuLoadStatus.empty);
  });
  test(
    'all failed is different from healthy providers returning no comments',
    () async {
      Future<List<DanmakuEntry>> fail() async => throw StateError('offline');
      final result = await CatalogDanmakuLoader.loadCombined(
        options: const CatalogDanmakuOptions(),
        loadExternal: fail,
        loadXifan: fail,
        loadCycani: fail,
      );
      expect(result.isFailed, true);
      final empty = await CatalogDanmakuLoader.loadCombined(
        options: const CatalogDanmakuOptions(),
        loadExternal: () async => [],
        loadXifan: fail,
        loadCycani: fail,
      );
      expect(empty.status, DanmakuLoadStatus.empty);
    },
  );
  test(
    'bad cache and malformed rows never suppress healthy comments',
    () async {
      final result = await CatalogDanmakuLoader.loadCombined(
        options: const CatalogDanmakuOptions(),
        loadCached: () async => throw StateError('corrupt'),
        loadExternal: () async => [
          entry(CatalogDanmakuOptions.externalSource, double.nan),
        ],
        loadXifan: () async => [entry(CatalogDanmakuOptions.xifanSource, -1)],
        loadCycani: () async => [entry(CatalogDanmakuOptions.cycaniSource, 2)],
      );
      expect(result.danmakus.length, 1);
    },
  );
  test(
    'exact shared mapping, actual episode ID, no user credentials on relay',
    () async {
      var catalogueReads = 0;
      var episodeReads = 0;
      var siteReads = 0;
      final x = fake((r) async {
        expect(r.headers.containsKey('Authorization'), false);
        expect(r.headers.containsKey('Cookie'), false);
        expect(r.headers['apikey'], startsWith('sb_publishable_'));
        if (r.path.endsWith('/animes')) {
          catalogueReads++;
          expect(r.queryParameters['bangumi_id'], 'eq.554779');
          return bare([
            {'id': 3432, 'bangumi_id': 554779},
          ]);
        }
        if (r.path.endsWith('/episodes')) {
          episodeReads++;
          expect(r.queryParameters['episode_number'], 'eq.5');
          expect(r.queryParameters['kind'], 'eq.main');
          return bare([
            {
              'id': 203779,
              'episode_number': 5.0,
              'dandan_episode_id': 193080005,
            },
          ]);
        }
        siteReads++;
        expect(r.data['p_episode_id'], 203779);
        return bare([
          {
            'id': 1,
            'v_time': 1.25,
            'content': 'site',
            'color': '#123456',
            'mode': 'top',
          },
        ]);
      });
      x.options.headers.addAll({
        'Authorization': 'private-user-token',
        'Cookie': 'private',
      });
      final relay = fake((r) async {
        expect(r.path, '/api/v2/comment/193080005');
        expect(r.queryParameters['chConvert'], '2');
        for (final k in r.headers.keys)
          expect(
            [
              'authorization',
              'cookie',
              'apikey',
              'x-appid',
              'x-appsecret',
              'x-signature',
            ].contains(k.toLowerCase()),
            false,
          );
        return bare({
          'count': 2,
          'comments': [
            {'m': 'external', 'p': '2.5,4,255,hash'},
            {'m': 'broken', 'p': 'NaN,1,255,x'},
          ],
        });
      });
      relay.options.headers.addAll({
        'Authorization': 'private-user-token',
        'apikey': 'not-for-relay',
      });
      final api = CycaniRemoteDanmaku(xifanDio: x, relayDio: relay);
      final result = await Future.wait([
        api.external(554779, 5, chConvert: 2),
        api.site(554779, 5),
      ]);
      expect([catalogueReads, episodeReads, siteReads], [1, 1, 1]);
      expect(result[0].single.source, CatalogDanmakuOptions.externalSource);
      expect(result[0].single.time, 2.5);
      expect(result[0].single.type, 4);
      expect(result[1].single.color, const Color(0xFF123456));
      expect(result[1].single.type, 5);
    },
  );
  test(
    'missing Xifan mapping uses real relay episode records, never concatenates IDs',
    () async {
      final remote = CycaniRemoteDanmaku(
        xifanDio: fake((_) async => bare([])),
        relayDio: fake((r) async {
          if (r.path.contains('/bgmtv/'))
            return bare({
              'success': true,
              'bangumi': {
                'episodes': [
                  {'episodeNumber': '5', 'episodeId': 91234},
                  {'episodeNumber': 'SP5', 'episodeId': 888},
                ],
              },
            });
          expect(r.path, '/api/v2/comment/91234');
          return bare({
            'comments': [
              {'m': 'fallback', 'p': '1,1,16777215,hash'},
            ],
          });
        }),
      );
      expect((await remote.external(554779, 5)).single.message, 'fallback');
      expect(await remote.site(554779, 5), isEmpty);
    },
  );
  test('wrong or ambiguous identities are not title-guessed', () async {
    final remote = CycaniRemoteDanmaku(
      xifanDio: fake(
        (r) async => bare([
          {'id': 3432, 'bangumi_id': 999},
        ]),
      ),
      relayDio: fake((_) async => throw StateError('must not run')),
    );
    expect(await remote.match(554779, 5), isNull);
    expect(await remote.match(0, 5), isNull);
    expect(await remote.match(554779, 0), isNull);
    final ambiguous = CycaniRemoteDanmaku(
      xifanDio: fake(
        (_) async => bare([
          {'id': 1, 'bangumi_id': 554779},
          {'id': 2, 'bangumi_id': 554779},
        ]),
      ),
      relayDio: fake((_) async => bare({})),
    );
    expect(await ambiguous.match(554779, 5), isNull);
  });
  test('failed matching can retry without a poisoned cached future', () async {
    var attempts = 0;
    final remote = CycaniRemoteDanmaku(
      xifanDio: fake((r) async {
        if (r.path.endsWith('/animes')) {
          if (attempts++ == 0) throw StateError('temporary');
          return bare([
            {'id': 3432, 'bangumi_id': 554779},
          ]);
        }
        return bare([
          {'id': 203779, 'episode_number': 5, 'dandan_episode_id': 193080005},
        ]);
      }),
      relayDio: fake((_) async => bare({})),
    );
    await expectLater(remote.match(554779, 5), throwsA(anything));
    expect((await remote.match(554779, 5))?.episodeId, 203779);
    expect(attempts, 2);
  });
  test(
    'site pagination exhausts ID cursors and deduplicates page overlaps',
    () async {
      final cursors = <int>[];
      final remote = CycaniRemoteDanmaku(
        xifanDio: fake((r) async {
          if (r.path.endsWith('/animes'))
            return bare([
              {'id': 3432, 'bangumi_id': 554779},
            ]);
          if (r.path.endsWith('/episodes'))
            return bare([
              {'id': 203779, 'episode_number': 5},
            ]);
          final after = r.data['p_after_id'] as int;
          cursors.add(after);
          Map<String, dynamic> row(int n) => {
            'id': n,
            'v_time': n / 10,
            'content': '$n',
            'color': '#ffffff',
            'mode': 'scroll',
          };
          return bare(
            after == 0
                ? [for (var i = 1; i <= 500; i++) row(i)]
                : [row(500), row(501)],
          );
        }),
        relayDio: fake((_) async => bare({})),
      );
      expect((await remote.site(554779, 5)).length, 501);
      expect(cursors, [0, 500]);
    },
  );
  test('real three-way native loading for one matched episode', () async {
    final api = CycaniApi();
    final remote = CycaniRemoteDanmaku();
    final video = await api.detail(3943);
    expect(video.bangumiId, 554779);
    final groups = await api.episodes(video.id, video: video);
    final section = groups.first.items.firstWhere(
      (e) => '${e['title']}'.contains('5'),
    );
    final counts = <String, int>{};
    Future<List<DanmakuEntry>> keep(
      String name,
      Future<List<DanmakuEntry>> call,
    ) async {
      final rows = await call;
      counts[name] = rows.length;
      return rows;
    }

    final result = await CatalogDanmakuLoader.loadCombined(
      options: const CatalogDanmakuOptions(),
      loadExternal: () => keep('external', remote.external(video.bangumiId, 5)),
      loadXifan: () => keep('xifan', remote.site(video.bangumiId, 5)),
      loadCycani: () => keep(
        'cycani',
        api
            .danmaku(int.parse('${section['id']}'))
            .then(CatalogDanmakuLoader.parse),
      ),
    );
    expect(counts.keys.toSet(), {'external', 'xifan', 'cycani'});
    expect(counts.values.every((n) => n > 0), true);
    expect(result.danmakus.length, counts.values.reduce((a, b) => a + b));
    expect(result.danmakus.map((e) => e.source).toSet().length, 3);
    print(
      'Verified live three-source counts: $counts; merged ${result.danmakus.length}',
    );
    api.dispose();
  }, skip: Platform.environment['CYCANI_MERGE_LIVE'] != '1');
}
