import 'catalog_action.dart';
import 'qingyue_home_page.dart' show CatalogError;
import 'catalog_detail_metadata.dart';
import 'package:cyanmoon_acg/pages/history/history_controller.dart';
import 'package:cyanmoon_acg/services/storage/storage.dart';
import 'catalog_plugins.dart';
import 'cycani_api.dart';
import 'catalog_identity.dart';
import 'dart:async';
import 'giri_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cyanmoon_acg/pages/video/video_playback_args.dart';
import 'catalog_aggregator.dart';
import 'cycani_detail_page.dart';
import 'catalog_comments.dart';
import 'catalog_models.dart';
import 'site_accounts.dart';
import 'catalog_feed_widgets.dart';
import 'site_native_catalog.dart';

(int, int)? xifanResumeMatch(
  List<String> pages,
  int anime,
  CatalogJson? progress,
) {
  final episode = catalogInt(progress?['episode_id']);
  final milliseconds = catalogInt(progress?['position_ms']);
  if (episode <= 0 || milliseconds <= 0) return null;
  final index = pages.indexWhere(
    (url) => NativeCatalogApi.xifanEpisode(url) == (anime, episode),
  );
  return index < 0 ? null : (index, milliseconds ~/ 1000);
}

(int, int)? giriResumeMatch(int episodes, int road, CatalogJson? progress) {
  if (progress == null || catalogInt(progress['road'], -1) != road) return null;
  final index = catalogInt(progress['episode_index'], -1);
  final position = catalogInt(progress['position_ms']);
  return index < 0 || index >= episodes || position <= 0
      ? null
      : (index, position ~/ 1000);
}

class CatalogDetailPage extends StatefulWidget {
  const CatalogDetailPage({super.key, required this.row});
  final CatalogJson row;
  @override
  State<CatalogDetailPage> createState() => _CatalogDetailPageState();
}

class _CatalogDetailPageState extends State<CatalogDetailPage> {
  late List<CatalogJson> members;
  late CatalogJson selected;
  Future<NativeCatalogDetail>? detail;
  int road = 0;
  bool _openingPlayer = false;
  Future<void>? _discovery;
  int? _follow;
  bool _sourceBusy = false;
  int _followGeneration = 0, _resumeGeneration = 0;
  CatalogJson? _resume;
  NativeCatalogDetail? _cached;
  String? _cachedKey;
  final _visitedDetails = <String, NativeCatalogDetail>{};
  final _selectedRoads = <String, int>{};
  @override
  void initState() {
    super.initState();
    members = catalogList(widget.row['catalog_members']);
    if (members.isEmpty) members = [widget.row];
    selected = members.first;
    _load();
    if (members.length == 1) _discovery = _discover();
  }

  Future<void> _discover() async {
    var entry = widget.row;
    final entryKey = catalogRowKey(entry);
    if ((entry['title'] ?? '').toString().trim().isEmpty) {
      try {
        final source = catalogSource(entry), id = CatalogVideo(entry).id;
        final video = source == CatalogSource.cycani
            ? await CycaniApi.instance.detail(id)
            : (await NativeCatalogApi.instance.detail(source, id)).video;
        entry = {...video.json, 'video_id': id, 'catalog_source': source.name};
      } catch (_) {
        return;
      }
    }
    final candidates = <String>{
      CatalogVideo(entry).title.trim(),
      (entry['title_original'] ?? '').toString().trim(),
      if (entry['aliases'] is List)
        for (final value in (entry['aliases'] as List).whereType<String>())
          value.trim(),
    }..remove('');
    final found = <CatalogJson>[entry];
    var matches = <CatalogJson>[entry];
    // One secondary name is enough to recover translated listings without
    // fanning out every alias to every provider.
    for (final query in candidates.take(2)) {
      if (!mounted || catalogRowKey(widget.row) != entryKey) return;
      try {
        final search = await CatalogAggregator.instance.search(query, 1);
        found.addAll(search.items.where((r) => catalogRowKey(r) != entryKey));
      } catch (_) {
        // Other names can still resolve a source when one search fails.
      }
      final group = mergeCatalogRows(found).firstWhere(
        (r) => catalogList(
          r['catalog_members'],
        ).any((m) => catalogRowKey(m) == entryKey),
      );
      matches = catalogList(group['catalog_members']);
      // 全站点成员齐备时提前收手；Bangumi 暂不作为站点成员参与（S2+ 接入）。
      if (matches.map(catalogSource).toSet().length ==
          CatalogSource.siteSources.length)
        break;
    }
    if (!mounted || catalogRowKey(widget.row) != entryKey) return;
    setState(() => members = matches);
  }

