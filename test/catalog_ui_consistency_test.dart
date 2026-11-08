import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/catalog_account_layout.dart';
import 'package:kazumi/features/cycani/catalog_detail_metadata.dart';
import 'package:kazumi/features/cycani/cycani_detail_page.dart';
import 'package:kazumi/features/cycani/catalog_models.dart';
import 'package:kazumi/features/cycani/site_accounts.dart';

class _WarmLibrary extends SourceAccounts {
  final pending = Completer<(List<CatalogJson>, bool)>();
  @override
  CatalogJson? profileSnapshot(bool giri) => {
    'id': 'owner',
    'nickname': '已缓存用户',
  };
  @override
  Future<CatalogJson?> cachedProfile(bool giri) async => profileSnapshot(giri);
  @override
  Future<List<CatalogJson>?> cachedLibrary(bool giri, int library) async => [
    {'anime_id': 19, 'anime_title': '缓存番剧', 'episode_number': 1},
  ];
  @override
  Future<bool> hasSession(bool giri) async => true;
  @override
  Future<(List<CatalogJson>, bool)> libraryPage(
    bool giri, {
    required bool history,
    required int page,
  }) => pending.future;
  @override
  Future<void> saveLibrary(
    bool giri,
    int library,
    List<CatalogJson> rows, {
    int? expectedSession,
  }) async {}
}

class _ManagedLibrary extends _WarmLibrary {
  final writes = <(int, int?)>[];
  bool failSecond = false;
  List<CatalogJson> rows = [
    {
      'anime_id': 101,
      'status': 1,
      'animes': {'title': '在看番剧'},
    },
    {
      'anime_id': 102,
      'status': 0,
      'animes': {'title': '想看番剧'},
    },
  ];
  @override
  Future<(List<CatalogJson>, bool)> libraryPage(
    bool giri, {
    required bool history,
    required int page,
  }) async => (rows, false);
  @override
  Future<void> setXifanFollow(int id, int? status) async {
    if (failSecond && id == 102) throw StateError('fixture failure');
    writes.add((id, status));
  }
}

class _PagedLibrary extends _WarmLibrary {
  final calls = <int>[];
  Completer<void>? gate;
  @override
  Future<(List<CatalogJson>, bool)> libraryPage(
    bool giri, {
    required bool history,
    required int page,
  }) async {
    calls.add(page);
    await gate?.future;
    return (
      [
        {'anime_id': 100 + page, 'anime_title': '第 $page 页番剧'},
      ],
      page == 1,
    );
  }
}

class _ExpiredLibrary extends _WarmLibrary {
  int epoch = 0;
  @override
  int librarySession(bool giri) => epoch;
  @override
  Future<bool> hasSession(bool giri) async {
    epoch++;
    return false;
  }
}

Widget dashboard(String source) => Scaffold(
  appBar: AppBar(title: Text(source)),
  body: CatalogAccountDashboard(
    header: CatalogProfileHeader(
      avatar: const CircleAvatar(
        radius: 36,
        child: Icon(Icons.person_outline, size: 36),
      ),
      name: '青月用户',
      id: '1024',
      onTap: () {},
    ),
    accountActions: [
      CatalogAccountLink(
        title: '个人资料',
        icon: Icons.person_outline,
        onTap: () {},
      ),
      CatalogAccountLink(
        title: '账户与安全',
        icon: Icons.lock_outline,
        onTap: () {},
      ),
    ],
    libraryActions: [
      CatalogAccountLink(
        title: '我的追番',
        icon: Icons.favorite_border,
        onTap: () {},
      ),
      CatalogAccountLink(title: '观看历史', icon: Icons.history, onTap: () {}),
    ],
    logout: () {},
  ),
);

Widget shell(Widget child, {double scale = 1}) => MaterialApp(
  theme: ThemeData(
    useMaterial3: true,
    fontFamily: 'PreviewSans',
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3c6938)),
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

