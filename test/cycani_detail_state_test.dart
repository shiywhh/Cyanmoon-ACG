import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:cyanmoon_acg/features/cycani/cycani_api.dart';
import 'package:cyanmoon_acg/features/cycani/cycani_detail_page.dart';
import 'package:cyanmoon_acg/features/cycani/cycani_account_page.dart';
import 'package:cyanmoon_acg/pages/video/video_playback_args.dart';
import 'cycani_api_test.dart' show FakeAdapter, MemoryVault, ok;

void main() {
  testWidgets('late favorite read cannot overwrite a confirmed change', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final oldRead = Completer<ResponseBody>();
    var reads = 0;
    final api = CycaniApi(
      vault: MemoryVault()
        ..value = jsonEncode({
          'token': 'fixture',
          'user': {'id': 7},
        }),
      dio: Dio()
        ..httpClientAdapter = FakeAdapter((r) async {
          if (r.path == '/videos/1')
            return ok({'id': 1, 'title': '竞态测试', 'play_from': []});
          if (r.path == '/user/favorites/1') {
            if (++reads == 1) return oldRead.future;
            return ok({'favorited': true, 'category': 'want'});
          }
          if (r.path.endsWith('/comments'))
            return ok({
              'list': [],
              'pager': {'total': 0},
            });
          return ok({});
        }),
    );
    await api.restore();
    await tester.pumpWidget(
      MaterialApp(home: CycaniDetailPage(videoId: 1, api: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('追番状态'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '想看'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Chip, '想看'), findsOneWidget);
    oldRead.complete(ok({'favorited': true, 'category': 'watching'}));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Chip, '想看'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });

  testWidgets(
    'player return preserves detail and line; authenticated account opens profile',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var details = 0,
          sections = 0,
          recommendations = 0,
          comments = 0,
          historyReads = 0;
      final adapter = FakeAdapter((r) async {
        if (r.path == '/videos/1') {
          details++;
          return ok({
            'id': 1,
            'title': '测试番剧',
            'description': '测试简介',
            'play_from': [
              {'code': 'a', 'title': '线路 A'},
              {'code': 'b', 'title': '线路 B'},
            ],
          });
        }
        if (r.path == '/videos/1/sections') {
          sections++;
          final b = r.queryParameters['player_code'] == 'b';
          return ok({
            'list': [
              {'id': b ? 21 : 11, 'title': b ? 'B01' : 'A01'},
            ],
            'pager': {'total': 1},
          });
        }
        if (r.path.endsWith('/recommendations')) {
          recommendations++;
          return ok({'list': []});
        }
        if (r.path.endsWith('/comments')) {
          comments++;
          return ok({
            'list': [],
            'pager': {'total': 0},
          });
        }
        if (r.path == '/user/histories/1') {
          historyReads++;
          return ok({
            'section_id': 11,
            'section_title': 'A01',
            'progress': 120000,
          });
        }
        return ok({'favorited': true, 'category': 'watching'});
      });
      final vault = MemoryVault()
        ..value = jsonEncode({
          'token': 'unit-test',
          'user': {'id': 7},
        });
      final api = CycaniApi(
        dio: Dio()..httpClientAdapter = adapter,
        vault: vault,
      );
      await api.restore();
      final nav = GlobalKey<NavigatorState>();
      OnlineVideoPlaybackArgs? playback;
      Future<void> route(String title) => nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: CycaniDetailPage(
            videoId: 1,
            api: api,
            resolveCatalogVideoIds: () async => {'xifan': 20, 'giri': 30},
            openPlayer: (args) async {
              playback = args;
              await route('播放器');
            },
            openAccountSettings: () => route('账户资料'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('个人资料'), findsOneWidget);
      await tester.ensureVisible(find.text('线路 B'));
      await tester.tap(find.text('线路 B'));
      await tester.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byType(SingleChildScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scroll).position;
      final offset = position.pixels;
      await tester.tap(find.text('B01'));
      await tester.pumpAndSettle();
      expect(find.text('播放器'), findsOneWidget);
      expect(playback!.initialRoad, 1);
      expect(playback!.catalogVideoIds, {'cycani': 1, 'xifan': 20, 'giri': 30});
      await tester.tap(find.text('返回'));
      await tester.pumpAndSettle();
      expect(details, 1);
      expect(sections, 2);
      expect(recommendations, 1);
      expect(comments, 1);
      expect(historyReads, 2);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is ChoiceChip && (w.label as Text).data == '线路 B' && w.selected,
        ),
        findsOneWidget,
      );
      expect(position.pixels, offset);
      await tester.tap(find.byTooltip('个人资料'));
      await tester.pumpAndSettle();
      expect(find.text('账户资料'), findsOneWidget);
      expect(find.byType(CycaniAccountPage), findsNothing);
      await tester.tap(find.text('返回'));
      await tester.pumpAndSettle();
      expect(details, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    },
  );
}
