import 'catalog_snapshot.dart';
import 'catalog_plugins.dart';
import 'catalog_library_widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:kazumi/services/network/proxy_aware_image_cache_manager.dart';
import 'catalog_disk_cache.dart';
import 'site_accounts.dart';
import 'package:window_manager/window_manager.dart' show windowManager;
import 'package:kazumi/utils/device.dart' show isDesktop;
import 'catalog_aggregator.dart';
import 'catalog_detail_page.dart';
import 'catalog_week_selector.dart';
import 'catalog_paging.dart';
import 'catalog_feed_widgets.dart';
import 'package:kazumi/bean/card/bangumi_timeline_card.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart';
import 'qingyue_my_page.dart';
import 'catalog_search_page.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/widget/collect_layout_switch.dart';
import 'package:kazumi/modules/collect/collect_layout.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/sync/danmaku_shield_sync_service.dart';
import 'cycani_api.dart';
import 'catalog_library.dart';
import 'catalog_models.dart';
import 'cycani_account_page.dart';

Plugin cycaniPlugin() => catalogPlugin(CatalogSource.cycani);

class QingyueBootstrap extends StatefulWidget {
  const QingyueBootstrap({super.key});
  @override
  State<QingyueBootstrap> createState() => _QingyueBootstrapState();
}

class _QingyueBootstrapState extends State<QingyueBootstrap> {
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await Future.wait([
        CycaniApi.instance.restore(),
        SourceAccounts.instance.restoreSnapshots(),
      ]);
      final plugins = inject<PluginsController>();
      await plugins.init();
      for (final source in CatalogSource.siteSources) {
        await plugins.updatePlugin(catalogPlugin(source));
      }
      await inject<ShaderAssetService>().copyShadersToExternalDirectory();
      await inject<DownloadController>().init();
      await inject<MyController>().loadShieldList();
      inject<DanmakuShieldSyncService>().start();
      if (mounted) context.navigate('/home');
    } catch (_) {
      if (mounted) setState(() => error = '加载失败');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: error == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/logo/cycani.png',
                  width: 64,
                  height: 64,
                ),
                SizedBox(height: 24),

                SizedBox(height: 20),
                CircularProgressIndicator(),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error!),
                FilledButton(
                  onPressed: () {
                    setState(() => error = null);
                    unawaited(_initialize());
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
    ),
  );
}

class QingyueHomePage extends StatefulWidget {
  const QingyueHomePage({
    super.key,
    this.initialSection = 0,
    this.standalone = false,
    this.api,
  });
  final int initialSection;
  final bool standalone;
  final CycaniApi? api;
  @override
  State<QingyueHomePage> createState() => _QingyueHomePageState();
}

class _QingyueHomePageState extends State<QingyueHomePage> {
  CycaniApi get api => widget.api ?? CycaniApi.instance;
  final search = TextEditingController(),
      librarySearch = TextEditingController();
  final _scrollStorage = PageStorageBucket();
  final scroll = ScrollController();
  final selected = <String>{};
  late Future<dynamic> future;
  late CatalogFeed feed;
  final _feedLibraryRevisions = <CatalogFeed, int>{};
  final _feeds = <Object, CatalogFeed>{};
  final _views = <Object, Future<List<CatalogJson>>>{};
  final _lastViews = <Object, List<CatalogJson>>{};
  Future<List<CatalogJson>>? _accountHomeSections;
  Object get _viewKey => tab == 3
      ? (tab, weekday, weeklyBangumi)
      : (
          tab,
          activeSource,
          tab == 2
              ? (activeSource == CatalogSource.giri ? giriRank : rankSection)
              : '',
        );

  CatalogFeed _newFeed() => CatalogFeed(
    _page,
    keyOf: (v) => CatalogVideo(v['video'] is Map ? catalogMap(v['video']) : v).id,
  );

  CancelToken? cancel;
  int tab = 0, weekday = DateTime.now().weekday, myRevision = 0;
  late int epoch;
  int? zone = 1;
  String keyword = '',
      order = 'update_time',
      category = '',
      rankSection = 'TV番组';
  String? tag, year;
  List<CatalogJson> zones = [], ranks = [], giriRanks = [];
  int? giriRank;
  final weekCounts = List<int?>.filled(7, null);
  final weekEpochs = List<int>.filled(7, 0);
  final weekData = <int, Future<List<CatalogJson>>>{};
  // 周表数据源模式：false = 三站聚合（默认），true = Bangumi 每日放送。
  bool weeklyBangumi = false;
  bool selectionMode = false, listMode = true;
  bool weekGridMode = false;
  static const labels = ['主页', '分类', '排行榜', '周表', '我的追番', '观看历史', '登录', '我的'];
  static const navigation = [0, 1, 2, 3, 7];
  static const icons = [
    Icons.home_outlined,
    Icons.grid_view_outlined,
    Icons.leaderboard_outlined,
    Icons.calendar_month_outlined,
    Icons.favorite_border,
    Icons.history,
    Icons.account_circle_outlined,
    Icons.person_outline,
  ];
  bool get _giriRankingTab => tab == 2 && activeSource == CatalogSource.giri;
  bool get paged => tab == 1 || tab == 4 || tab == 5 || _giriRankingTab;
  @override
  void initState() {
    super.initState();
    tab = widget.initialSection;
    epoch = api.sessionEpoch;
    feed = _newFeed();
    api.addListener(_sessionChanged);
    future = _load();
    if (!externalSource) unawaited(_filters());
  }

