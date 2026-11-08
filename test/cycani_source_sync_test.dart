import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyanmoon_acg/features/cycani/site_accounts.dart';
import 'cycani_api_test.dart' show FakeAdapter;

ResponseBody response(Object? data) => ResponseBody.fromString(
  jsonEncode(data),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  test(
    'Giri follow cannot send with a replaced session after lookup',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'cycani.giri.session.v1': jsonEncode({
          'cookies': {'sid': 'fixture'},
        }),
      });
      final started = Completer<void>(), rows = Completer<ResponseBody>();
      final adapter = FakeAdapter((r) async {
        if (r.path.endsWith('/sso/status'))
          return response({
            'info': {
              'authenticated': true,
              'csrf_token': 'fixture',
              'user': {'user_id': 7},
            },
          });
        if (r.path.endsWith('/collectList')) {
          started.complete();
          return rows.future;
        }
        throw StateError('Unexpected write');
      });
      final api = SourceAccounts(giri: Dio()..httpClientAdapter = adapter);
      final pending = expectLater(api.setGiriFollow(9, 1), throwsStateError);
      await started.future;
      await api.logout(true);
      rows.complete(response({'code': 1, 'info': []}));
      await pending;
      expect(
        adapter.requests.any((r) => r.path.endsWith('/collectAdd')),
        isFalse,
      );
    },
  );

  test(
    'stale Giri collection write cannot enter a replacement account',
    () async {
      const key = 'cycani.giri.session.v1';
      FlutterSecureStorage.setMockInitialValues({
        key: jsonEncode({
          'cookies': {'sid': 'old-fixture'},
        }),
      });
      final api = SourceAccounts();
      final old = api.librarySession(true);
      await api.logout(true);
      await const FlutterSecureStorage().write(
        key: key,
        value: jsonEncode({
          'cookies': {'sid': 'new-fixture'},
        }),
      );
      await api.saveGiriCollections(null, [
        {'id': 90, 'group_name': 'old owner'},
      ], expectedSession: old);
      expect(await api.cachedGiriCollections(null), isNull);
      await api.saveGiriCollections(null, [
        {'id': 91, 'group_name': 'new owner'},
      ], expectedSession: api.librarySession(true));
      expect((await api.cachedGiriCollections(null))!.single['id'], 91);
    },
  );

  test('old library results cannot repopulate a replacement session', () async {
    const key = 'cycani.xifan.session.v1';
    FlutterSecureStorage.setMockInitialValues({key: 'old'});
    final api = SourceAccounts();
    final old = api.librarySession(false);
    await api.logout(false);
    await const FlutterSecureStorage().write(key: key, value: 'new');
    await api.saveLibrary(false, 5, [
      {'anime_id': 1},
    ], expectedSession: old);
    expect(await api.cachedLibrary(false, 5), isNull);
    await api.saveLibrary(false, 5, [
      {'anime_id': 2},
    ], expectedSession: api.librarySession(false));
    expect((await api.cachedLibrary(false, 5))?.single['anime_id'], 2);
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Giri original login carries the challenge cookie and persists verified session',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      Object? challenge;
      final adapter = FakeAdapter((r) async {
        if (r.path.endsWith('/verify/index.html')) {
          challenge = r.queryParameters['id'];
          return ResponseBody.fromBytes(
            [137, 80, 78, 71, 13, 10, 26, 10],
            200,
            headers: {
              'set-cookie': ['sid=challenge; Path=/'],
            },
          );
        }
        if (r.path.endsWith('/user/login')) {
          expect(r.headers['Cookie'], 'sid=challenge');
          expect(Map.fromEntries((r.data as FormData).fields), {
            'user_name': 'fixture',
            'user_pwd': 'pass',
            'verify': '1234',
            'id': '$challenge',
          });
          return ResponseBody.fromString(
            '{"code":1}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
              'set-cookie': ['sid=verified; Path=/'],
            },
          );
        }
        expect(r.path, '/index.php/sso/status');
        expect(r.headers['Cookie'], 'sid=verified');
        return response({
          'info': {
            'authenticated': true,
            'user': {'user_name': 'fixture', 'user_id': 87},
          },
        });
      });
      final api = SourceAccounts(giri: Dio()..httpClientAdapter = adapter);
      await api.captcha();
      expect(await api.giriLogin(' fixture ', 'pass', ' 1234 '), 'fixture');
      expect((await api.profile(true))?['user_id'], 87);
    },
  );

  test(
    'late Xifan profile does not enter the replacement account cache',
    () async {
      const key = 'cycani.xifan.session.v1';
      FlutterSecureStorage.setMockInitialValues({
        key: jsonEncode({'access_token': 'old', 'expires_at': 4102444800}),
      });
      final started = Completer<void>();
      final pending = Completer<ResponseBody>();
      final adapter = FakeAdapter((r) {
        started.complete();
        return pending.future;
      });
      final api = SourceAccounts(xifan: Dio()..httpClientAdapter = adapter);
      final profile = api.profile(false);
      await started.future;
      await api.logout(false);
      await const FlutterSecureStorage().write(key: key, value: 'new');
      pending.complete(response({'id': 'old-owner'}));
      expect(await profile, isNull);
      expect(await api.cachedProfile(false), isNull);
    },
  );

  test('Giri publishes root and reply with verified user and CSRF', () async {
    FlutterSecureStorage.setMockInitialValues({
      'cycani.giri.session.v1': jsonEncode({
        'cookies': {'sid': 'fixture'},
      }),
    });
    final sent = <Map<String, String>>[];
    final adapter = FakeAdapter((r) async {
      if (r.path.endsWith('/sso/status')) {
        return response({
          'info': {
            'authenticated': true,
            'csrf_token': 'csrf',
            'user': {'user_id': 87},
          },
        });
      }
      expect(r.path, '/api.php/Comment/add');
      expect(r.headers['X-CSRF-Token'], 'csrf');
      sent.add(Map.fromEntries((r.data as FormData).fields));
      return response({'code': 1});
    });
    final api = SourceAccounts(giri: Dio()..httpClientAdapter = adapter);
    await api.postComment(true, 31, 'root');
    await api.postComment(true, 31, 'reply', parent: 42);
    expect(sent, [
      {'user_id': '87', 'vod_id': '31', 'p_id': '0', 'content': 'root'},
      {'user_id': '87', 'vod_id': '31', 'p_id': '42', 'content': 'reply'},
    ]);
  });

  test('Xifan publishes root and reply with the source session', () async {
    FlutterSecureStorage.setMockInitialValues({
      'cycani.xifan.session.v1': jsonEncode({
        'access_token': 'fixture',
        'expires_at': 4102444800,
      }),
    });
    final sent = <Object?>[];
    final adapter = FakeAdapter((r) async {
      expect(r.path, '/rest/v1/rpc/post_comment');
      expect(r.headers['Authorization'], 'Bearer fixture');
      sent.add(r.data);
      return response({'ok': true});
    });
    final api = SourceAccounts(xifan: Dio()..httpClientAdapter = adapter);
    await api.postComment(false, 31, 'root');
    await api.postComment(false, 31, 'reply', parent: 42);
    expect(sent, [
      {'p_anime_id': 31, 'p_content': 'root'},
      {'p_anime_id': 31, 'p_content': 'reply', 'p_parent_id': 42},
    ]);
  });

  test(
    'Giri home preserves one failing section and clears on logout',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'cycani.giri.session.v1': jsonEncode({
          'cookies': {'sid': 'fixture'},
        }),
      });
      var fail = false;
      final adapter = FakeAdapter((r) async {
        if (r.path.endsWith('/sso/status')) {
          return response({
            'info': {
              'authenticated': true,
              'user': {'user_id': 87},
            },
          });
        }
        final collect = r.path.endsWith('/collectList');
        return response({
          'code': collect && fail ? 0 : 1,
          'info': [
            {
              'vod_id': collect
                  ? 3
                  : fail
                  ? 5
                  : 4,
            },
          ],
        });
      });
      final api = SourceAccounts(giri: Dio()..httpClientAdapter = adapter);
      await api.giriHomeAccountSections();
      fail = true;
      final sections = await api.giriHomeAccountSections();
      expect(sections.map((s) => (s['videos'] as List).single['video_id']), [
        3,
        5,
      ]);
      await api.logout(true);
      expect(api.cachedGiriHomeAccountSections, isEmpty);
    },
  );

  test(
    'Giri reads and mutates only the verified account using session CSRF',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'cycani.giri.session.v1': jsonEncode({
          'cookies': {'sid': 'fixture'},
        }),
      });
      final adapter = FakeAdapter((r) async {
        expect(r.headers['Cookie'], 'sid=fixture');
        if (r.path.endsWith('/sso/status')) {
          return response({
            'info': {
              'authenticated': true,
              'csrf_token': 'fixture-csrf',
              'user': {'user_id': 87},
            },
          });
        }
        if (r.path.endsWith('/history')) {
          expect(r.queryParameters['user_id'], 87);
          return response({
            'code': 1,
            'info': {
              'rows': [
                {'vod_id': 3},
              ],
            },
          });
        }
        if (r.path.endsWith('/collectList')) {
          return response({
            'code': 1,
            'info': [
              {'vod_id': 3},
            ],
          });
        }
        expect(r.headers['X-CSRF-Token'], 'fixture-csrf');
        return response({'code': 1});
      });
      final api = SourceAccounts(giri: Dio()..httpClientAdapter = adapter);
      expect((await api.giriHistory()).single['vod_id'], 3);
      await api.recordGiriHistory(3);
      await api.setGiriFollow(3, 2);
      expect(
        adapter.requests.map((r) => r.path),
        containsAll([
          '/api.php/vod/historyRecord',
          '/api.php/App2/collectEdit',
        ]),
      );
    },
  );

  test(
    'Xifan progress uses its episode id and milliseconds, not Cycani IDs',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'cycani.xifan.session.v1': jsonEncode({
          'access_token': 'fixture',
          'expires_at': 4102444800,
        }),
      });
      final adapter = FakeAdapter((r) async {
        expect(r.headers['Authorization'], 'Bearer fixture');
        return response({'ok': true});
      });
      final api = SourceAccounts(xifan: Dio()..httpClientAdapter = adapter);
      await api.recordXifanProgress(452, 90000, 120000);
      await api.setXifanFollow(33, 0);
      expect(adapter.requests.first.data, {
        'p_episode_id': 452,
        'p_position_ms': 90000,
        'p_duration_ms': 120000,
      });
      expect(adapter.requests.last.data, {'p_anime_id': 33, 'p_status': 0});
    },
  );
  test(
    'Xifan password changes require fresh verification of the current account',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'cycani.xifan.session.v1': jsonEncode({
          'access_token': 'fixture',
          'expires_at': 4102444800,
        }),
      });
      final adapter = FakeAdapter((r) async {
        if (r.method == 'GET') {
          expect(r.headers['Authorization'], 'Bearer fixture');
          return response({'id': 'test-user', 'email': 'tester@example.test'});
        }
        if (r.path.endsWith('/token')) {
          expect(r.data['email'], 'tester@example.test');
          expect(r.queryParameters['grant_type'], 'password');
          return response({
            'access_token': 'fresh',
            'refresh_token': 'fresh-refresh',
            'expires_at': 4102444800,
          });
        }
        expect(r.path, '/auth/v1/user');
        expect(r.method, 'PUT');
        expect(r.headers['Authorization'], 'Bearer fresh');
        return response({'id': 'test-user'});
      });
      final api = SourceAccounts(xifan: Dio()..httpClientAdapter = adapter);
      await api.changeXifanPassword('test-current', 'test-updated');
      expect(adapter.requests.map((r) => r.method), ['GET', 'POST', 'PUT']);
    },
  );
  test(
    'Giri collection writes are scoped to the verified account and folder',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'cycani.giri.session.v1': jsonEncode({
          'cookies': {'sid': 'fixture'},
        }),
      });
      final adapter = FakeAdapter((r) async {
        if (r.path.endsWith('/sso/status')) {
          return response({
            'info': {
              'authenticated': true,
              'csrf_token': 'fixture-csrf',
              'user': {'user_id': 87},
            },
          });
        }
        final fields = Map.fromEntries((r.data as FormData).fields);
        expect(fields['user_id'], '87');
        if (r.path.endsWith('/collectGroupList')) {
          return response({
            'code': 1,
            'info': [
              {'id': 9, 'group_name': 'fixture folder'},
            ],
          });
        }
        expect(r.headers['X-CSRF-Token'], 'fixture-csrf');
        expect(fields['group_id'], '9');
        expect(fields['vod_id'], '11');
        return response({'code': 1});
      });
      final api = SourceAccounts(giri: Dio()..httpClientAdapter = adapter);
      expect((await api.giriCollectionGroups()).single['id'], 9);
      await api.addGiriCollectionItem(9, 11);
      expect(adapter.requests.last.path, '/api.php/App2/collectGroupIdsAdd');
    },
  );
  test(
    'Giri private collection snapshots survive a new controller and clear on logout',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'cycani.giri.session.v1': jsonEncode({
          'cookies': {'sid': 'fixture'},
        }),
      });
      final writer = SourceAccounts();
      await writer.saveGiriCollections(null, [
        {'id': 12, 'group_name': 'test folder'},
      ]);
      await writer.saveGiriCollections(12, [
        {'vod_id': 9},
      ]);
      final reader = SourceAccounts();
      expect((await reader.cachedGiriCollections(null))?.single['id'], 12);
      expect((await reader.cachedGiriCollections(12))?.single['vod_id'], 9);
      await reader.logout(true);
      expect(await writer.cachedGiriCollections(null), isNull);
      expect(await writer.cachedGiriCollections(12), isNull);
      const storage = FlutterSecureStorage();
      expect(
        (await storage.readAll()).keys.where(
          (k) => k.startsWith('catalog.account.giri.collection'),
        ),
        isEmpty,
      );
    },
  );
  test(
    'Xifan email change forwards proof only to request and confirmation only gets code',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'cycani.xifan.session.v1': jsonEncode({
          'access_token': 'fixture',
          'expires_at': 4102444800,
        }),
      });
      final adapter = FakeAdapter((r) async {
        expect(r.headers['Authorization'], 'Bearer fixture');
        if (r.path.endsWith('request-email-change')) {
          expect(r.data['new_email'], 'next@example.test');
          expect(r.data['geetest'], hasLength(4));
          expect(r.data['geetest'], isNot(contains('access_token')));
          return response({'sent': true, 'masked_email': 'n***@example.test'});
        }
        expect(r.path, '/rest/v1/rpc/confirm_email_change');
        expect(r.data, {'p_code': '123456'});
        return response({'success': true, 'new_email': 'next@example.test'});
      });
      final api = SourceAccounts(xifan: Dio()..httpClientAdapter = adapter);
      await expectLater(
        api.requestXifanEmailChange('next@example.test', {}),
        throwsStateError,
      );
      expect(adapter.requests, isEmpty);
      final masked = await api.requestXifanEmailChange('next@example.test', {
        'lot_number': 'lot',
        'captcha_output': 'answer',
        'pass_token': 'pass',
        'gen_time': 'time',
        'access_token': 'ignored',
      });
      expect(masked, 'n***@example.test');
      expect(await api.confirmXifanEmailChange('123456'), 'next@example.test');
    },
  );
  test('Xifan history and follows advance by their own page sizes', () async {
    FlutterSecureStorage.setMockInitialValues({
      'cycani.xifan.session.v1': jsonEncode({
        'access_token': 'fixture',
        'expires_at': 4102444800,
      }),
    });
    final adapter = FakeAdapter((r) async {
      if (r.path.endsWith('get_continue_watching')) {
        expect(r.data, {'p_limit': 30, 'p_offset': 30});
        return response(List.generate(30, (i) => {'anime_id': i + 31}));
      }
      expect(r.queryParameters['limit'], 100);
      expect(r.queryParameters['offset'], 200);
      return response([
        {'anime_id': 201},
      ]);
    });
    final api = SourceAccounts(xifan: Dio()..httpClientAdapter = adapter);
    final (history, moreHistory) = await api.libraryPage(
      false,
      history: true,
      page: 2,
    );
    final (follows, moreFollows) = await api.libraryPage(
      false,
      history: false,
      page: 3,
    );
    expect(history.first['anime_id'], 31);
    expect(moreHistory, isTrue);
    expect(follows.single['anime_id'], 201);
    expect(moreFollows, isFalse);
  });
  test('late Xifan refresh cannot resurrect a signed-out session', () async {
    FlutterSecureStorage.setMockInitialValues({
      'cycani.xifan.session.v1': jsonEncode({
        'access_token': 'old',
        'refresh_token': 'old-refresh',
        'expires_at': 1,
      }),
    });
    final entered = Completer<void>(), token = Completer<ResponseBody>();
    final adapter = FakeAdapter((r) async {
      expect(r.path, '/auth/v1/token');
      entered.complete();
      return token.future;
    });
    final api = SourceAccounts(xifan: Dio()..httpClientAdapter = adapter);
    final pending = expectLater(api.xifanHistory(), throwsStateError);
    await entered.future;
    await api.logout(false);
    token.complete(
      response({
        'access_token': 'late',
        'refresh_token': 'late-refresh',
        'expires_at': 4102444800,
      }),
    );
    await pending;
    expect(await api.hasSession(false), isFalse);
    expect(await api.xifanHistory(), isEmpty);
    expect(adapter.requests, hasLength(1));
  });
  test('Xifan detail finds progress beyond the first page', () async {
    FlutterSecureStorage.setMockInitialValues({
      'cycani.xifan.session.v1': jsonEncode({
        'access_token': 'fixture',
        'expires_at': 4102444800,
      }),
    });
    final adapter = FakeAdapter((r) async {
      expect(r.path, '/rest/v1/rpc/get_continue_watching');
      if (r.data['p_offset'] == 0)
        return response(List.generate(100, (i) => {'anime_id': i + 1}));
      expect(r.data['p_offset'], 100);
      return response([
        {'anime_id': 101, 'episode_id': 201, 'position_ms': 88000},
      ]);
    });
    final api = SourceAccounts(xifan: Dio()..httpClientAdapter = adapter);
    expect((await api.xifanProgressFor(101))?['position_ms'], 88000);
    expect(adapter.requests, hasLength(2));
  });
}
