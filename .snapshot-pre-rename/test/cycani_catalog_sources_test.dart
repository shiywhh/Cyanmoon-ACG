import 'package:kazumi/features/cycani/cycani_paging.dart';
import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'cycani_api_test.dart' show FakeAdapter;
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/cycani_catalog_sources.dart';
import 'package:kazumi/features/cycani/cycani_models.dart';

CycaniJson row(
  CatalogSource source,
  int id,
  String title,
  int year, {
  int bgm = 0,
}) => {
  'catalog_source': source.name,
  'video_id': id,
  'title': title,
  'year': year,
  'bangumi_id': bgm,
};

class _ScheduleFixture extends CycaniCatalogSources {
  var failXifan = false;
  var emptyXifan = false;

  @override
  Future<List<CycaniJson>> schedule(CatalogSource source, int day) async {
    if (source == CatalogSource.xifan && failXifan) throw StateError('offline');
    return [
      {
        'videos': [
          if (!(source == CatalogSource.xifan && emptyXifan))
            {'id': source.index + 1, 'title': '${source.name}-$day'},
        ],
      },
    ];
  }
}

class _SearchFixture extends CycaniCatalogSources {
  var failXifan = false;

  @override
  Future<CycaniPage> searchSource(
    CatalogSource source,
    String keyword,
    int page,
  ) async {
    if (source == CatalogSource.xifan && failXifan) throw StateError('offline');
    return CycaniPage([
      row(source, source.index + 1, '${source.name}-$keyword-$page', 2026),
    ], hasMore: page == 1);
  }
}