  Future<Map<String, int>> _playbackIds() async {
    final key = catalogRowKey(selected);
    try {
      await _discovery?.timeout(const Duration(seconds: 8));
    } catch (_) {
      // Unavailable matching sites do not block the chosen source's playback.
    }
    if (!mounted || catalogRowKey(selected) != key) return const {};
    return catalogDanmakuIds(members, selected: selected);
  }

  void _load({bool refresh = false}) {
    final source = catalogSource(selected);
    final key = catalogRowKey(selected);
    if (_cachedKey != key) {
      _resume =
          source == CatalogSource.xifan &&
              key == catalogRowKey(widget.row) &&
              widget.row['resume_episode_id'] != null
          ? {
              'episode_id': widget.row['resume_episode_id'],
              'position_ms': widget.row['resume_position_ms'],
            }
          : null;

      _follow = null;
      _cachedKey = key;
      _cached = _visitedDetails[key];
    }
    if (source != CatalogSource.cycani && _cached == null) {
      NativeCatalogApi.instance
          .cachedDetail(source, CatalogVideo(selected).id)
          .then((value) {
            if (mounted &&
                _cachedKey == key &&
                _cached == null &&
                value != null) {
              _visitedDetails[key] = value;
              setState(() => _cached = value);
            }
          });
    }
    detail = source == CatalogSource.cycani
        ? null
        : NativeCatalogApi.instance.detail(
            source,
            CatalogVideo(selected).id,
            refresh: refresh,
          );
    final request = detail;
    if (request != null) {
      unawaited(
        request.then<void>((value) {
          if (!mounted || !identical(detail, request) || _cachedKey != key) {
            return;
          }
          _visitedDetails[key] = value;
          _cached = value;
        }, onError: (Object _, StackTrace __) {}),
      );
    }
    _loadFollow(source);
    _loadResume(source);
  }

  Future<void> _loadResume(CatalogSource source) async {
    final generation = ++_resumeGeneration;
    if (source == CatalogSource.giri) {
      final request = detail;
      final key = catalogRowKey(selected);
      if (request == null) return;
      try {
        final value = await request;
        if (!mounted ||
            generation != _resumeGeneration ||
            catalogRowKey(selected) != key)
          return;
        final progress = inject<HistoryController>().lastWatching(
          value.video.toBangumi(),
          source.label,
        );
        if (progress == null ||
            progress.progress.inSeconds <= 0 ||
            !GStorage.getSetting<bool>(SettingsKeys.playResume))
          return;
        if (progress.road < 0 ||
            progress.road >= value.roads.length ||
            progress.episode <= 0 ||
            progress.episode > value.roads[progress.road].data.length)
          return;
        setState(() {
          if (_resume == null && road == 0) road = progress.road;
          _resume = {
            'road': progress.road,
            'episode_index': progress.episode - 1,
            'position_ms': progress.progress.inMilliseconds,
          };
        });
      } catch (_) {
        /* Local history may be unavailable during first bootstrap. */
      }
      return;
    }
    if (source != CatalogSource.xifan) return;
    final id = CatalogVideo(selected).id;
    final accounts = SourceAccounts.instance;
    try {
      final cached = (await accounts.cachedLibrary(
        false,
        5,
      ))?.where((r) => catalogInt(r['anime_id']) == id).firstOrNull;
      if (mounted &&
          generation == _resumeGeneration &&
          _resume == null &&
          cached != null) {
        setState(() => _resume = cached);
      }
      final fresh = await accounts.xifanProgressFor(id);
      // fresh 为 null（未登录/超出续播窗口）时不覆盖刚从缓存恢复的续播记录。
      if (fresh != null && mounted && generation == _resumeGeneration) {
        setState(() => _resume = fresh);
      }
    } catch (_) {}
  }