  Future<CatalogPage> _page(int page, String? cursor) async {
    final section = tab;
    final disk = widget.api == null && section == 1 && page == 1
        ? _categoryCacheKey
        : null;
    if (_giriRankingTab) {
      final id = giriRank;
      final catalog = CatalogAggregator.instance;
      var groups = giriRanks;
      if (groups.isEmpty && widget.api == null) {
        groups = await CatalogDiskCache.read('giri-ranking-groups') ?? [];
        if (mounted &&
            activeSource == CatalogSource.giri &&
            groups.isNotEmpty) {
          final cachedGroups = groups;
          setState(() => giriRanks = cachedGroups);
        }
      }
      if (groups.isEmpty || (page == 1 && id == null)) {
        try {
          final fresh = await catalog.giriRankingGroups();
          if (fresh.isNotEmpty) {
            groups = fresh;
            if (widget.api == null) {
              unawaited(CatalogDiskCache.write('giri-ranking-groups', fresh));
            }
            if (mounted &&
                activeSource == CatalogSource.giri &&
                (giriRank == null ||
                    fresh.any((r) => catalogInt(r['id']) == giriRank))) {
              setState(() => giriRanks = fresh);
            }
          }
        } catch (_) {
          if (groups.isEmpty) rethrow;
        }
      }
      final selected =
          id ?? (groups.isEmpty ? null : catalogInt(groups.first['id']));
      if (selected == null) return const CatalogPage([], hasMore: false);
      final result = await catalog.giriRankingPage(selected, page);
      if (page == 1 && widget.api == null) {
        unawaited(
          CatalogDiskCache.write('giri-ranking:$selected', result.items),
        );
        if (id == null) {
          unawaited(CatalogDiskCache.write('giri-ranking:null', result.items));
        }
      }
      return result;
    }
    if (section == 1 && externalSource) {
      final value = await CatalogAggregator.instance.browse(
        activeSource,
        page,
        kind: sourceKind,
        finished: _sourceFilters['finished'],
        genre: _sourceFilters['genre'],
        area: _sourceFilters['area'],
        version: _sourceFilters['version'],
        state: _sourceFilters['state'],
        year: year,
        order: order,
        cancelToken: cancel,
      );
      if (disk != null) unawaited(CatalogDiskCache.write(disk, value.items));
      return value;
    }
    if (section == 4 || section == 5) {
      // One merged library across every signed-in site; writes route per row.
      final entries = await CatalogLibrarySource().load(
        history: section == 5,
        category: category,
        api: widget.api,
      );
      return CatalogPage(
        [
          for (final entry in entries)
            {
              ...entry.toRow(),
              'entry': entry,
              'progress': catalogInt(entry.raw['progress']),
            },
        ],
        hasMore: false,
      );
    }
    final data = await api.videos(
      page: page,
      zone: zone,
      tag: tag,
      year: year,
      order: order,
      cancelToken: cancel,
    );
    final value = CatalogPage.fromJson(data, page: page);
    if (disk != null) unawaited(CatalogDiskCache.write(disk, value.items));
    return value;
  }

  Future<void> _filters() async {
    try {
      final values = await Future.wait([api.zones(), api.ranks()]);
      if (mounted)
        setState(() {
          zones = values[0];
          ranks = values[1];
        });
    } catch (_) {}
  }

  void _sessionChanged() {
    if (!mounted) return;
    if (epoch != api.sessionEpoch) {
      epoch = api.sessionEpoch;
      selected.clear();
      if (!externalSource) _reload(reset: true, refresh: true);
    } else {
      setState(() {});
    }
  }

  CatalogSource activeSource = CatalogSource.cycani;
  String sourceKind = '';
  final _sourceFilters = <String, String>{};
  final _filterSelections =
      <
        CatalogSource,
        (int?, String?, String?, String, String, Map<String, String>)
      >{};
  Map<String, List<String>> _giriOptions = {};
  bool _loadingGiriOptions = false;

