import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyanmoon_acg/features/cycani/cycani_api.dart';
import 'package:cyanmoon_acg/features/cycani/cycani_account_stats.dart';
import 'package:cyanmoon_acg/features/cycani/qingyue_my_page.dart';
import 'cycani_api_test.dart' show FakeAdapter, MemoryVault, ok;

void main() {
  test(
    'cloud stats exhaust opaque cursors, deduplicate and use favorite total',
    () async {
      final cursors = <Object?>[];
      final adapter = FakeAdapter((r) async {
        if (r.path == '/user/favorites')
          return ok({
            'list': [
              {'video_id': 1},
            ],
            'pager': {'total': 42},
          });
        final next = r.queryParameters['cursor'];
        cursors.add(next);
        return ok({
          'list': next == null
              ? [
                  {'video_id': 1},
                  {'video_id': 2},
                ]
              : [
                  {'video_id': 1},
                  {'video_id': 3},
                ],
          'deleted_video_ids': next == null ? [] : [2],
          'cursor': {
            'has_more': next == null,
            'next_cursor': next == null ? 'next' : null,
          },
        });
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
      final stats = await loadCycaniAccountStats(api);
      expect(stats.watchedVideos, 2);
      expect(stats.favorites, 42);
      expect(cursors, [null, 'next']);
      api.dispose();
    },
  );
  test(
    'native seconds become site milliseconds on history reporting',
    () async {
      final adapter = FakeAdapter((r) async => ok({}));
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
      await api.reportHistory(52391, 2.099, 1425.171);
      expect(adapter.requests.last.data['progress'], 2099);
      expect(adapter.requests.last.data['duration'], 1425171);
      api.dispose();
    },
  );
  testWidgets('My displays cloud metrics and clears them on logout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final adapter = FakeAdapter(
      (r) async => ok(
        r.path == '/user/me'
            ? {'id': 7, 'nickname': '用户'}
            : r.path == '/user/favorites'
            ? {
                'list': [
                  {'video_id': 1},
                ],
                'pager': {'total': 1},
              }
            : {
                'list': [
                  {'video_id': 1},
                  {'video_id': 2},
                ],
                'cursor': {'has_more': false},
              },
      ),
    );
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QingyueMyPage(
            api: api,
            openLibrary: (_) {},
            openDownloads: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('观看番剧'), findsOneWidget);
    expect(find.text('追番数量'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('观看集数'), findsNothing);
    await api.logout();
    await tester.pumpAndSettle();
    expect(find.text('2'), findsNothing);
    expect(find.text('—'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  test('watch stats survive restore but never cross a logout epoch', () async {
    final vault = MemoryVault()
      ..value = jsonEncode({
        'token': 'session',
        'user': {'id': 23},
      });
    final writer = CycaniApi(vault: vault);
    await writer.restore();
    final epoch = writer.sessionEpoch;
    await writer.saveWatchStats(8, 12, epoch: epoch);
    final reader = CycaniApi(vault: vault);
    await reader.restore();
    expect(reader.cachedWatchStats, {
      'owner': '23',
      'watched': 8,
      'favorites': 12,
    });
    await writer.logout();
    await writer.saveWatchStats(99, 99, epoch: epoch);
    expect(vault.value, isNull);
    expect(writer.cachedWatchStats, isEmpty);
    writer.dispose();
    reader.dispose();
  });
}
