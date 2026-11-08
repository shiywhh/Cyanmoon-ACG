import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/features/cycani/catalog_danmaku_options.dart';
import 'package:kazumi/features/cycani/catalog_danmaku_source_settings.dart';
import 'package:kazumi/features/cycani/catalog_danmaku_loader.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_settings.dart';
import 'package:kazumi/pages/settings/settings_page.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'cycani_api_test.dart' show FakeAdapter;

class TestPaths extends PathProviderPlatform {
  TestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class NoDownloads implements DownloadController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DanmakuEntry item(String source, double time) => DanmakuEntry(
  message: source,
  time: time,
  type: 1,
  color: const Color(0xFFFFFFFF),
  source: source,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform originalPaths;
  setUpAll(() async {
    Logger.level = Level.off;
    temp = await Directory.systemTemp.createTemp('cycani-merged-settings-');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = TestPaths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  setUp(() async {
    await GStorage.resetDanmakuSettings();
    DioFactory.reset();
  });
  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    await temp.delete(recursive: true);
  });
  test(
    'three sources default on, persist independently and reset with native options',
    () async {
      expect(
        GStorage.getSetting<bool>(SettingsKeys.danmakuEnabledByDefault),
        true,
      );
      final defaults = CatalogDanmakuOptions.read();
      expect(defaults.giri, isTrue);
      expect(defaults.giriExternal, isTrue);
      expect(
        [defaults.external, defaults.xifan, defaults.cycani],
        [true, true, true],
      );
      await GStorage.putSetting(SettingsKeys.danmakuSourceXifan, false);
      final changed = CatalogDanmakuOptions.read();
      expect(
        [changed.external, changed.xifan, changed.cycani],
        [true, false, true],
      );
      await GStorage.putSetting(SettingsKeys.danmakuSourceGiri, false);
      await GStorage.putSetting(SettingsKeys.danmakuSourceGiriExternal, false);
      expect(CatalogDanmakuOptions.read().giri, isFalse);
      expect(CatalogDanmakuOptions.read().giriExternal, isFalse);
      await GStorage.resetDanmakuSettings();
      expect(CatalogDanmakuOptions.read().giri, isTrue);
      expect(CatalogDanmakuOptions.read().giriExternal, isTrue);
      expect(CatalogDanmakuOptions.read().xifan, true);
      for (final source in [
        CatalogDanmakuOptions.externalSource,
        CatalogDanmakuOptions.xifanSource,
        CatalogDanmakuOptions.cycaniSource,
      ])
        expect(CatalogDanmakuOptions.managed(source), true);
    },
  );
  testWidgets(
    'one source group, five switches, persisted changes notify reload',
    (tester) async {
      var changed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogDanmakuSourceSettings(onChanged: () => changed++),
          ),
        ),
      );
      expect(find.text('外部聚合'), findsOneWidget);
      expect(find.text('稀饭站内'), findsOneWidget);
      expect(find.text('次元城站内'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(5));
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).every((s) => s.value),
        true,
      );
      final tile = find.byKey(ValueKey(SettingsKeys.danmakuSourceXifan.name));
      await tester.runAsync(() async {
        await tester.tap(
          find.descendant(of: tile, matching: find.byType(Switch)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(CatalogDanmakuOptions.read().xifan, false);
      expect(changed, 1);
      await tester.runAsync(GStorage.resetDanmakuSettings);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Switch>(
              find.descendant(of: tile, matching: find.byType(Switch)),
            )
            .value,
        true,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'native danmaku page contains new source section without legacy provider filters',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DanmakuSettingsPage()));
      await tester.pumpAndSettle();
      expect(find.text('弹幕来源'), findsOneWidget);
      expect(find.text('外部聚合'), findsOneWidget);
      expect(find.text('稀饭站内'), findsOneWidget);
      expect(find.text('次元城站内'), findsOneWidget);
      expect(find.text('BiliBili'), findsNothing);
      expect(find.text('Gamer'), findsNothing);
      expect(find.text('弹弹play'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('settings index has a single combined danmaku entry', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsIndexPage()));
    await tester.pumpAndSettle();
    expect(find.text('弹幕设置'), findsOneWidget);
    expect(find.text('站内弹幕'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'combined data enters the unchanged native timeline with all source labels',
    () async {
      final result = await CatalogDanmakuLoader.loadCombined(
        options: const CatalogDanmakuOptions(),
        loadExternal: () async => [
          item(CatalogDanmakuOptions.externalSource, 1.1),
        ],
        loadXifan: () async => [item(CatalogDanmakuOptions.xifanSource, 2.2)],
        loadCycani: () async => [item(CatalogDanmakuOptions.cycaniSource, 3.3)],
      );
      final player = PlayerDanmakuController(
        isLocalPlayback: () => false,
        downloadController: NoDownloads(),
      );
      player.applyDanmakuLoad(result, enableDanmaku: true);
      expect(player.danmakuOn, true);
      expect(player.danDanmakus.keys.toSet(), {1, 2, 3});
      expect(
        player
            .danmakusForPlaybackPosition(const Duration(milliseconds: 2200))
            .single
            .source,
        CatalogDanmakuOptions.xifanSource,
      );
    },
  );
  test(
    'manual external choice preserves both site feeds and sends no credentials',
    () async {
      DioFactory.apiDio.httpClientAdapter.close();
      DioFactory.apiDio.httpClientAdapter = FakeAdapter((r) async {
        expect(r.uri.host, 'ext-danmaku.moedot.net');
        expect(r.path, contains('/api/v2/comment/91234'));
        for (final key in r.headers.keys)
          expect(
            [
              'authorization',
              'cookie',
              'x-appid',
              'x-appsecret',
              'x-signature',
            ].contains(key.toLowerCase()),
            false,
          );
        return ResponseBody.fromString(
          jsonEncode({
            'comments': [
              {'m': 'new external', 'p': '4.5,1,16777215,hash'},
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      final player = PlayerDanmakuController(
        isLocalPlayback: () => false,
        downloadController: NoDownloads(),
      );
      player.addDanmakus([
        item(CatalogDanmakuOptions.externalSource, 1),
        item(CatalogDanmakuOptions.xifanSource, 2),
        item(CatalogDanmakuOptions.cycaniSource, 3),
      ]);
      expect(await player.getDanDanmakuByEpisodeID(91234), true);
      final rows = player.danDanmakus.values.expand((e) => e).toList();
      expect(rows.length, 3);
      expect(rows.any((e) => e.message == 'new external'), true);
      expect(
        rows.any((e) => e.message == CatalogDanmakuOptions.externalSource),
        false,
      );
      expect(rows.map((e) => e.source).toSet(), {
        CatalogDanmakuOptions.externalSource,
        CatalogDanmakuOptions.xifanSource,
        CatalogDanmakuOptions.cycaniSource,
      });
    },
  );
  test(
    'manual external failure retains the complete existing timeline',
    () async {
      DioFactory.apiDio.httpClientAdapter.close();
      DioFactory.apiDio.httpClientAdapter = FakeAdapter(
        (_) async => ResponseBody.fromString('{}', 503),
      );
      final player = PlayerDanmakuController(
        isLocalPlayback: () => false,
        downloadController: NoDownloads(),
      );
      player.addDanmakus([
        item(CatalogDanmakuOptions.externalSource, 1),
        item(CatalogDanmakuOptions.xifanSource, 2),
        item(CatalogDanmakuOptions.cycaniSource, 3),
      ]);
      await expectLater(
        player.getDanDanmakuByEpisodeID(91234),
        throwsA(anything),
      );
      expect(player.danDanmakus.values.expand((e) => e).length, 3);
      expect(player.danmakuLoading, false);
    },
  );
}
