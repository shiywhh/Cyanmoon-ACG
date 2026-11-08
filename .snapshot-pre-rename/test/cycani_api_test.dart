import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/cycani_api.dart';
import 'package:kazumi/features/cycani/cycani_models.dart';

class MemoryVault implements CycaniVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? v) async {
    value = v;
  }
}

typedef Handler = Future<ResponseBody> Function(RequestOptions);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handle);
  final Handler handle;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody ok(dynamic data) => ResponseBody.fromString(
  jsonEncode({'code': 0, 'msg': '', 'data': data}),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
ResponseBody unauthorized() => ResponseBody.fromString(
  '{"code":401,"msg":"unauthorized","data":null}',
  401,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
CycaniJson payload(RequestOptions r) =>
    cycaniMap(r.data is String ? jsonDecode(r.data) : r.data);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryVault vault;
  late Dio dio;
  late CycaniApi api;
  late FakeAdapter adapter;
  void setup(Handler handler, {bool authenticated = false}) {
    vault = MemoryVault();
    if (authenticated)
      vault.value = jsonEncode({
        'token': 'test-session',
        'user': {'id': 7},
      });
    adapter = FakeAdapter(handler);
    dio = Dio()..httpClientAdapter = adapter;
    api = CycaniApi(dio: dio, vault: vault);
  }

  test(
    'stable section identifiers reject alternate hosts, paths and queries',
    () {
      expect(cycaniSectionId('https://www.cycani.org/section/52391'), 52391);
      for (final value in [
        'https://evil.test/section/1',
        'http://www.cycani.org/section/1',
        'https://www.cycani.org:444/section/1',
        'https://www.cycani.org/section/0',
        'https://www.cycani.org/section/1?x=1',
        'https://www.cycani.org/section/1#x',
      ]) {
        expect(cycaniSectionId(value), isNull, reason: value);
      }
    },
  );
  test('site video IDs are isolated from existing Bangumi storage', () {
    final item = CycaniVideo({
      'video_id': 63,
      'title': '紫罗兰永恒花园',
      'cover_url': 'https://img.test/a.jpg',
      'bangumi_id': 183878,
    }).toBangumi();
    expect(item.id, -63);
    expect(item.nameCn, '紫罗兰永恒花园');
    expect(item.info, 'cycani:63');
  });
  test(
    'public search has exact site headers, encoded query and no bearer',
    () async {
      setup((r) async => ok({'list': []}));
      await api.videos(keyword: '紫罗兰 永恒', page: 2, zone: 1, year: '2018');
      final r = adapter.requests.single;
      expect(r.path, '/videos/search');
      expect(r.queryParameters['q'], '紫罗兰 永恒');
      expect(r.queryParameters['page'], 2);
      expect(r.headers['X-App-Name'], 'cyc_web');
      expect(r.headers.containsKey('Authorization'), false);
    },
  );
  test('private playback without login never reaches transport', () async {
    setup((r) async => ok({}));
    await expectLater(api.playUrl(831), throwsA(isA<CycaniException>()));
    expect(adapter.requests, isEmpty);
  });

  test(
    'unfiltered catalogue always supplies the site-required ZoneID',
    () async {
      setup((r) async => ok({'list': []}));
      await api.videos();
      expect(adapter.requests.single.path, '/videos');
      expect(adapter.requests.single.queryParameters['zone_id'], 1);
      await api.videos(zone: 2);
      expect(adapter.requests.last.queryParameters['zone_id'], 2);
    },
  );
  test('absolute and protocol-relative API paths are rejected', () async {
    setup((r) async => ok({}));
    for (final path in [
      'https://evil.test',
      '//evil.test',
      '/x/https://evil.test',
    ]) {
      await expectLater(api.request(path), throwsA(isA<CycaniException>()));
    }
    expect(adapter.requests, isEmpty);
  });
  test(
    'pagination loads every episode across every source, without 100-episode truncation',
    () async {
      setup((r) async {
        final page = int.parse('${r.queryParameters['page']}');
        final code = r.queryParameters['player_code'];
        final count = code == 'main' ? (page == 1 ? 100 : 37) : 2;
        final start = (page - 1) * 100;
        return ok({
          'list': List.generate(
            count,
            (i) => {
              'id': start + i + 1 + (code == 'main' ? 0 : 1000),
              'title': '第${start + i + 1}集',
            },
          ),
          'pager': {'total': code == 'main' ? 137 : 2},
        });
      });
      final result = await api.episodes(
        63,
        video: const CycaniVideo({
          'id': 63,
          'play_from': [
            {'code': 'main', 'title': '主线'},
            {'code': 'backup', 'title': '备用'},
          ],
        }),
      );
      expect(result.map((e) => e.items.length), [137, 2]);
      expect(adapter.requests.length, 3);
      expect(
        result.first.toRoad().data.last,
        'https://www.cycani.org/section/137',
      );
    },
  );
  test(
    'play URL is freshly resolved each time and bearer stays on API host',
    () async {
      var count = 0;
      setup(
        (r) async => ok({
          'name': '第01集',
          'url': 'https://media.test/a.mp4?expires=${++count}',
        }),
        authenticated: true,
      );
      await api.restore();
      expect(await api.playUrl(831), 'https://media.test/a.mp4?expires=1');
      expect(await api.playUrl(831), 'https://media.test/a.mp4?expires=2');
      expect(
        adapter.requests.every(
          (r) =>
              r.uri.host == 'www.cycani.org' &&
              r.headers['Authorization'] == 'Bearer test-session',
        ),
        true,
      );
    },
  );
  test(
    'invalid or insecure media URL is not passed to native player',
    () async {
      setup(
        (r) async => ok({'url': 'http://media.test/a.mp4'}),
        authenticated: true,
      );
      await api.restore();
      await expectLater(api.playUrl(1), throwsA(isA<CycaniException>()));
    },
  );
  test(
    'concurrent 401 responses share one refresh and retry with new bearer',
    () async {
      var refreshes = 0;
      setup((r) async {
        if (r.path == '/auth/refresh') {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return ok({'token': 'new-session'});
        }
        return r.headers['Authorization'] == 'Bearer test-session'
            ? unauthorized()
            : ok({'url': 'https://media.test/a.mp4'});
      }, authenticated: true);
      await api.restore();
      await Future.wait([api.playUrl(1), api.playUrl(2)]);
      expect(refreshes, 1);
      expect(vault.value, contains('new-session'));
    },
  );
  test('expired refresh clears session instead of infinite retries', () async {
    setup((r) async => unauthorized(), authenticated: true);
    await api.restore();
    await expectLater(api.playUrl(1), throwsA(isA<CycaniException>()));
    expect(api.loggedIn, false);
    expect(vault.value, isNull);
    expect(adapter.requests.length, 2);
  });
  test(
    'login saves only server-issued session, never the submitted password',
    () async {
      setup(
        (r) async => ok({
          'token': 'server-token',
          'user': {'id': 7, 'nickname': '测试'},
        }),
      );
      await api.login('user', 'test-password');
      expect(api.loggedIn, true);
      expect(vault.value, contains('server-token'));
      expect(vault.value, isNot(contains('test-password')));
      expect(payload(adapter.requests.single)['username'], 'user');
    },
  );
  test('invalid token import keeps previous working account', () async {
    setup((r) async => unauthorized(), authenticated: true);
    await api.restore();
    await expectLater(
      api.importToken('invalid.new.token'),
      throwsA(isA<CycaniException>()),
    );
    expect(api.loggedIn, true);
    expect(vault.value, contains('test-session'));
  });

  test('login token with Bearer prefix is sent exactly once', () async {
    setup(
      (r) async => r.path == '/auth/login'
          ? ok({
              'token': '  Bearer issued-token  ',
              'user': {'id': 7},
            })
          : ok({'url': 'https://media.test/a.mp4'}),
    );
    await api.login('user', 'test-password');
    await api.playUrl(831);
    expect(
      adapter.requests.last.headers['Authorization'],
      'Bearer issued-token',
    );
    expect(vault.value, contains('issued-token'));
    expect(vault.value, isNot(contains('Bearer issued-token')));
  });

  test(
    'existing malformed Bearer-prefixed saved session is migrated',
    () async {
      setup((r) async => ok({'url': 'https://media.test/a.mp4'}));
      vault.value = jsonEncode({
        'token': 'Bearer Bearer saved-token',
        'user': {'id': 7},
      });
      await api.restore();
      await api.playUrl(831);
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer saved-token',
      );
      expect(vault.value, isNot(contains('Bearer')));
    },
  );

  test(
    'refresh responses with Bearer prefix do not create duplicate headers',
    () async {
      setup((r) async {
        if (r.path == '/auth/refresh')
          return ok({'token': 'Bearer renewed-token'});
        return r.headers['Authorization'] == 'Bearer test-session'
            ? unauthorized()
            : ok({'url': 'https://media.test/a.mp4'});
      }, authenticated: true);
      await api.restore();
      await api.playUrl(831);
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer renewed-token',
      );
    },
  );
  test('account switch discards late private responses', () async {
    setup((r) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return ok({'list': []});
    }, authenticated: true);
    await api.restore();
    final future = api.favorites();
    await api.logout();
    await expectLater(future, throwsA(isA<CycaniException>()));
  });
  test(
    'comment, danmaku and history mutation payloads match observed site API',
    () async {
      setup((r) async => ok({}), authenticated: true);
      await api.restore();
      await api.postComment(63, ' hello ', parentId: 9);
      await api.postDanmaku(831, ' hi ', 12.5, mode: 'top', color: 0xFFCC00);
      await api.reportHistory(831, 20.5, 1500);
      await api.moveFavorites([63, 64], 'watched');
      expect(payload(adapter.requests[0]), {
        'video_id': 63,
        'content': 'hello',
        'parent_id': 9,
      });
      expect(payload(adapter.requests[1]), {
        'section_id': 831,
        'content': 'hi',
        'time_point': 12.5,
        'mode': 'top',
        'color': 0xFFCC00,
      });
      expect(payload(adapter.requests[2])['section_id'], 831);
      expect(payload(adapter.requests[3]), {
        'video_ids': [63, 64],
        'to_category': 'watched',
      });
      expect(adapter.requests.every((r) => r.method == 'POST'), true);
    },
  );
  test(
    'network errors do not expose authorization or signed URL in user errors',
    () async {
      setup(
        (r) async => throw DioException(
          requestOptions: r,
          type: DioExceptionType.connectionTimeout,
        ),
        authenticated: true,
      );
      await api.restore();
      try {
        await api.playUrl(831);
        fail('expected error');
      } catch (e) {
        expect('$e', isNot(contains('test-session')));
        expect('$e', isNot(contains('Bearer')));
      }
    },
  );
  test(
    'Cycani library snapshots are owner-scoped and clear on logout',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final vault = MemoryVault()
        ..value = jsonEncode({
          'token': 'token',
          'user': {'id': 27},
        });
      final api = CycaniApi(
        vault: vault,
        libraryStore: const FlutterSecureStorage(),
      );
      await api.restore();
      await api.saveLibrarySnapshot(5, '', [
        {
          'video_id': 2,
          'progress': 8000,
          'secret': 'ignored',
          'video': {'id': 2, 'title': 'Title'},
        },
      ], epoch: api.sessionEpoch);
      final restored = CycaniApi(
        vault: vault,
        libraryStore: const FlutterSecureStorage(),
      );
      await restored.restore();
      final rows = await restored.readLibrarySnapshot(5, '');
      expect(rows?.single['video_id'], 2);
      expect(rows?.single, isNot(contains('secret')));
      final another = CycaniApi(
        libraryStore: const FlutterSecureStorage(),
        vault: MemoryVault()
          ..value = jsonEncode({
            'token': 'other',
            'user': {'id': 28},
          }),
      );
      await another.restore();
      expect(await another.readLibrarySnapshot(5, ''), isNull);
      await api.logout();
      expect(await restored.readLibrarySnapshot(5, ''), isNull);
      api.dispose();
      restored.dispose();
      another.dispose();
    },
  );
}