  Future<void> _loadGiriOptions() async {
    if (_loadingGiriOptions || _giriOptions.values.any((v) => v.isNotEmpty))
      return;
    _loadingGiriOptions = true;
    final result = await CatalogAggregator.instance.giriBrowseFilters();
    if (mounted)
      setState(() {
        _giriOptions = result;
        _loadingGiriOptions = false;
      });
  }

  bool get externalSource => activeSource != CatalogSource.cycani;
  void _selectSource(CatalogSource source) {
    if (source == activeSource) return;
    _filterSelections[activeSource] = (
      zone,
      tag,
      year,
      sourceKind,
      order,
      Map.of(_sourceFilters),
    );
    activeSource = source;
    if (!externalSource && (zones.isEmpty || ranks.isEmpty))
      unawaited(_filters());
    final saved = _filterSelections[source];
    zone = saved?.$1 ?? 1;
    tag = saved?.$2;
    year = saved?.$3;
    sourceKind = saved?.$4 ?? '';
    order = saved?.$5 ?? 'update_time';
    _sourceFilters
      ..clear()
      ..addAll(saved?.$6 ?? const {});
    _reload(reset: true);
  }

  void _readPublicSnapshot(Object key) {
    if (widget.api != null || _lastViews.containsKey(key)) return;
    unawaited(
      restoreCatalogSnapshot(
        '$key',
        canApply: () => mounted && !_lastViews.containsKey(key),
        apply: (rows) => setState(() => _lastViews[key] = rows),
      ),
    );
  }

  void _rememberPublicSnapshot(Object key, List<CatalogJson> rows) {
    _lastViews[key] = rows;
    if (widget.api == null && rows.isNotEmpty) {
      unawaited(CatalogDiskCache.write('$key', rows));
    }
  }

  String get _categoryCacheKey =>
      'category:${activeSource.name}:$zone:$tag:$year:$order:$sourceKind:$_sourceFilters';

  Future<dynamic> _load({bool refresh = false}) {
    cancel = CancelToken();
    if (tab == 1 && activeSource == CatalogSource.giri)
      unawaited(_loadGiriOptions());
    if (paged) {
      final key = (
        tab,
        activeSource,
        zone,
        tag,
        year,
        order,
        sourceKind,
        _sourceFilters.toString(),
        category,
        api.sessionEpoch,
        _giriRankingTab ? giriRank : null,
      );
      feed = _feeds.putIfAbsent(key, _newFeed);
      if (tab == 4 || tab == 5) {
        final revision = api.libraryRevision(tab);
        final old = _feedLibraryRevisions[feed];
        _feedLibraryRevisions[feed] = revision;
        if (old != null && old != revision && feed.page > 0)
          return feed.refresh();
      }

      if (refresh && feed.page > 0) return feed.refresh();
      if (feed.page == 0 && !feed.loading) {
        if ((tab == 4 || tab == 5) && widget.api == null && api.loggedIn) {
          final target = feed, epoch = api.sessionEpoch;
          unawaited(
            api.readLibrarySnapshot(tab, category).then((rows) {
              if (mounted && epoch == api.sessionEpoch && rows != null)
                target.showCached(rows);
            }),
          );
          return target.refresh();
        }

        if ((tab == 1 || _giriRankingTab) && widget.api == null) {
          final target = feed;
          final key = _giriRankingTab
              ? 'giri-ranking:$giriRank'
              : _categoryCacheKey;
          unawaited(
            CatalogDiskCache.read(key).then((rows) {
              if (mounted && rows != null && target.loading)
                target.showCached(rows);
            }),
          );
          return target.refresh();
        }
        return feed.reset();
      }
      return Future.value(null);
    }
    if (tab == 3) {
      final key = _viewKey;
      _readPublicSnapshot(key);
      final request = _schedule();
      unawaited(
        request.then<void>(
          (rows) => _rememberPublicSnapshot(key, rows),
          onError: (Object _, StackTrace __) {},
        ),
      );
      return request;
    }
    if (tab == 0 && activeSource == CatalogSource.giri && widget.api == null) {
      _accountHomeSections = SourceAccounts.instance
          .giriHomeAccountSections()
          .catchError(
            (Object _) => SourceAccounts.instance.cachedGiriHomeAccountSections,
          );
    }
    if (tab != 0 && tab != 2) return Future.value(null);
    final key = _viewKey;
    _readPublicSnapshot(key);
    if (refresh) _views.remove(key);
    return _views.putIfAbsent(key, () {
      final request = tab == 2
          ? _ranking()
          : widget.api == null
          ? CatalogAggregator.instance.recommendations(activeSource)
          : api.recommendations();
      unawaited(
        request.then<void>(
          (rows) {
            if (identical(_views[key], request))
              _rememberPublicSnapshot(key, rows);
          },
          onError: (Object error, StackTrace _) {
            if (identical(_views[key], request)) _views.remove(key);
          },
        ),
      );
      return request;
    });
  }