void main() {
  test(
    'Giri home keeps working when recommendation and banner fail together',
    () async {
      final adapter = FakeAdapter((request) async {
        final Object payload = switch (request.path) {
          '/Vod/get_list' => {
            'code': 1,
            'info': {
              'rows': [
                {
                  'vod_id': request.queryParameters['type_id'],
                  'vod_name': 'Fixture',
                },
              ],
            },
          },
          _ => {'code': 0},
        };
        return ResponseBody.fromString(
          jsonEncode(payload),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      final api = CycaniCatalogSources(
        giri: Dio()..httpClientAdapter = adapter,
      );
      final groups = await api.recommendations(CatalogSource.giri);
      final byName = {for (final group in groups) group['name']: group};
      expect(byName['精选番剧']?['layout'], 'hero');
      final shortcuts = groups.firstWhere((g) => g['layout'] == 'categories');
      expect(cycaniList(shortcuts['categories']).map((r) => r['id']), [
        '2',
        '3',
        '21',
        '20',
        '24',
        '26',
      ]);
      expect(CycaniVideo(cycaniList(byName['精选番剧']?['videos']).single).id, 2);
      expect(CycaniVideo(cycaniList(byName['剧场版']?['videos']).single).id, 21);
      expect(cycaniList(byName['为你推荐']?['videos']), isEmpty);
      expect(
        adapter.requests.where(
          (r) => r.path == '/Vod/get_list' && r.queryParameters['type_id'] == 2,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'search restores only the failed provider first page for the same query',
    () async {
      final api = _SearchFixture();
      Future<Set<CatalogSource>> sources(String query, int page) async =>
          (await api.search(query, page)).items.map(catalogSource).toSet();
      expect(await sources('alpha', 1), CatalogSource.values.toSet());
      api.failXifan = true;
      expect(await sources('alpha', 1), CatalogSource.values.toSet());
      expect(await sources('beta', 1), {
        CatalogSource.cycani,
        CatalogSource.giri,
      });
      expect(await sources('alpha', 2), {
        CatalogSource.cycani,
        CatalogSource.giri,
      });
    },
  );

  test(
    'weekly union retains only the failed source snapshot for the same day',
    () async {
      final api = _ScheduleFixture();
      Future<Set<String>> titles(int day) async => cycaniList(
        (await api.mergedSchedule(day)).single['videos'],
      ).map((r) => CycaniVideo(r).title).toSet();
      expect(await titles(1), {'cycani-1', 'xifan-1', 'giri-1'});
      api.failXifan = true;
      expect(await titles(1), {'cycani-1', 'xifan-1', 'giri-1'});
      expect(await titles(2), {'cycani-2', 'giri-2'});
      api.failXifan = false;
      api.emptyXifan = true;
      expect(await titles(1), {'cycani-1', 'giri-1'});
      api.failXifan = true;
      expect(await titles(1), {'cycani-1', 'giri-1'});
    },
  );

  test('three sites merge one work without conflating source-local IDs', () {
    final result = mergeCatalogRows([
      row(CatalogSource.cycani, 1, '学生会也有洞！', 2026),
      row(CatalogSource.xifan, 1, '学生会也有洞!', 2026, bgm: 554779),
      row(CatalogSource.giri, 1, '学生会也有洞', 2026),
    ]);
    expect(result, hasLength(1));
    expect(cycaniList(result.single['catalog_members']), hasLength(3));
  });
  test('conflicting authoritative IDs and distinct seasons stay separate', () {
    final result = mergeCatalogRows([
      row(CatalogSource.cycani, 1, 'A', 2026, bgm: 1),
      row(CatalogSource.xifan, 1, 'A', 2026, bgm: 2),
      row(CatalogSource.giri, 1, 'A', 2026),
      row(CatalogSource.xifan, 2, 'A 第二季', 2026),
    ]);
    expect(result, hasLength(4));
  });
  test('same title in different years or without a year is not merged', () {
    expect(
      mergeCatalogRows([
        row(CatalogSource.cycani, 1, 'A', 2024),
        row(CatalogSource.xifan, 1, 'A', 2025),
        row(CatalogSource.giri, 1, 'A', 0),
      ]),
      hasLength(3),
    );
  });
  test('official aliases join translations in the same year and format', () {
    final a = {
      ...row(CatalogSource.xifan, 1, '译名甲', 2026, bgm: 100),
      'title_original': 'Original',
      'aliases': ['译名乙'],
      'version': 'TV',
    };
    final b = {
      ...row(CatalogSource.giri, 1, '译名乙', 2026),
      'subtitle': 'Original',
      'version': '电视动画',
    };
    expect(
      cycaniList(mergeCatalogRows([a, b]).single['catalog_members']),
      hasLength(2),
    );
    expect(
      mergeCatalogRows([
        a,
        {...b, 'version': '剧场版'},
      ]),
      hasLength(2),
    );
    expect(
      mergeCatalogRows([
        {...a, 'season_number': 1},
        {...b, 'season_number': 2},
      ]),
      hasLength(2),
    );
  });

  test('an alias bridge cannot collapse two authoritative works', () {
    final a = row(CatalogSource.cycani, 1, 'Title A', 2026, bgm: 10);
    final b = row(CatalogSource.xifan, 2, 'Title B', 2026, bgm: 20);
    final bridge = {
      ...row(CatalogSource.giri, 3, 'Title A', 2026),
      'aliases': ['Title B'],
    };
    expect(mergeCatalogRows([a, bridge, b]), hasLength(3));
  });

  test('live three-source recommendation and merged search', () async {
    final api = CycaniCatalogSources.instance;
    final result = await api.search('学生会也有洞', 1);
    expect(
      result.items.map(catalogSource).toSet(),
      CatalogSource.values.toSet(),
    );
    expect(
      mergeCatalogRows(result.items).any(
        (e) =>
            cycaniList(
              e['catalog_members'],
            ).map(catalogSource).toSet().length ==
            3,
      ),
      true,
    );
    final week = await api.mergedSchedule(5);
    expect(
      cycaniList(week.single['videos']).map(catalogSource).toSet(),
      containsAll(CatalogSource.values),
    );
    final cycaniHome = await api.recommendations(CatalogSource.cycani);
    expect(
      cycaniHome.any(
        (g) => g['layout'] == 'hero' && cycaniList(g['videos']).isNotEmpty,
      ),
      isTrue,
    );
    final rec = await Future.wait(
      CatalogSource.values.map(api.recommendations),
    );
    expect(
      rec.every(
        (groups) => groups.any((e) => cycaniList(e['videos']).isNotEmpty),
      ),
      true,
    );
    print(
      'Live three-source merged search and each recommendation feed passed',
    );
  }, skip: Platform.environment['CYCANI_CATALOG_LIVE'] != '1');
  test(
    'live Xifan home contains official sections and a usable series',
    () async {
      final api = CycaniCatalogSources.instance;
      final xifan = await api.recommendations(CatalogSource.xifan);
      expect(
        xifan.map((group) => group['name']),
        containsAll(['追番周表', '刚上架の旧番', '高分合集']),
      );
      final series = cycaniList(
        xifan.firstWhere((g) => g['name'] == '高分合集')['videos'],
      );
      expect(series, isNotEmpty);
      expect(
        (await api.xifanSeries(cycaniInt(series.first['xifan_series']))),
        isNotEmpty,
      );
    },
    skip: Platform.environment['XIFAN_HOME_LIVE'] != '1',
  );

  for (final source in [CatalogSource.xifan, CatalogSource.giri]) {
    test('live ${source.name} browse, ranks and week stay in source', () async {
      final api = CycaniCatalogSources.instance;
      final groups = await Future.wait([
        api.browse(source, 1, kind: 'movie').then((page) => page.items),
        api.ranking(source, movie: true),
        api.ranking(source, movie: false),
        api
            .schedule(source, 5)
            .then(
              (groups) => groups
                  .expand((group) => cycaniList(group['videos']))
                  .toList(),
            ),
      ]);
      for (final rows in groups) {
        expect(rows, isNotEmpty);
        expect(rows.map(catalogSource).toSet(), {source});
        expect(rows.every((row) => CycaniVideo(row).id > 0), isTrue);
      }
    }, skip: Platform.environment['CYCANI_PARITY_LIVE'] != '1');
  }
}
