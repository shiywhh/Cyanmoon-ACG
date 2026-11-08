import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyanmoon_acg/features/cycani/giri_danmaku.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_danmaku_loader.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_danmaku_options.dart';
import 'package:cyanmoon_acg/features/cycani/site_native_catalog.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_aggregator.dart';
import 'cycani_api_test.dart' show FakeAdapter;

ResponseBody jsonResponse(Object? value) => ResponseBody.fromString(
  jsonEncode(value),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
const fixtureXml =
    '<i><d p="2,5,25,16711680">a &amp; b</d>'
    '<d p="1,4,25,255"><![CDATA[<hello>]]></d>'
    '<d p="-1,1,25,1">bad</d><d p="NaN,1,25,1">bad</d></i>';

void main() {
  test(
    'transient read disconnect retries with fresh multipart bodies',
    () async {
      var calls = 0;
      final bodies = <FormData>[];
      final api = Dio()
        ..httpClientAdapter = FakeAdapter((request) async {
          calls++;
          bodies.add(request.data as FormData);
          if (calls == 1)
            throw DioException(
              requestOptions: request,
              type: DioExceptionType.connectionError,
            );
          return jsonResponse({
            'code': 1,
            'info': [
              {
                'scroll_json': {'time': 1, 'content': 'recovered'},
              },
            ],
          });
        });
      final rows = await GiriDanmakuApi(
        api: api,
      ).internal('https://a.girigirilove.com/01.m3u8');
      expect(rows.single.message, 'recovered');
      expect(calls, 2);
      expect(identical(bodies[0], bodies[1]), isFalse);
    },
  );

  test(
    'missing XML is a provider error, not a trigger for unrelated DNS requests',
    () async {
      final api = Dio()
        ..httpClientAdapter = FakeAdapter(
          (_) async => jsonResponse({
            'code': 1,
            'info': 'https://akua.girigirilove.com/zijian/05.xml',
          }),
        );
      var calls = 0;
      final xml = Dio()
        ..httpClientAdapter = FakeAdapter((_) async {
          calls++;
          return ResponseBody.fromString('not found', 404);
        });
      await expectLater(
        GiriDanmakuApi(
          api: api,
          xml: xml,
        ).external('https://a.girigirilove.com/01.m3u8'),
        throwsA(isA<DioException>()),
      );
      expect(calls, 1);
    },
  );

  test(
    'Giri internal rows use native mode, fractional time and JSON style color',
    () {
      final rows = GiriDanmakuApi.parseInternal([
        {
          'scroll_json': {
            'time': 1.5,
            'content': 'hello',
            'mode': 2,
            'style': {'color': '#FF0000'},
          },
        },
        {
          'scroll_json': jsonEncode({
            'time': 2,
            'content': 'bottom',
            'mode': 3,
          }),
        },
        {'scroll_json': '{broken'},
        {
          'scroll_json': {'time': -1, 'content': 'invalid'},
        },
      ]);
      expect(rows.map((r) => r.time), [1.5, 2]);
      expect(rows.map((r) => r.type), [5, 4]);
      expect(rows.first.color.toARGB32(), 0xFFFF0000);
      expect(
        rows.every((r) => r.source == CatalogDanmakuOptions.giriSource),
        isTrue,
      );
    },
  );

  test(
    'XML preserves entities and CDATA while rejecting invalid timestamps',
    () {
      final rows = GiriDanmakuApi.parseXml(fixtureXml);
      expect(rows.map((r) => r.time), [1, 2]);
      expect(rows.map((r) => r.message), ['<hello>', 'a & b']);
      expect(rows.map((r) => r.type), [4, 5]);
      expect(rows.first.color.toARGB32(), 0xFF0000FF);
      expect(
        rows.every((r) => r.source == CatalogDanmakuOptions.giriExternalSource),
        isTrue,
      );
    },
  );

  test(
    'companion XML fallback is confined to official self-hosted playlist paths',
    () {
      expect(
        GiriDanmakuApi.fallbackXml(
          'https://a.girigirilove.com/zijian/show/01/playlist.m3u8?token=x#part',
        ).toString(),
        'https://a.girigirilove.com/zijian/show/01.xml',
      );
      expect(
        GiriDanmakuApi.fallbackXml(
          'https://other.example/zijian/01/playlist.m3u8',
        ),
        isNull,
      );
      expect(
        GiriDanmakuApi.fallbackXml(
          'https://a.girigirilove.com/other/playlist.m3u8',
        ),
        isNull,
      );
    },
  );

  test(
    'readers use multipart play_url and never forward credentials to XML/DNS',
    () async {
      final api = Dio(BaseOptions(headers: {'Authorization': 'secret'}));
      api.httpClientAdapter = FakeAdapter((r) async {
        expect(r.headers.containsKey('Authorization'), isFalse);
        expect(Map.fromEntries((r.data as FormData).fields), {
          'play_url': 'https://media.example/episode.m3u8',
        });
        return jsonResponse({
          'code': 1,
          'info': 'https://akua.girigirilove.com/zijian/01.xml',
        });
      });
      var calls = 0;
      final xml = Dio(BaseOptions(headers: {'Cookie': 'secret'}));
      xml.httpClientAdapter = FakeAdapter((r) async {
        expect(r.headers.containsKey('Cookie'), isFalse);
        calls++;
        if (calls == 1) throw const SocketException('TLS closed');
        if (r.uri.host == 'dns.alidns.com' ||
            r.uri.host == 'cloudflare-dns.com') {
          return jsonResponse({
            'Answer': [
              {'type': 5, 'data': 'fixture.girigirilove.com.'},
            ],
          });
        }
        expect(r.uri.host, 'fixture.girigirilove.com');
        expect(r.headers['Host'], 'akua.girigirilove.com');
        return ResponseBody.fromString(fixtureXml, 200);
      });
      final rows = await GiriDanmakuApi(
        api: api,
        xml: xml,
      ).external('https://media.example/episode.m3u8');
      expect(rows, hasLength(2));
      expect(calls, 4);
    },
  );

  test(
    'Giri independent sources merge even when the XML request fails',
    () async {
      final result = await CatalogDanmakuLoader.loadCombined(
        options: const CatalogDanmakuOptions(
          external: false,
          xifan: false,
          cycani: false,
        ),
        loadExternal: () async => [],
        loadXifan: () async => [],
        loadCycani: () async => [],
        loadGiri: () async => GiriDanmakuApi.parseInternal([
          {
            'scroll_json': {'time': 1, 'content': 'site'},
          },
        ]),
        loadGiriExternal: () async => throw StateError('offline'),
      );
      expect(result.danmakus.single.source, CatalogDanmakuOptions.giriSource);
      expect(result.allSourcesLoaded, isFalse);
    },
  );

  test(
    'live Giri episode reads native and external XML using production readers',
    () async {
      final detail = await NativeCatalogApi.instance.detail(
        CatalogSource.giri,
        27203,
      );
      final url = detail.roads.first.data.first;
      final rows = await Future.wait([
        GiriDanmakuApi.instance.internal(url),
        GiriDanmakuApi.instance.external(url),
      ]);
      expect(rows[0], isNotEmpty);
      expect(rows[1], isNotEmpty);
      print('Giri native ${rows[0].length}, external ${rows[1].length}');
    },
    skip: Platform.environment['GIRI_DANMAKU_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