void main() {
  testWidgets(
    'warm profile still restores disk library before network completes',
    (tester) async {
      final api = _WarmLibrary();
      await tester.pumpWidget(
        MaterialApp(
          home: SourceAccountsPage(
            initialGiri: false,
            library: 5,
            accountApi: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('缓存番剧'), findsWidgets);
      expect(find.text('登录'), findsNothing);
      api.pending.complete((
        [
          {'anime_id': 20, 'anime_title': '更新番剧'},
        ],
        false,
      ));
      await tester.pumpAndSettle();
      expect(find.text('更新番剧'), findsWidgets);
      expect(find.text('缓存番剧'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'library filters persist and batch failures retain only unsuccessful selections',
    (tester) async {
      final api = _ManagedLibrary();
      Widget page() => MaterialApp(
        home: SourceAccountsPage(
          initialGiri: false,
          library: 4,
          accountApi: api,
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '想看'));
      await tester.pumpAndSettle();
      expect(find.text('想看番剧'), findsWidgets);
      expect(find.text('在看番剧'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '想看'))
            .selected,
        isTrue,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('批量管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择当前列表'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2'), findsOneWidget);
      api.failSecond = true;
      await tester.tap(find.text('删除已选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(api.writes, [(101, null)]);
      expect(find.text('已选 1'), findsOneWidget);
      expect(find.text('在看番剧'), findsNothing);
      expect(find.text('想看番剧'), findsWidgets);
      expect(find.text('部分操作失败，请重试'), findsOneWidget);
      api.failSecond = false;
      await tester.tap(find.text('删除已选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(api.writes, [(101, null), (102, null)]);
      expect(find.text('已选 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'library reopening refreshes loaded pages without dropping cached tail',
    (tester) async {
      final api = _PagedLibrary();
      Widget page() => MaterialApp(
        home: SourceAccountsPage(
          initialGiri: false,
          library: 5,
          accountApi: api,
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(api.calls, [1, 2]);
      expect(find.text('第 2 页番剧'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      api.calls.clear();
      api.gate = Completer<void>();
      await tester.pumpWidget(page());
      await tester.pump();
      expect(find.text('第 2 页番剧'), findsWidgets);
      api.gate!.complete();
      await tester.pumpAndSettle();
      expect(api.calls, [1, 2]);
      expect(find.text('第 2 页番剧'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('expired account clears the warm logged-in dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SourceAccountsPage(
          initialGiri: true,
          accountApi: _ExpiredLibrary(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已缓存用户'), findsNothing);
    expect(find.text('使用原视频账号登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [320.0, 420.0, 1280.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('common account/detail layout at $width scale $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final site in ['次元城', '稀饭', 'GiriGiri']) {
          await tester.pumpWidget(shell(dashboard(site), scale: scale));
          await tester.pump();
          expect(find.text('个人资料'), findsOneWidget);
          expect(find.text('账户与安全'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(
          shell(
            const Scaffold(
              body: CatalogDetailScroll(
                children: [
                  CatalogDetailHeader(
                    poster: CatalogPoster(urls: []),
                    metadata: CatalogDetailMetadata(
                      video: CatalogVideo({
                        'title': '很长的番剧标题也应自动换行显示',
                        'subtitle': '别名一,别名二',
                        'year': '2026',
                        'area': '日本',
                        'version': 'TV',
                        'total_episodes': 12,
                        'score': 7.5,
                        'tags': ['喜剧', '日常', 'TV', '喜剧'],
                      }),
                      actions: [
                        FilledButton(onPressed: null, child: Text('开始观看')),
                        OutlinedButton(onPressed: null, child: Text('加入追番')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            scale: scale,
          ),
        );
        await tester.pump();
        expect(find.text('喜剧'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'shared account visual preview',
    // 手工预览截图生成器：仅在显式设置 CATALOG_UI_PREVIEW 时运行，
    // 常规测试套件中显式 skip 而不是空转返回假装通过。
    skip: Platform.environment['CATALOG_UI_PREVIEW'] == null,
    (tester) async {
    final output = Platform.environment['CATALOG_UI_PREVIEW'];
    if (output == null) return;
    await tester.runAsync(() async {
      final loader = FontLoader('PreviewSans')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('assets/fonts/MiSans-Regular.ttf').readAsBytes(),
            ),
          ),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    await tester.binding.setSurfaceSize(const Size(1260, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey();
    await tester.pumpWidget(
      shell(
        RepaintBoundary(
          key: key,
          child: Row(
            children: [
              for (final source in ['次元城', '稀饭', 'GiriGiri'])
                Expanded(child: dashboard(source)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      expect(bytes.length, lessThan(500000));
      await File(output).writeAsBytes(bytes);
      image.dispose();
    });
  });
}