  Future<List<CatalogJson>> _week(int day) =>
      weekData.putIfAbsent(day, () async {
        final generation = weekEpochs[day - 1];
        final source = activeSource;
        final values = widget.api == null
            ? weeklyBangumi
            ? await CatalogAggregator.instance.bangumiSchedule(day)
            : await CatalogAggregator.instance.mergedSchedule(day)
            : source == CatalogSource.cycani
            ? await api.schedule(day)
            : await CatalogAggregator.instance.schedule(source, day);
        final ids = <int>{};
        for (final group in values) {
          for (final item in catalogList(group['videos'])) {
            ids.add(CatalogVideo(item).id);
          }
        }
        if (mounted && generation == weekEpochs[day - 1])
          setState(() {
            weekCounts[day - 1] = ids.length;
          });
        return values;
      });
  Future<List<CatalogJson>> _schedule() {
    final result = _week(weekday);
    for (var day = 1; day <= 7; day++) {
      if (day != weekday)
        unawaited(_week(day).then((_) {}, onError: (Object _) {}));
    }
    return result;
  }

  Future<List<CatalogJson>> _ranking() async {
    if (activeSource == CatalogSource.bangumi) {
      return CatalogAggregator.instance
          .bangumiRanking(movie: rankSection == '剧场番组');
    }
    if (activeSource == CatalogSource.xifan) {
      return CatalogAggregator.instance.xifanWeeklyRanking();
    }
    return CatalogAggregator(
      cycani: api,
    ).ranking(CatalogSource.cycani, movie: rankSection == '剧场番组');
  }

  void _reload({bool reset = false, bool refresh = false}) {
    if (tab == 3 && refresh) {
      weekEpochs[weekday - 1]++;
      weekData.remove(weekday);
      weekCounts[weekday - 1] = null;
    }
    selected.clear();
    if (tab == 7) myRevision++;
    setState(() {
      future = _load(refresh: refresh);
    });
  }

  void _selectTab(int value) {
    if (tab == value) return;
    tab = value;
    selectionMode = false;
    search.clear();
    librarySearch.clear();
    // Bangumi 目前只接入排行榜（tab 2）：离开该 tab 时回落到默认站点，
    // 避免主页/分类等未接入 bangumi 数据的功能触发未实现分支。
    if (activeSource == CatalogSource.bangumi && value != 2) {
      activeSource = CatalogSource.cycani;
    }
    _reload(reset: true);
  }

