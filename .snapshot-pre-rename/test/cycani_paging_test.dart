import 'package:kazumi/features/cycani/cycani_models.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:kazumi/features/cycani/cycani_paging.dart';
import 'package:kazumi/features/cycani/cycani_api.dart';
import 'package:kazumi/features/cycani/cycani_home_page.dart';
import 'package:kazumi/features/cycani/cycani_search_page.dart';
import 'package:kazumi/features/cycani/cycani_comments.dart';
import 'cycani_api_test.dart' show FakeAdapter, MemoryVault, ok;

void main() {
  test('append, deduplicate, single-flight, stop on last page', () async {
    final pending = Completer<CycaniPage>();
    var calls = 0;
    final feed = CycaniFeed((p, c) {
      calls++;
      return p == 1
          ? Future.value(
              const CycaniPage([
                {'id': 1},
              ], hasMore: true),
            )
          : pending.future;
    });
    await feed.reset();
    final loading = feed.loadMore();
    await feed.loadMore();
    expect(calls, 2);
    pending.complete(
      const CycaniPage([
        {'id': 1},
        {'id': 2},
      ], hasMore: false),
    );
    await loading;
    expect(feed.items.map((v) => v['id']), [1, 2]);
    await feed.loadMore();
    expect(calls, 2);
    feed.dispose();
  });
  test('failure retains items and retries same next page', () async {
    final pages = <int>[];
    var fail = true;
    final feed = CycaniFeed((p, c) async {
      pages.add(p);
      if (p == 2 && fail) {
        fail = false;
        throw StateError('offline');
      }
      return CycaniPage([
        {'id': p},
      ], hasMore: p < 2);
    });
    await feed.reset();
    await feed.loadMore();
    expect(feed.items.length, 1);
    expect(feed.error, isNotNull);
    await feed.loadMore();
    expect(pages, [1, 2, 2]);
    expect(feed.items.length, 2);
    feed.dispose();
  });
  test('reset discards late results from previous query', () async {
    final old = Completer<CycaniPage>();
    var calls = 0;
    final feed = CycaniFeed(
      (p, c) => ++calls == 1
          ? old.future
          : Future.value(
              const CycaniPage([
                {'id': 2},
              ], hasMore: false),
            ),
    );
    final first = feed.reset();
    await feed.reset();
    old.complete(
      const CycaniPage([
        {'id': 1},
      ], hasMore: true),
    );
    await first;
    expect(feed.items.single['id'], 2);
    expect(feed.hasMore, false);
    feed.dispose();
  });
  test('opaque cursor advances and repeated cursor stops', () async {
    final cursors = <String?>[];
    final feed = CycaniFeed((p, c) async {
      cursors.add(c);
      return CycaniPage(
        [
          {'id': p},
        ],
        hasMore: true,
        cursor: 'opaque',
      );
    });
    await feed.reset();
    await feed.loadMore();
    await feed.loadMore();
    expect(cursors, [null, 'opaque']);
    expect(feed.hasMore, false);
    feed.dispose();
  });
  test('empty response stops even with invalid hasMore', () async {
    final feed = CycaniFeed(
      (p, c) async => const CycaniPage([], hasMore: true),
    );
    await feed.reset();
    expect(feed.hasMore, false);
    feed.dispose();
  });
  test('dispose ignores outstanding response', () async {
    final pending = Completer<CycaniPage>();
    final feed = CycaniFeed((p, c) => pending.future);
    final future = feed.reset();
    feed.dispose();
    pending.complete(
      const CycaniPage([
        {'id': 1},
      ], hasMore: false),
    );
    await future;
  });
  for (final mode in ['search', 'catalogue', 'comments']) {
    testWidgets('$mode appends on bottom scroll, no page buttons', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pages = <int>[];
      final adapter = FakeAdapter((req) async {
        if (req.path == '/video-zones' || req.path == '/ranks')
          return ok({'list': []});
        final page = (req.queryParameters['page'] as int?) ?? 1;
        pages.add(page);
        final size = mode == 'comments' ? 20 : 36;
        return ok({
          'list': List.generate(
            size,
            (i) => {
              'id': (page - 1) * size + i + 1,
              'video_id': (page - 1) * size + i + 1,
              'title': '番剧${(page - 1) * size + i + 1}',
              'content': '评论${(page - 1) * size + i + 1}',
            },
          ),
          'pager': {'total': size * 2},
        });
      });
      final api = CycaniApi(
        dio: Dio()..httpClientAdapter = adapter,
        vault: MemoryVault(),
      );
      final child = mode == 'search'
          ? CycaniSearchPage(initialKeyword: '测试', api: api)
          : mode == 'catalogue'
          ? CycaniHomePage(initialSection: 1, api: api)
          : Scaffold(
              body: SingleChildScrollView(
                child: CycaniComments(videoId: 1, api: api),
              ),
            );
      await tester.pumpWidget(MaterialApp(home: child));
      await tester.pumpAndSettle();
      expect(pages, [1]);
      expect(find.text('下一页'), findsNothing);
      expect(find.text('上一页'), findsNothing);
      final scrollable = mode == 'comments'
          ? find.byType(Scrollable).first
          : find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        mode == 'comments' ? find.text('评论20') : find.text('番剧36'),
        500,
        scrollable: scrollable,
        maxScrolls: 30,
      );
      await tester.drag(scrollable, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(pages, [1, 2]);
      expect(tester.takeException(), isNull);
      await tester.drag(scrollable, const Offset(0, -12000));
      await tester.pumpAndSettle();
      expect(pages, [1, 2]);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    });
  }
  testWidgets('ranking exposes only TV and theatre and loads selected API', (
    tester,
  ) async {
    final ids = <String>[];
    final adapter = FakeAdapter((r) async {
      if (r.path == '/ranks')
        return ok({
          'list': [
            {'id': 1, 'name': 'TV番组', 'type': 'weekly'},
            {'id': 2, 'name': '剧场番组', 'type': 'weekly'},
            {'id': 3, 'name': '其他番组', 'type': 'daily'},
          ],
        });
      if (r.path.contains('/videos')) ids.add(r.path);
      return ok({'list': []});
    });
    final api = CycaniApi(
      dio: Dio()..httpClientAdapter = adapter,
      vault: MemoryVault(),
    );
    await tester.pumpWidget(
      MaterialApp(home: CycaniHomePage(initialSection: 2, api: api)),
    );
    await tester.pumpAndSettle();
    expect(find.text('TV 番组'), findsOneWidget);
    expect(find.text('剧场番组'), findsOneWidget);
    for (final text in ['日榜', '周榜', '月榜', '总榜', '默认榜单', '其他番组'])
      expect(find.text(text), findsNothing);
    await tester.tap(find.text('剧场番组'));
    await tester.pumpAndSettle();
    expect(ids, ['/ranks/1/videos', '/ranks/2/videos']);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  for (final section in [4, 5]) {
    testWidgets('library $section appends with correct page or opaque cursor', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <Map<String, dynamic>>[];
      final adapter = FakeAdapter((req) async {
        if (req.path == '/video-zones' || req.path == '/ranks')
          return ok({'list': []});
        final second = section == 5
            ? req.queryParameters['cursor'] != null
            : req.queryParameters['page'] == 2;
        requests.add(Map<String, dynamic>.from(req.queryParameters));
        return ok({
          'list': List.generate(
            36,
            (i) => {
              'video': {
                'id': (second ? 36 : 0) + i + 1,
                'title': '番剧${(second ? 36 : 0) + i + 1}',
              },
            },
          ),
          if (section == 4) 'pager': {'total': 72},
          if (section == 5)
            'cursor': {
              'has_more': !second,
              'next_cursor': second ? null : 'opaque-36',
            },
        });
      });
      final vault = MemoryVault()
        ..value = jsonEncode({
          'token': 'test-token',
          'user': {'id': 7},
        });
      final api = CycaniApi(
        dio: Dio()..httpClientAdapter = adapter,
        vault: vault,
      );
      await api.restore();
      await tester.pumpWidget(
        MaterialApp(
          home: CycaniHomePage(
            initialSection: section,
            standalone: true,
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('番剧36'),
        500,
        scrollable: scrollable,
        maxScrolls: 30,
      );
      await tester.drag(scrollable, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      if (section == 5) {
        expect(requests.last['cursor'], 'opaque-36');
      } else {
        expect(requests.last['page'], 2);
      }
      expect(find.text('下一页'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    });
  }

  testWidgets('week view does not repeat its page title in content', (
    tester,
  ) async {
    final adapter = FakeAdapter(
      (r) async => ok({
        'list': r.path == '/index/weekday'
            ? [
                {'name': '周表', 'videos': []},
              ]
            : [],
      }),
    );
    final api = CycaniApi(
      dio: Dio()..httpClientAdapter = adapter,
      vault: MemoryVault(),
    );
    await tester.pumpWidget(
      MaterialApp(home: CycaniHomePage(initialSection: 3, api: api)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.text('周表'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  test('metadata labels remove duplicates without merging translations', () {
    expect(
      cycaniUniqueLabels(
        [
          'TV',
          ' tv ',
          '日本',
          'Japan',
          'FX Senshi Kurumi-chan',
          'FX Senshi Kurumi chan',
        ],
        exclude: ['TV'],
      ),
      ['日本', 'Japan', 'FX Senshi Kurumi-chan'],
    );
  });
  testWidgets('week refresh requests fresh selected-day data', (tester) async {
    final days = <int, int>{};
    final adapter = FakeAdapter((r) async {
      if (r.path == '/index/weekday') {
        final day = r.queryParameters['weekday'] as int;
        days[day] = (days[day] ?? 0) + 1;
        return ok({
          'list': [
            {'name': '周表', 'videos': []},
          ],
        });
      }
      return ok({'list': []});
    });
    final api = CycaniApi(
      dio: Dio()..httpClientAdapter = adapter,
      vault: MemoryVault(),
    );
    await tester.pumpWidget(
      MaterialApp(home: CycaniHomePage(initialSection: 3, api: api)),
    );
    await tester.pumpAndSettle();
    expect(days[DateTime.now().weekday], 1);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(days[DateTime.now().weekday], 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  testWidgets('comment refresh keeps previous rows until new data arrives', (
    tester,
  ) async {
    final refresh = Completer<ResponseBody>();
    var requests = 0;
    final adapter = FakeAdapter((r) async {
      requests++;
      if (requests == 1) {
        return ok({
          'list': [
            {'id': 1, 'content': '刷新前评论'},
          ],
        });
      }
      return refresh.future;
    });
    final api = CycaniApi(
      dio: Dio()..httpClientAdapter = adapter,
      vault: MemoryVault(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CycaniComments(videoId: 1, api: api),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新评论'));
    await tester.pump();
    expect(find.text('刷新前评论'), findsOneWidget);
    refresh.complete(
      ok({
        'list': [
          {'id': 2, 'content': '刷新后评论'},
        ],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('刷新前评论'), findsNothing);
    expect(find.text('刷新后评论'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
}
