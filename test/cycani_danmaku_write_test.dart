import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyanmoon_acg/features/cycani/site_accounts.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_playback_discussion.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_aggregator.dart';
import 'package:cyanmoon_acg/features/cycani/cycani_api.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_danmaku_dialog.dart';
import 'cycani_api_test.dart' show FakeAdapter;

ResponseBody response(Object value) => ResponseBody.fromString(
  jsonEncode(value),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'Xifan send/report use real episode/comment IDs and its own token',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'cycani.xifan.session.v1': jsonEncode({
          'access_token': 'xifan-token',
          'expires_at': 4102444800,
        }),
      });
      final requests = <RequestOptions>[];
      final api = SourceAccounts(
        xifan: Dio()
          ..httpClientAdapter = FakeAdapter((r) async {
            requests.add(r);
            expect(r.headers['Authorization'], 'Bearer xifan-token');
            return response({'ok': true});
          }),
      );
      await api.postXifanDanmaku(203779, ' hello ', 12.5, color: 0xFF0000);
      expect(requests.first.path, '/rest/v1/rpc/send_danmaku');
      expect(requests.first.data, {
        'p_episode_id': 203779,
        'p_content': 'hello',
        'p_v_time': 12.5,
        'p_mode': 'scroll',
        'p_color': '#ff0000',
      });
      await api.reportXifanDanmaku(33, ' spam ');
      expect(requests.last.path, '/rest/v1/rpc/report');
      expect(requests.last.data, {
        'p_target_type': 'danmaku',
        'p_target_id': 33,
        'p_reason': 'spam',
      });
    },
  );

  test(
    'Giri send/report use verified source cookies and canonical scrolling payload',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'cycani.giri.session.v1': jsonEncode({
          'cookies': {'sid': 'giri-cookie'},
        }),
      });
      final requests = <RequestOptions>[];
      final api = SourceAccounts(
        giri: Dio()
          ..httpClientAdapter = FakeAdapter((r) async {
            expect(r.headers['Cookie'], 'sid=giri-cookie');
            expect(r.headers.containsKey('Authorization'), isFalse);
            if (r.path.endsWith('/sso/status')) {
              return response({
                'info': {
                  'authenticated': true,
                  'csrf_token': 'proof',
                  'user': {'user_id': 87},
                },
              });
            }
            requests.add(r);
            expect(r.headers['X-CSRF-Token'], 'proof');
            return response({'code': 1});
          }),
      );
      const url = 'https://a.girigirilove.com/zijian/show/01/playlist.m3u8';
      await api.postGiriDanmaku(
        url,
        ' hello ',
        1.25,
        mode: 'bottom',
        color: 255,
      );
      expect(requests.first.path, '/api.php/Scrolling/add');
      final fields = Map.fromEntries((requests.first.data as FormData).fields);
      expect(fields['play_url'], url);
      final body = jsonDecode(fields['scroll_json']!);
      expect(body['time'], 1.25);
      expect(body['mode'], 3);
      expect(body['content'], 'hello');
      expect(body['style']['color'], '#0000ff');
      await api.reportGiriDanmaku(105450);
      expect(requests.last.method, 'GET');
      expect(requests.last.path, '/api.php/Scrolling/remove');
      expect(requests.last.queryParameters, {'scroll_id': '105450'});
    },
  );

  test('signed out and invalid writes never reach the network', () async {
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = FakeAdapter((_) async {
        calls++;
        return response({'ok': true, 'code': 1});
      });
    final api = SourceAccounts(xifan: dio, giri: dio);
    await expectLater(api.postXifanDanmaku(1, 'text', 1), throwsStateError);
    await expectLater(
      api.postGiriDanmaku('https://a.girigirilove.com/a.mp4', 'text', 1),
      throwsStateError,
    );
    await expectLater(
      api.postXifanDanmaku(1, 'text', double.nan),
      throwsArgumentError,
    );
    await expectLater(api.reportGiriDanmaku(-1), throwsArgumentError);
    expect(calls, 0);
  });

  test(
    'playback discussion resolves namespace and episode identity without guessing',
    () {
      final x = CatalogDiscussionTarget.fromPlayback(
        pluginName: '稀饭',
        itemId: -1000003432,
        pageUrl: 'https://next.xifanacg.com/anime/3432/play/203779',
      );
      expect(x?.source, CatalogSource.xifan);
      expect(x?.videoId, 3432);
      expect(x?.episodeId, 203779);
      final g = CatalogDiscussionTarget.fromPlayback(
        pluginName: 'GiriGiri',
        itemId: -2000027203,
        pageUrl: 'https://a.girigirilove.com/show/01.m3u8',
      );
      expect(g?.videoId, 27203);
      expect(
        CatalogDiscussionTarget.fromPlayback(
          pluginName: CycaniApi.pluginName,
          itemId: -2000027203,
          pageUrl: 'https://www.cycani.org/play/123',
        ),
        isNull,
      );
      expect(
        CatalogDiscussionTarget.fromPlayback(
          pluginName: 'GiriGiri',
          itemId: -2000027203,
          pageUrl: 'https://wrong.example/01.m3u8',
        ),
        isNull,
      );
    },
  );

  testWidgets(
    'shared send dialog captures time, prevents duplicate send and reloads on success',
    (tester) async {
      final pending = Completer<void>();
      var sent = 0, reloaded = 0;
      double? time;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CatalogDanmakuDialog(
                    sourceName: '稀饭',
                    position: () => 12.5,
                    onSent: () => reloaded++,
                    send:
                        (
                          String content,
                          double position, {
                          required String mode,
                          required int color,
                        }) {
                          expect(content, 'hello');
                          time = position;
                          sent++;
                          return pending.future;
                        },
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('发送稀饭弹幕'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.text('发送'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(sent, 1);
      expect(time, 12.5);
      pending.complete();
      await tester.pumpAndSettle();
      expect(reloaded, 1);
      expect(find.byType(CatalogDanmakuDialog), findsNothing);
    },
  );
}