  Future<void> _loadFollow(CatalogSource source) async {
    final generation = ++_followGeneration;
    if (source == CatalogSource.cycani) return;
    final accounts = SourceAccounts.instance;
    final session = accounts.librarySession(source == CatalogSource.giri);
    try {
      final status = await accounts.followStatus(
        source == CatalogSource.giri,
        CatalogVideo(selected).id,
      );
      if (!mounted ||
          generation != _followGeneration ||
          session != accounts.librarySession(source == CatalogSource.giri))
        return;
      setState(
        () => _follow = status == null || source == CatalogSource.giri
            ? (status == 0 ? null : status)
            : switch (status) {
                0 => 2,
                2 => 3,
                _ => 1,
              },
      );
    } catch (_) {}
  }

  Widget _selector() => DropdownButton<String>(
    key: const ValueKey('catalog-detail-source'),
    value: catalogRowKey(selected),
    items: [
      for (final m in members)
        DropdownMenuItem(
          value: catalogRowKey(m),
          child: Text(catalogSource(m).label),
        ),
    ],
    onChanged: (key) {
      if (key == null || key == catalogRowKey(selected)) return;
      setState(() {
        _selectedRoads[catalogRowKey(selected)] = road;
        selected = members.firstWhere((m) => catalogRowKey(m) == key);
        road = _selectedRoads[key] ?? 0;
        _load();
      });
    },
  );
  Future<void> _sourceAction(
    Future<void> Function() action, {
    String? success,
  }) async {
    await runCatalogAction(
      active: () => mounted,
      busy: _sourceBusy,
      setBusy: (value) => setState(() => _sourceBusy = value),
      action: action,
      onSuccess: () {
        if (success != null)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(success)));
      },
      onError: (error) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error is StateError ? '${error.message}' : '同步失败'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = catalogSource(selected);
    if (source == CatalogSource.cycani)
      return CycaniDetailPage(
        videoId: CatalogVideo(selected).id,
        sourceSelector: _selector(),
        catalogVideoIds: catalogDanmakuIds(members, selected: selected),
        resolveCatalogVideoIds: _playbackIds,
      );
    return Scaffold(
      appBar: AppBar(
        title: const Text('番剧详情'),
        actions: [
          IconButton(
            tooltip: '账号',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SourceAccountsPage(
                  initialGiri: source == CatalogSource.giri,
                ),
              ),
            ),
          ),
          if (source == CatalogSource.giri)
            IconButton(
              tooltip: '收藏到文件夹',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      GiriCollectionsPage(addVideoId: CatalogVideo(selected).id),
                ),
              ),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => setState(() => _load(refresh: true)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<NativeCatalogDetail>(
        key: ValueKey(catalogRowKey(selected)),
        future: detail,
        builder: (context, s) {
          final visible = s.data ?? _cached;
          if (visible != null && road >= visible.roads.length) road = 0;
          return CatalogDetailScroll(
            key: PageStorageKey('catalog-detail-${catalogRowKey(selected)}'),
            children: [
              if (s.connectionState != ConnectionState.done && visible == null)
                const Center(child: CircularProgressIndicator())
              else if (s.hasError && visible == null)
                CatalogError(
                  error: '详情加载失败',
                  retry: () => setState(() => _load(refresh: true)),
                )
              else if (visible case final d?) ...[
                CatalogDetailHeader(
                  poster: CatalogPoster(
                    urls: [
                      d.video.cover,
                      CatalogVideo(selected).cover,
                      ...members.map((r) => CatalogVideo(r).cover),
                    ],
                  ),
                  metadata: CatalogDetailMetadata(
                    video: d.video,
                    episodes: d.roads.isEmpty
                        ? null
                        : d.roads[road].data.length,
                    actions: [
                      FilledButton.icon(
                        onPressed: d.roads.isEmpty || d.roads[road].data.isEmpty
                            ? null
                            : () => _play(d, source, _resumeIndex(d)),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          _resumeIndex(d) > 0 || _hasResume(d)
                              ? '继续观看'
                              : '开始观看',
                        ),
                      ),
                      PopupMenuButton<int>(
                        tooltip: '追番',
                        enabled: !_sourceBusy,
                        child: Chip(
                          avatar: Icon(
                            _follow == null
                                ? Icons.bookmark_border
                                : Icons.bookmark,
                          ),
                          label: Text(switch (_follow) {
                            1 => '在看',
                            2 => '想看',
                            3 => '看过',
                            _ => '加入追番',
                          }),
                        ),
                        onSelected: (status) {
                          final id = CatalogVideo(selected).id;
                          final key = catalogRowKey(selected);
                          final api = SourceAccounts.instance;
                          final session = api.librarySession(
                            source == CatalogSource.giri,
                          );
                          ++_followGeneration;
                          _sourceAction(() async {
                            if (source == CatalogSource.giri) {
                              await api.setGiriFollow(id, status);
                            } else {
                              await api.setXifanFollow(
                                id,
                                status == 0
                                    ? null
                                    : (status == 2
                                          ? 0
                                          : status == 3
                                          ? 2
                                          : 1),
                              );
                            }
                            if (mounted &&
                                catalogRowKey(selected) == key &&
                                session ==
                                    api.librarySession(
                                      source == CatalogSource.giri,
                                    )) {
                              setState(
                                () => _follow = status == 0 ? null : status,
                              );
                            }
                          }, success: '追番已更新');
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 1, child: Text('在看')),
                          PopupMenuItem(value: 2, child: Text('想看')),
                          PopupMenuItem(value: 3, child: Text('看过')),
                          PopupMenuItem(value: 0, child: Text('取消追番')),
                        ],
                      ),
                    ],
                  ),
                ),
                CatalogSynopsis(video: d.video, selector: _selector()),
                CatalogEpisodePicker(
                  roads: d.roads.map((r) => r.name).toList(),
                  selected: road,
                  labels: d.roads.isEmpty
                      ? []
                      : d.roads[road].identifier.toList(),
                  onRoad: (r) => setState(() => road = r),
                  onEpisode: (i) => _play(d, source, i),
                ),
                const SizedBox(height: 32),
                CatalogComments(
                  key: ValueKey(catalogRowKey(selected)),
                  source: source,
                  videoId: CatalogVideo(selected).id,
                ),
                if (d.related.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('相关推荐', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 224,
                    child: CustomScrollView(
                      slivers: [CatalogVideoSliver(items: d.related)],
                    ),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  (int, int)? _resumeMatch(NativeCatalogDetail d) {
    if (d.roads.isEmpty || road >= d.roads.length) return null;
    if (catalogSource(selected) == CatalogSource.giri) {
      return giriResumeMatch(d.roads[road].data.length, road, _resume);
    }
    return xifanResumeMatch(
      d.roads[road].data,
      CatalogVideo(selected).id,
      _resume,
    );
  }

  bool _hasResume(NativeCatalogDetail d) => _resumeMatch(d) != null;
  int _resumeIndex(NativeCatalogDetail d) => _resumeMatch(d)?.$1 ?? 0;

  Future<void> _play(NativeCatalogDetail d, CatalogSource source, int i) async {
    if (_openingPlayer) return;
    _openingPlayer = true;
    try {
      await _openPlayback(d, source, i);
    } finally {
      _openingPlayer = false;
    }
  }

  Future<void> _openPlayback(
    NativeCatalogDetail d,
    CatalogSource source,
    int i,
  ) async {
    final key = catalogRowKey(selected), resume = _resumeMatch(d);
    final chosenRoad = road;
    final ids = await _playbackIds();
    if (!mounted || catalogRowKey(selected) != key) return;
    if (source == CatalogSource.giri) {
      final id = CatalogVideo(selected).id;
      _sourceAction(() => SourceAccounts.instance.recordGiriHistory(id));
    }
    await context.pushNamed(
      '/video/',
      arguments: OnlineVideoPlaybackArgs(
        bangumiItem: d.video.toBangumi(),
        plugin: catalogPlugin(source),
        title: d.video.title,
        src: source.detail(CatalogVideo(selected).id).toString(),
        roads: d.roads,
        catalogVideoIds: ids,
        catalogBangumiId: d.video.bangumiId,
        initialRoad: chosenRoad,
        initialEpisode: i + 1,
        initialOffset: resume?.$1 == i ? resume!.$2 : 0,
      ),
    );
    if (mounted && catalogRowKey(selected) == key) {
      _loadResume(source);
      _loadFollow(source);
    }
  }
}