  @override
  void dispose() {
    api.removeListener(_sessionChanged);
    cancel?.cancel();
    for (final f in {..._feeds.values, feed}) {
      f.dispose();
    }
    search.dispose();
    librarySearch.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _manage(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) _reload(reset: true, refresh: true);
    } catch (e) {
      if (mounted) catalogToast(context, '$e');
    }
  }

  Widget _filtersBar() {
    final filters = catalogMap(
      (zones.where((z) => catalogInt(z['id']) == zone).firstOrNull ??
          (zones.firstOrNull ?? {}))['filters'],
    );
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (tab == 1 && externalSource) ...[
          _select(
            '类型',
            sourceKind,
            activeSource == CatalogSource.giri
                ? CatalogAggregator.giriKinds
                : CatalogAggregator.xifanKinds,
            (value) {
              sourceKind = value ?? '';
              _reload(reset: true);
            },
          ),
          _select<String?>(
            '年份',
            year,
            {
              null: '全部年份',
              if (activeSource == CatalogSource.giri)
                for (final y in _giriOptions['year'] ?? const <String>[]) y: y
              else ...{
                for (var y = DateTime.now().year; y >= 2007; y--) '$y': '$y',
                'older': '更早',
              },
            },
            (value) {
              year = value;
              _reload(reset: true);
            },
          ),
          for (final (key, label, options) in [
            if (activeSource == CatalogSource.xifan) ...[
              ('finished', '状态', {'0': '连载中', '1': '完结'}),
              (
                'genre',
                '题材',
                {for (final item in CatalogAggregator.xifanTags) item: item},
              ),
            ] else
              for (final (key, label) in [
                ('genre', '题材'),
                ('area', '季度'),
                ('version', '形式'),
                ('state', '改编来源'),
              ])
                (
                  key,
                  label,
                  {
                    for (final item in _giriOptions[key] ?? const <String>[])
                      item: item,
                  },
                ),
          ])
            if (options.isNotEmpty)
              _select<String?>(
                label,
                _sourceFilters[key],
                {null: '全部$label', ...options},
                (v) {
                  if (v == null) {
                    _sourceFilters.remove(key);
                  } else {
                    _sourceFilters[key] = v;
                  }
                  _reload(reset: true);
                },
              ),
          _select(
            '排序',
            order,
            {
              'update_time': '最近更新',
              'hits': '最多观看',
              'score': '评分',
              if (activeSource == CatalogSource.xifan) 'release_date': '最新发布',
            },
            (value) {
              order = value ?? 'update_time';
              _reload(reset: true);
            },
          ),
        ],
        if (tab == 1 && !externalSource) ...[
          _select<int?>(
            '频道',
            zone,
            {
              if (keyword.isNotEmpty) null: '全部频道',
              for (final z in zones) catalogInt(z['id']): '${z['name']}',
            },
            (v) {
              zone = v;
              tag = null;
              year = null;
              _reload(reset: true);
            },
          ),
          _select<String?>(
            '类型',
            tag,
            {
              null: '全部类型',
              for (final t in (filters['categories'] as List? ?? []))
                '$t': '$t',
            },
            (v) {
              tag = v;
              _reload(reset: true);
            },
          ),
          _select<String?>(
            '年份',
            year,
            {
              null: '全部年份',
              for (final y in (filters['years'] as List? ?? [])) '$y': '$y',
            },
            (v) {
              year = v;
              _reload(reset: true);
            },
          ),
          _select(
            '排序',
            order,
            {'update_time': '最近更新', 'hits': '最多观看', 'score': '评分'},
            (v) {
              order = v!;
              _reload(reset: true);
            },
          ),
        ],
        if (tab == 2 && activeSource == CatalogSource.xifan)
          const Chip(label: Text('周热榜')),
        if (tab == 2 &&
            activeSource == CatalogSource.giri &&
            giriRanks.isNotEmpty)
          _select<int>(
            '榜单',
            giriRank ?? catalogInt(giriRanks.first['id']),
            {
              for (final row in giriRanks)
                catalogInt(row['id']): row['title'].toString(),
            },
            (id) {
              giriRank = id;
              _reload(reset: true);
            },
          ),
        if (tab == 2 && activeSource == CatalogSource.cycani)
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'TV番组', label: Text('TV 番组')),
              ButtonSegment(value: '剧场番组', label: Text('剧场番组')),
            ],
            selected: {rankSection},
            onSelectionChanged: (v) {
              rankSection = v.single;
              _reload(reset: true);
            },
          ),
        if (tab == 3) ...[
          // 周表数据源切换：三站聚合（默认）/ Bangumi 每日放送。
          if (widget.api == null)
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  showCheckmark: false,
                  label: const Text('三站聚合'),
                  selected: !weeklyBangumi,
                  onSelected: (_) {
                    if (!weeklyBangumi) return;
                    setState(() {
                      weeklyBangumi = false;
                      weekData.clear();
                      for (var i = 0; i < weekEpochs.length; i++) {
                        weekEpochs[i]++;
                        weekCounts[i] = null;
                      }
                    });
                    _reload(reset: true);
                  },
                ),
                ChoiceChip(
                  showCheckmark: false,
                  label: const Text('Bangumi'),
                  selected: weeklyBangumi,
                  onSelected: (_) {
                    if (weeklyBangumi) return;
                    setState(() {
                      weeklyBangumi = true;
                      weekData.clear();
                      for (var i = 0; i < weekEpochs.length; i++) {
                        weekEpochs[i]++;
                        weekCounts[i] = null;
                      }
                    });
                    _reload(reset: true);
                  },
                ),
              ],
            ),
          SizedBox(
            width: double.infinity,
            child: DefaultTabController(
              length: 7,
              initialIndex: weekday - 1,
              child: CatalogWeekSelector(
                counts: weekCounts,
                todayIndex: DateTime.now().weekday - 1,
                onChanged: (index) {
                  weekday = index + 1;
                  _reload(reset: true);
                },
              ),
            ),
          ),
        ],
        if (tab == 4)
          for (final e in {
            '': '全部',
            'watching': '在看',
            'want': '想看',
            'watched': '看过',
          }.entries)
            ChoiceChip(
              showCheckmark: false,
              label: Text(e.value),
              selected: category == e.key,
              onSelected: (_) {
                category = e.key;
                _reload(reset: true);
              },
            ),
        if (tab == 4 || tab == 5) ...[
          FilterChip(
            label: Text(selectionMode ? '已选 ${selected.length}' : '批量管理'),
            selected: selectionMode,
            onSelected: (v) => setState(() {
              selectionMode = v;
              selected.clear();
            }),
          ),
          if (selected.isNotEmpty && tab == 4)
            PopupMenuButton<int>(
              tooltip: '修改追番状态',
              onSelected: (v) => _manage(() async {
                for (final entry in _selectedEntries()) {
                  await CatalogLibrarySource.writeFollow(entry, v);
                }
              }),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 1, child: Text('正在追')),
                PopupMenuItem(value: 2, child: Text('准备追')),
                PopupMenuItem(value: 3, child: Text('已追完')),
              ],
              child: const Chip(label: Text('移动已选')),
            ),
          if (selected.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除已选'),
              onPressed: () async {
                if (await catalogConfirm(context, '删除所选记录？')) {
                  await _manage(() async {
                    for (final entry in _selectedEntries()) {
                      if (tab == 4) {
                        await CatalogLibrarySource.writeFollow(entry, null);
                      } else {
                        await CatalogLibrarySource.deleteHistory(entry);
                      }
                    }
                  });
                }
              },
            ),
          if (tab == 5)
            TextButton(
              onPressed: () async {
                if (await catalogConfirm(context, '清空次元城服务器上的全部观看历史？')) {
                  await _manage(api.clearHistories);
                }
              },
              child: const Text('清空次元城历史'),
            ),
        ],
      ],
    );
  }

  Widget _select<T>(
    String label,
    T value,
    Map<T, String> options,
    ValueChanged<T?> changed,
  ) => DropdownButton<T>(
    value: options.containsKey(value) ? value : null,
    hint: Text(label),
    borderRadius: BorderRadius.circular(16),
    items: options.entries
        .map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
        .toList(),
    onChanged: changed,
  );

  List<CatalogLibraryEntry> _selectedEntries() => [
    for (final row in feed.items)
      if (row['entry'] case final CatalogLibraryEntry entry
          when selected.contains(entry.identity))
        entry,
  ];

  Widget _tile(List<CatalogJson> items, int i) {
    final entry = items[i]['entry'] as CatalogLibraryEntry?;
    final raw = items[i],
        video = CatalogVideo(
          items[i]['video'] is Map ? catalogMap(items[i]['video']) : items[i],
        );
    void open() {
      if (entry != null) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => CatalogDetailPage(row: raw)),
        );
        return;
      }
      if (video.id <= 0) return;
      if (widget.api == null && tab <= 3) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => CatalogDetailPage(row: raw)),
        );
      } else {
        context.pushNamed('/qingyue/detail', arguments: video.id);
      }
    }

    final selectKey = entry?.identity ?? 'bgm:${video.id}';
    final score = double.tryParse('${raw['score']}') ?? 0;
    return Stack(
      children: [
        Positioned.fill(
          child: ((tab == 4 || tab == 5) && listMode)
              ? BangumiTimelineCard(
                  bangumiItem: video.toBangumi(),
                  showRating: true,
                  onTap: open,
                )
              : BangumiCardV(
                  bangumiItem: video.toBangumi(),
                  enableHero: false,
                  onTap: open,
                ),
        ),
        if (selectionMode)
          Positioned(
            top: 4,
            left: 4,
            child: Checkbox.adaptive(
              value: selected.contains(selectKey),
              onChanged: (v) => setState(() {
                v == true ? selected.add(selectKey) : selected.remove(selectKey);
              }),
            ),
          ),
        if (score > 0 && !((tab == 4 || tab == 5) && listMode))
          Positioned(top: 4, right: 4, child: RatingBadge(score: score)),
        if (tab == 4 && entry != null)
          Positioned(
            bottom: 8,
            left: 8,
            child: Chip(label: Text(entry.source.label)),
          ),
        if (tab == 5 && (entry?.subtitle != null || catalogInt(raw['progress']) > 0))
          Positioned(
            bottom: 8,
            right: 8,
            child: Chip(
              label: Text(
                entry?.subtitle ??
                    '${raw['section_title'] ?? ''} · ${catalogInt(raw['progress']) ~/ 60000} 分钟',
              ),
            ),
          ),
      ],
    );
  }

  Widget _homeBanners(List<CatalogJson> rows) => SizedBox(
    height: 184,
    child: PageView.builder(
      key: PageStorageKey('home-banners-$activeSource'),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index], video = CatalogVideo(rows[index]);
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CatalogDetailPage(row: row),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  cacheManager: ProxyAwareImageCacheManager.instance,
                  imageUrl: video.cover,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox(),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    color: Colors.black54,
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      video.title,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _accountHomeRows() => _accountHomeSection('追番更新', heading: true);
  Widget _personalizedSliver(List<CatalogJson> fallback) =>
      _accountHomeSection('为你推荐', fallback: fallback);
  Widget _accountHomeSection(
    String title, {
    List<CatalogJson> fallback = const [],
    bool heading = false,
  }) => FutureBuilder<List<CatalogJson>>(
    key: ValueKey((title, SourceAccounts.instance.librarySession(true))),
    initialData: SourceAccounts.instance.cachedGiriHomeAccountSections,
    future: _accountHomeSections,
    builder: (context, snapshot) {
      final group = snapshot.data
          ?.where((row) => row['name'] == title)
          .firstOrNull;
      final rows = group == null ? fallback : catalogList(group['videos']);
      return SliverMainAxisGroup(
        slivers: [
          if (heading && rows.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
          CatalogVideoSliver(items: rows),
        ],
      );
    },
  );

  List<Widget> _slivers(dynamic value) {
    final items = paged ? feed.items : catalogList(value);
    if (tab == 0 || tab == 3)
      return [
        if (tab == 0 && activeSource == CatalogSource.giri) _accountHomeRows(),
        for (final group in items) ...[
          if ('${group['name'] ?? labels[tab]}'.trim().isNotEmpty &&
              '${group['name'] ?? labels[tab]}'.trim() != labels[tab])
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${group['name'] ?? labels[tab]}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (tab == 0 &&
                        activeSource == CatalogSource.cycani &&
                        catalogInt(group['zone_id']) > 0)
                      TextButton(
                        onPressed: () {
                          zone = catalogInt(group['zone_id']);
                          tag = null;
                          _selectTab(1);
                        },
                        child: const Text('查看更多'),
                      ),
                  ],
                ),
              ),
            ),
          if (group['layout'] == 'text')
            SliverToBoxAdapter(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('${group['text'] ?? ''}'),
                ),
              ),
            )
          else if (group['layout'] == 'hero')
            SliverToBoxAdapter(child: _homeBanners(catalogList(group['videos'])))
          else if (group['layout'] == 'personalized')
            _personalizedSliver(catalogList(group['videos']))
          else
            CatalogVideoSliver(
              items: catalogList(group['videos']),
              horizontal: tab == 3 && !weekGridMode,
              tileBuilder: tab == 3 && weekGridMode
                  ? (context, i) =>
                        _tile(catalogList(group['videos']), i)
                  : null,
            ),
        ],
        if (items.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('暂无内容')),
          ),
      ];
    final shown = (tab == 4 || tab == 5) && librarySearch.text.trim().isNotEmpty
        ? items
              .where(
                (e) => (e['entry'] as CatalogLibraryEntry?)
                    ?.title
                    .toLowerCase()
                    .contains(librarySearch.text.trim().toLowerCase()) ??
                    CatalogVideo(e['video'] is Map ? catalogMap(e['video']) : e)
                        .title
                        .toLowerCase()
                        .contains(librarySearch.text.trim().toLowerCase()),
              )
              .toList()
        : items;
    return [
      if (shown.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: Text('暂无内容')),
          ),
        ),
      CatalogVideoSliver(
        items: shown,
        horizontal: (tab == 4 || tab == 5) && listMode,
        tileBuilder: (context, i) => _tile(shown, i),
      ),
      if (paged) SliverToBoxAdapter(child: CatalogFeedLoadMore(feed: feed)),
    ];
  }

  Widget _scroll(dynamic value) => PageStorage(
    bucket: _scrollStorage,
    child: RefreshIndicator(
      onRefresh: () async {
        _reload(reset: true, refresh: true);
        await future;
      },
      child: CustomScrollView(
        key: PageStorageKey<Object>(paged ? feed : _viewKey),
        controller: scroll,
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: _slivers(value),
      ),
    ),
  );
  Widget _body() => paged
      ? AnimatedBuilder(
          animation: feed,
          builder: (context, _) {
            if (feed.page == 0 && feed.loading && feed.items.isEmpty)
              return const Center(child: CircularProgressIndicator());
            if (feed.page == 0 && feed.error != null && feed.items.isEmpty)
              return CatalogError(
                error: feed.error!,
                retry: feed.loadMore,
                login: _login,
              );
            return _scroll(null);
          },
        )
      : FutureBuilder<dynamic>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done ||
                snapshot.hasError) {
              final previous = _lastViews[_viewKey];
              if (previous != null) return _scroll(previous);
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
            }
            if (snapshot.hasError)
              return CatalogError(
                error: snapshot.error!,
                retry: () => _reload(refresh: true),
                login: _login,
              );
            return _scroll(snapshot.data);
          },
        );
  Future<void> _openSearch([String value = '']) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CatalogSearchPage(initialKeyword: value, api: widget.api),
      ),
    );
  }

  Future<void> _openLibrary(int section) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            QingyueHomePage(initialSection: section, standalone: true, api: api),
      ),
    );
    if (mounted && tab == 7) _reload();
  }

  Future<void> _login() async {
    if (externalSource) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SourceAccountsPage(
            initialGiri: activeSource == CatalogSource.giri,
          ),
        ),
      );
      if (mounted) _reload();
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CycaniAccountPage()));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700,
        colors = Theme.of(context).colorScheme;
    final index = navigation.indexOf(tab).clamp(0, 4);
    final content = Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        toolbarHeight: 80,
        automaticallyImplyLeading: widget.standalone,
        scrolledUnderElevation: 0,
        title: DragToMoveArea(
          child:
              navigation.contains(tab) &&
                  !widget.standalone &&
                  tab != 3 &&
                  widget.api == null
              ? PopupMenuButton<CatalogSource>(
                  tooltip: '切换站点',
                  initialValue: activeSource,
                  onSelected: _selectSource,
                  itemBuilder: (_) => [
                    for (final source in CatalogSource.siteSources)
                      PopupMenuItem(value: source, child: Text(source.label)),
                    // Bangumi 暂只接入排行榜数据（tab 2），其他 tab 不提供入口。
                    if (tab == 2)
                      const PopupMenuItem(
                        value: CatalogSource.bangumi,
                        child: Text('Bangumi'),
                      ),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tab == 0
                            ? activeSource.label
                            : '${labels[tab]} · ${activeSource.label}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.keyboard_arrow_down),
                    ],
                  ),
                )
              : Text(
                  labels[tab],
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        actions: [
          if (tab == 3)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: CollectLayoutSwitch(
                value:
                    weekGridMode ? CollectLayout.cards : CollectLayout.list,
                onChanged: (layout) =>
                    setState(() => weekGridMode = layout == CollectLayout.cards),
              ),
            ),
          if (!wide && !widget.standalone)
            IconButton(
              tooltip: '搜索',
              onPressed: _openSearch,
              icon: const Icon(Icons.search),
            ),
          if (tab == 7)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                onPressed: () => context.pushNamed('/settings/'),
                icon: const Icon(Icons.tune),
                label: const Text('设置'),
              ),
            ),
          if (isDesktop())
            IconButton(
              tooltip: '退出',
              onPressed: () => windowManager.close(),
              icon: const Icon(Icons.close),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: tab == 7
          ? QingyueMyPage(
              key: ValueKey('my-$activeSource-$epoch-$myRevision'),
              source: activeSource,
              api: api,
              openLibrary: _openLibrary,
              openDownloads: () => context.pushNamed('/settings/download/'),
            )
          : Padding(
              padding: EdgeInsets.fromLTRB(
                wide ? 24 : 16,
                0,
                wide ? 24 : 16,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (tab != 0) ...[_filtersBar(), const SizedBox(height: 16)],
                  if (tab == 4 || tab == 5) ...[
                    CatalogLibraryToolbar(
                      search: librarySearch,
                      listMode: listMode,
                      onSearch: (_) => setState(() {}),
                      onView: (value) => setState(() => listMode = value),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Expanded(child: _body()),
                ],
              ),
            ),
      floatingActionButton: tab == 7
          ? null
          : FloatingActionButton.small(
              heroTag: null,
              tooltip: '返回顶部',
              onPressed: () {
                if (scroll.hasClients)
                  scroll.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
              },
              child: const Icon(Icons.arrow_upward),
            ),
    );
    if (widget.standalone) return content;
    return Scaffold(
      backgroundColor: colors.surfaceContainer,
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              backgroundColor: colors.surfaceContainer,
              groupAlignment: 1,
              labelType: NavigationRailLabelType.all,
              selectedIndex: index,
              leading: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FloatingActionButton(
                  elevation: 0,
                  heroTag: null,
                  tooltip: '搜索',
                  onPressed: _openSearch,
                  child: const Icon(Icons.search),
                ),
              ),
              onDestinationSelected: (i) => _selectTab(navigation[i]),
              destinations: [
                for (final i in navigation)
                  NavigationRailDestination(
                    icon: Icon(icons[i]),
                    label: Text(labels[i]),
                  ),
              ],
            ),
          Expanded(
            child: ClipRRect(
              borderRadius: wide
                  ? const BorderRadius.horizontal(left: Radius.circular(20))
                  : BorderRadius.zero,
              child: content,
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => _selectTab(navigation[i]),
              destinations: [
                for (final i in navigation)
                  NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
              ],
            ),
    );
  }
}

class CatalogError extends StatelessWidget {
  const CatalogError({
    super.key,
    required this.error,
    required this.retry,
    this.login,
  });
  final Object error;
  final VoidCallback retry;
  final VoidCallback? login;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 16),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(onPressed: retry, child: const Text('重试')),
              if (login != null &&
                  error is CycaniException &&
                  (error as CycaniException).code == 401)
                FilledButton(onPressed: login, child: const Text('登录账户')),
            ],
          ),
        ],
      ),
    ),
  );
}

void catalogToast(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
Future<bool> catalogConfirm(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;
