import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/features/cycani/catalog_identity.dart';
import 'package:kazumi/features/cycani/catalog_lru.dart';
import 'package:kazumi/features/cycani/catalog_danmaku_cache.dart';
import 'package:kazumi/features/cycani/cycani_source_accounts.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'cycani_api_test.dart' show FakeAdapter;

class Paths extends PathProviderPlatform {
  Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

ResponseBody json(Object value) => ResponseBody.fromString(
  jsonEncode(value),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all site identities round-trip old history namespaces without collisions',
    () {
      for (final source in CatalogSource.values) {
        final entry = SiteEntry(source, 123);
        expect(SiteEntry.fromLegacy(entry.legacyId), entry);
      }
      for (final id in [0, 1, -1000000000, -2000000000, -3000000001]) {
        expect(SiteEntry.fromLegacy(id), isNull);
      }
    },
  );
  test('LRU is bounded and reading keeps an entry alive', () {
    final cache = CatalogLru<String, int>(capacity: 2)
      ..['a'] = 1
      ..['b'] = 2;
    expect(cache['a'], 1);
    cache['c'] = 3;
    expect(cache.containsKey('b'), isFalse);
    expect(cache.entries.length, 2);
  });
  test(
    'source cache preserves failed sources, allows successful empty, isolates identity',
    () async {
      final root = await Directory.systemTemp.createTemp('qingyue-cache-test-');
      final old = PathProviderPlatform.instance;
      PathProviderPlatform.instance = Paths(root.path);
      try {
        final cache = CatalogDanmakuCache('episode-one');
        DanmakuEntry entry(String source) => DanmakuEntry(
          message: source,
          time: 1,
          type: 1,
          color: Colors.white,
          source: source,
        );
        await cache.readThrough('a', () async => [entry('a')]);
        await cache.readThrough('b', () async => [entry('b')]);
        final a = await cache.readThrough(
          'a',
          () async => throw StateError('offline'),
          refresh: true,
        );
        expect(a.single.message, 'a');
        expect(
          await cache.readThrough('b', () async => [], refresh: true),
          isEmpty,
        );
        expect(
          await cache.readThrough('b', () async => throw StateError('offline')),
          isEmpty,
        );
        await expectLater(
          CatalogDanmakuCache(
            'episode-two',
          ).readThrough('a', () async => throw StateError('offline')),
          throwsStateError,
        );
      } finally {
        PathProviderPlatform.instance = old;
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'Giri cloud progress uses one-based episode position, seconds and CSRF',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'cycani.giri.session.v1': jsonEncode({
          'cookies': {'sid': 'test'},
        }),
      });
      final requests = <RequestOptions>[];
      final api = SourceAccounts(
        giri: Dio()
          ..httpClientAdapter = FakeAdapter((r) async {
            if (r.path.endsWith('/sso/status'))
              return json({
                'info': {
                  'authenticated': true,
                  'csrf_token': 'proof',
                  'user': {'user_id': 87},
                },
              });
            requests.add(r);
            return json({
              'code': 1,
              'info': r.path.endsWith('getVodPlayTime') ? '12.75' : null,
            });
          }),
      );
      expect(await api.giriProgress(27203, 2), 12.75);
      await api.recordGiriProgress(27203, 2, 12.75);
      expect(requests.map((r) => r.path), [
        '/api.php/App2/getVodPlayTime',
        '/api.php/App2/setVodPlayTime',
      ]);
      final fields = Map.fromEntries((requests.last.data as FormData).fields);
      expect(fields, {
        'user_id': '87',
        'vod_id': '27203',
        'no': '2',
        'time': '12.75',
      });
      expect(requests.last.headers['X-CSRF-Token'], 'proof');
      await expectLater(api.recordGiriProgress(1, 0, 5), throwsArgumentError);
      await expectLater(
        api.recordGiriProgress(1, 1, double.nan),
        throwsArgumentError,
      );
    },
  );
}
