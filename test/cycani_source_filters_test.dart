import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/catalog_aggregator.dart';
import 'cycani_api_test.dart' show FakeAdapter;

void main() {
  for (final source in [CatalogSource.xifan, CatalogSource.giri]) {
    test(
      '${source.name} catalogue retries a transient connection without changing filters',
      () async {
        var calls = 0;
        final adapter = FakeAdapter((request) async {
          calls++;
          if (calls == 1)
            throw DioException(
              requestOptions: request,
              type: DioExceptionType.connectionTimeout,
            );
          expect(
            request.queryParameters[source == CatalogSource.xifan
                ? 'format'
                : 'type_id'],
            source == CatalogSource.xifan ? 'eq.movie' : 21,
          );
          final data = source == CatalogSource.xifan
              ? <Object>[]
              : {
                  'code': 1,
                  'info': {'rows': [], 'total': 0},
                };
          return ResponseBody.fromString(
            jsonEncode(data),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });
        final dio = Dio()..httpClientAdapter = adapter;
        await CatalogAggregator(
          xifan: dio,
          giri: dio,
        ).browse(source, 1, kind: 'movie');
        expect(calls, 2);
      },
    );
  }

  test(
    'external classification forwards each site format without converting to TV',
    () async {
      ResponseBody json(Object value) => ResponseBody.fromString(
        jsonEncode(value),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
      final x = FakeAdapter((r) async {
        expect(r.queryParameters['format'], 'eq.ova');
        expect(r.queryParameters['release_year'], 'lt.2007');
        expect(r.queryParameters['is_finished'], 'eq.true');
        expect(r.queryParameters['meta_tags'], 'cs.{"校园"}');
        expect(r.queryParameters['offset'], 36);
        return json([]);
      });
      final g = FakeAdapter((r) async {
        expect(r.queryParameters['type_id'], 3);
        expect(r.queryParameters['vod_area'], '一月');
        expect(r.queryParameters['vod_class'], '喜剧');
        expect(r.queryParameters['vod_state'], '漫画改');
        return json({
          'code': 1,
          'info': {'rows': [], 'total': 0},
        });
      });
      final api = CatalogAggregator(
        xifan: Dio()..httpClientAdapter = x,
        giri: Dio()..httpClientAdapter = g,
      );
      await api.browse(
        CatalogSource.xifan,
        2,
        kind: 'ova',
        year: 'older',
        finished: '1',
        genre: '校园',
      );
      await api.browse(
        CatalogSource.giri,
        1,
        kind: '3',
        area: '一月',
        genre: '喜剧',
        state: '漫画改',
      );
    },
  );

  test(
    'live classification loads actual Giri options and Xifan filtered catalogue',
    () async {
      final api = CatalogAggregator.instance;
      final options = await api.giriBrowseFilters();
      expect(options['year'], isNotEmpty);
      expect(options['area'], isNotEmpty);
      expect(options['genre'], contains('喜剧'));
      expect(options['state'], isNotEmpty);
      final result = await api.browse(
        CatalogSource.xifan,
        1,
        kind: 'tv',
        genre: '校园',
        order: 'release_date',
      );
      expect(result.items, isNotEmpty);
    },
    skip: Platform.environment['CYCANI_FILTERS_LIVE'] != '1',
  );
}
