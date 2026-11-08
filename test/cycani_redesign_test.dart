import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kazumi/features/cycani/cycani_api.dart';
import 'package:kazumi/features/cycani/catalog_avatar_store.dart';
import 'package:kazumi/features/cycani/qingyue_home_page.dart';
import 'package:kazumi/features/cycani/catalog_search_page.dart';
import 'cycani_api_test.dart' show MemoryVault, FakeAdapter, ok;

void main() {
  test(
    'local avatar persists per account, replaces and resets without server writes',
    () async {
      final dir = await Directory.systemTemp.createTemp('cycani-avatar-');
      addTearDown(() => dir.delete(recursive: true));
      final source = File('${dir.path}/selected.png');
      await source.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=',
        ),
      );
      final store = CatalogAvatarStore(directory: () async => dir);
      await store.setFile(7, XFile(source.path));
      expect(
        await File(store.pathFor(7)!).readAsBytes(),
        await source.readAsBytes(),
      );
      expect(store.pathFor(8), isNull);
      final restored = CatalogAvatarStore(directory: () async => dir);
      await restored.initialize();
      expect(restored.pathFor(7), store.pathFor(7));
      await restored.setFile(7, XFile(source.path));
      await restored.clear(7);
      expect(restored.pathFor(7), isNull);
      final cleared = CatalogAvatarStore(directory: () async => dir);
      await cleared.initialize();
      expect(cleared.pathFor(7), isNull);
    },
  );
  for (final size in [const Size(390, 844), const Size(1280, 860)]) {
    testWidgets('five destinations and independent search at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final adapter = FakeAdapter(
        (r) async => ok({
          'list': [],
          'pager': {'total': 0},
        }),
      );
      final api = CycaniApi(
        dio: Dio()..httpClientAdapter = adapter,
        vault: MemoryVault(),
      );
      await tester.pumpWidget(MaterialApp(home: QingyueHomePage(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('分类'), findsOneWidget);
      expect(find.text('探索'), findsNothing);
      expect(find.text('我的追番'), findsNothing);
      expect(find.byTooltip('退出'), findsOneWidget);
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      expect(find.text('我的追番'), findsOneWidget);
      expect(find.text('下载记录'), findsOneWidget);
      expect(find.text('账户设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogSearchPage), findsOneWidget);
      await tester.enterText(find.byType(TextField), '测试番剧');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('未找到番剧'), findsOneWidget);
      final req = adapter.requests.lastWhere((r) => r.path == '/videos/search');
      expect(req.queryParameters['q'], '测试番剧');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('我的追番'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    });
  }
  testWidgets(
    'main tabs restore their own scroll positions without fetching again',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final rows = List.generate(
        36,
        (i) => {'id': i + 1, 'title': '番剧 ${i + 1}'},
      );
      final adapter = FakeAdapter((r) async {
        if (r.path == '/index/recommend')
          return ok({
            'list': [
              {'name': '推荐', 'videos': rows},
            ],
          });
        if (r.path == '/videos/search' || r.path == '/videos')
          return ok({
            'list': rows,
            'pager': {'total': 36},
          });
        return ok({'list': []});
      });
      final api = CycaniApi(
        dio: Dio()..httpClientAdapter = adapter,
        vault: MemoryVault(),
      );
      await tester.pumpWidget(MaterialApp(home: QingyueHomePage(api: api)));
      await tester.pumpAndSettle();
      final view = find.byType(CustomScrollView);
      await tester.drag(view, const Offset(0, -540));
      await tester.pumpAndSettle();
      double offset() =>
          tester.widget<CustomScrollView>(view).controller!.offset;
      final first = offset();
      expect(first, greaterThan(100));
      await tester.tap(find.text('分类').last);
      await tester.pumpAndSettle();
      expect(offset(), 0);
      await tester.tap(find.text('主页').last);
      await tester.pumpAndSettle();
      expect(offset(), closeTo(first, 1));
      expect(
        adapter.requests.where((r) => r.path == '/index/recommend'),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    },
  );
}
