import 'catalog_detail_metadata.dart';
import 'catalog_lru.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cyanmoon_acg/services/network/proxy_aware_image_cache_manager.dart';
import 'catalog_disk_cache.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cyanmoon_acg/pages/video/video_playback_args.dart';
import 'cycani_api.dart';
import 'catalog_identity.dart';
import 'catalog_models.dart';
import 'qingyue_home_page.dart' show cycaniPlugin, CatalogError, catalogToast;
import 'cycani_account_page.dart';
import 'catalog_comments.dart';

class CycaniDetailPage extends StatefulWidget {
  const CycaniDetailPage({
    super.key,
    required this.videoId,
    this.api,
    this.openPlayer,
    this.openAccountSettings,
    this.sourceSelector,
    this.catalogVideoIds = const {},
    this.resolveCatalogVideoIds,
  });
  final int videoId;
  final Widget? sourceSelector;
  final Map<String, int> catalogVideoIds;
  final Future<Map<String, int>> Function()? resolveCatalogVideoIds;
  final CycaniApi? api;
  final Future<void> Function(OnlineVideoPlaybackArgs)? openPlayer;
  final Future<void> Function()? openAccountSettings;
  @override
  State<CycaniDetailPage> createState() => _CycaniDetailPageState();
}

class _CycaniDetailPageState extends State<CycaniDetailPage> {
  CycaniApi get api => widget.api ?? CycaniApi.instance;
  final scroll = ScrollController();
  late Future<CatalogVideo> future;
  List<CatalogEpisodes> episodes = [];
  List<CatalogJson> recommendations = [];
  CatalogJson history = {}, favorite = {};
  CatalogVideo? _diskVideo;
  int source = 0;
  bool _openingPlayer = false;
  int loadGeneration = 0, accountGeneration = 0;
  bool busy = false;
  late int epoch;
  @override
  void initState() {
    super.initState();
    epoch = api.sessionEpoch;
    api.addListener(_sessionChanged);
    future = _load();
  }

  @override
  void didUpdateWidget(covariant CycaniDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId || oldWidget.api != widget.api) {
      (oldWidget.api ?? CycaniApi.instance).removeListener(_sessionChanged);
      api.addListener(_sessionChanged);
      epoch = api.sessionEpoch;
      history = {};
      favorite = {};
      episodes = [];
      _diskVideo = null;
      recommendations = [];
      source = 0;
      accountGeneration++;
      future = _load();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) scroll.jumpTo(0);
      });
    }
  }

  void _sessionChanged() {
    if (!mounted || epoch == api.sessionEpoch) return;
    epoch = api.sessionEpoch;
    setState(() {
      history = {};
      favorite = {};
    });
    unawaited(_loadAccountState());
  }

  Future<void> _loadAccountState() async {
    final session = api.sessionEpoch,
        id = widget.videoId,
        revision = ++accountGeneration;
    if (!api.loggedIn) return;
    Future<CatalogJson?> read(Future<CatalogJson> request) async {
      try {
        return await request;
      } catch (_) {
        return null;
      }
    }

    final values = await Future.wait([
      read(api.history(id)),
      read(api.favoriteStatus(id)),
    ]);
    if (!mounted ||
        session != api.sessionEpoch ||
        id != widget.videoId ||
        revision != accountGeneration)
      return;
    setState(() {
      if (values[0] != null) history = values[0]!;
      if (values[1] != null) favorite = values[1]!;
    });
  }

  void _reloadPublic() {
    setState(() {
      future = _load(refresh: true);
    });
  }

  Future<void> _openAccount() async {
    if (api.loggedIn) {
      if (widget.openAccountSettings != null) {
        await widget.openAccountSettings!();
      } else {
        await context.pushNamed('/settings/account');
      }
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const CycaniAccountPage()),
      );
    }
    if (mounted) await _loadAccountState();
  }

  @override
  void dispose() {
    api.removeListener(_sessionChanged);
    scroll.dispose();
    super.dispose();
  }

  static final _publicCache =
      Expando<
        Map<int, Future<(CatalogVideo, List<CatalogEpisodes>, List<CatalogJson>)>>
      >();

  Future<CatalogVideo> _load({bool refresh = false}) async {
    final id = widget.videoId, generation = ++loadGeneration;
    final cache = _publicCache[api] ??=
        CatalogLru<
          int,
          Future<(CatalogVideo, List<CatalogEpisodes>, List<CatalogJson>)>
        >();
    if (refresh) cache.remove(id);
    final key = 'detail:cycani:$id';
    if (widget.api == null && _diskVideo == null && !refresh) {
      unawaited(
        CatalogDiskCache.read(key).then((rows) {
          if (!mounted ||
              generation != loadGeneration ||
              _diskVideo != null ||
              rows == null ||
              rows.isEmpty)
            return;
          final row = rows.first;
          final video = CatalogVideo(catalogMap(row['video']));
          if (video.id != id) return;
          setState(() {
            _diskVideo = video;
            episodes = [
              for (final road in catalogList(row['roads']))
                CatalogEpisodes(
                  name: road['name'].toString(),
                  code: road['code'].toString(),
                  items: catalogList(road['items']),
                ),
            ];
            recommendations = catalogList(row['suggestions']);
          });
        }),
      );
    }
    final pending = cache.putIfAbsent(id, () async {
      final video = await api.detail(id);
      final (roads, suggestions) = await (
        api.episodes(id, video: video),
        api
            .request('/videos/$id/recommendations', query: {'limit': 12})
            .then((data) => catalogList(data))
            .catchError((Object _) => <CatalogJson>[]),
      ).wait;
      if (widget.api == null)
        unawaited(
          CatalogDiskCache.write(key, [
            {
              'video': video.json,
              'suggestions': suggestions,
              'roads': [
                for (final r in roads)
                  {'name': r.name, 'code': r.code, 'items': r.items},
              ],
            },
          ]),
        );
      return (video, roads, suggestions);
    });
    try {
      final (video, roads, suggestions) = await pending;
      if (mounted && generation == loadGeneration && id == widget.videoId) {
        _diskVideo = video;
        episodes = roads;
        recommendations = suggestions;
        source = source.clamp(0, (roads.length - 1).clamp(0, 10000));
        unawaited(_loadAccountState());
      }
      return video;
    } catch (_) {
      if (identical(cache[id], pending)) cache.remove(id);
      rethrow;
    }
  }

  Future<void> _play(
    CatalogVideo video, {
    int index = 0,
    int? road,
    bool resume = false,
  }) async {
    if (_openingPlayer) return;
    _openingPlayer = true;
    try {
      await _openPlayback(video, index: index, road: road, resume: resume);
    } finally {
      _openingPlayer = false;
    }
  }

  Future<void> _openPlayback(
    CatalogVideo video, {
    int index = 0,
    int? road,
    bool resume = false,
  }) async {
    if (!api.loggedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const CycaniAccountPage()),
      );
      if (!mounted || !api.loggedIn) return;
    }
    final chosen = road ?? source;
    if (episodes.isEmpty ||
        chosen >= episodes.length ||
        index >= episodes[chosen].items.length) {
      return;
    }
    final ids =
        await widget.resolveCatalogVideoIds?.call() ?? widget.catalogVideoIds;
    if (!mounted || widget.videoId != video.id) return;
    final args = OnlineVideoPlaybackArgs(
      bangumiItem: video.toBangumi(),
      plugin: cycaniPlugin(),
      title: video.title,
      src: '${CycaniApi.origin}/anime/${video.id}',
      roads: episodes.map((e) => e.toRoad()).toList(),
      catalogVideoIds: {...ids, 'cycani': video.id},
      catalogBangumiId: video.bangumiId,
      initialEpisode: index + 1,
      initialRoad: chosen,
      initialOffset: resume ? catalogInt(history['progress']) ~/ 1000 : 0,
    );
    if (widget.openPlayer != null) {
      await widget.openPlayer!(args);
    } else {
      await context.pushNamed('/video/', arguments: args);
    }
    if (mounted) unawaited(_loadAccountState());
  }

  Future<void> _continue(CatalogVideo video) async {
    final section = catalogInt(history['section_id']);
    for (var r = 0; r < episodes.length; r++) {
      final i = episodes[r].items.indexWhere(
        (e) => catalogInt(e['id']) == section,
      );
      if (i >= 0) {
        await _play(video, index: i, road: r, resume: true);
        return;
      }
    }
    await _play(video);
  }

  Future<void> _favorite(String value) async {
    if (busy) return;
    final id = widget.videoId, session = api.sessionEpoch;
    final revision = ++accountGeneration;
    setState(() => busy = true);
    try {
      if (value == 'remove') {
        await api.removeFavorites([id]);
      } else if (favorite['favorited'] == true)
        await api.moveFavorites([id], value);
      else
        await api.favorite(id, value);
      if (!mounted || id != widget.videoId || session != api.sessionEpoch)
        return;
      final updated = await api.favoriteStatus(id);
      if (mounted &&
          id == widget.videoId &&
          session == api.sessionEpoch &&
          revision == accountGeneration)
        setState(() => favorite = updated);
    } catch (e) {
      if (mounted) catalogToast(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('番剧详情'),
      actions: [
        IconButton(
          tooltip: api.loggedIn ? '个人资料' : '登录',
          onPressed: _openAccount,
          icon: const Icon(Icons.account_circle_outlined),
        ),
        IconButton(
          tooltip: '刷新',
          onPressed: _reloadPublic,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<CatalogVideo>(
      future: future,
      builder: (context, snapshot) {
        final visible = snapshot.data ?? _diskVideo;
        if (snapshot.connectionState != ConnectionState.done &&
            visible == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError && visible == null) {
          return CatalogError(error: snapshot.error!, retry: _reloadPublic);
        }
        if (visible == null) return const SizedBox.shrink();
        final video = visible;
        final image = CatalogPoster(urls: [video.cover]);
        final metadata = CatalogDetailMetadata(
          video: video,
          episodes: video.total,
          actions: [
            FilledButton.icon(
              onPressed: episodes.isEmpty ? null : () => _continue(video),
              icon: const Icon(Icons.play_arrow),
              label: Text(
                history.isNotEmpty
                    ? '继续 ${history['section_title'] ?? '观看'}'
                    : '开始观看',
              ),
            ),
            if (history.isNotEmpty)
              OutlinedButton(
                onPressed: episodes.isEmpty ? null : () => _play(video),
                child: const Text('从头播放'),
              ),
            PopupMenuButton<String>(
              tooltip: '追番状态',
              enabled: api.loggedIn && !busy,
              onSelected: _favorite,
              itemBuilder: (_) => [
                for (final e in {
                  'watching': '在看',
                  'want': '想看',
                  'watched': '看过',
                  if (favorite['favorited'] == true) 'remove': '取消追番',
                }.entries)
                  PopupMenuItem(value: e.key, child: Text(e.value)),
              ],
              child: Chip(
                avatar: Icon(
                  favorite['favorited'] == true
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                ),
                label: Text(
                  !api.loggedIn
                      ? '登录后追番'
                      : {
                              'watching': '在看',
                              'want': '想看',
                              'watched': '看过',
                            }[favorite['category']] ??
                            '加入追番',
                ),
              ),
            ),
          ],
        );
        return CatalogDetailScroll(
          key: PageStorageKey('cycani-detail-${widget.videoId}'),
          controller: scroll,
          children: [
            CatalogDetailHeader(poster: image, metadata: metadata),
            CatalogSynopsis(video: video, selector: widget.sourceSelector),
            CatalogEpisodePicker(
              roads: episodes.map((r) => r.name).toList(),
              selected: source,
              labels: episodes.isEmpty
                  ? []
                  : [
                      for (final (i, item) in episodes[source].items.indexed)
                        '${item['title'] ?? '第${i + 1}集'}',
                    ],
              onRoad: (r) => setState(() => source = r),
              onEpisode: (i) => _play(video, index: i),
            ),
            const SizedBox(height: 32),
            CatalogComments(
              source: CatalogSource.cycani,
              videoId: video.id,
              api: api,
              cacheEnabled: widget.api == null,
            ),
            if (recommendations.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text('相关推荐', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final r in recommendations)
                    ActionChip(
                      label: Text('${r['title'] ?? ''}'),
                      onPressed: () => context.pushNamed(
                        '/qingyue/detail',
                        arguments: catalogInt(r['video_id'] ?? r['id']),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    ),
  );
}

class CatalogDetailScroll extends StatelessWidget {
  const CatalogDetailScroll({
    super.key,
    this.controller,
    required this.children,
  });

  final ScrollController? controller;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: controller,
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1300),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

class CatalogSynopsis extends StatelessWidget {
  const CatalogSynopsis({super.key, required this.video, this.selector});

  final CatalogVideo video;
  final Widget? selector;

  @override
  Widget build(BuildContext context) {
    final credits = <Widget>[];
    for (final (key, label) in const [
      ('director', '导演'),
      ('actor', '演员'),
      ('writer', '编剧'),
      ('language', '语言'),
      ('state', '状态'),
    ]) {
      final value = video.json[key];
      final text = value is List
          ? value
                .whereType<Object>()
                .map((v) => v.toString().trim())
                .where((v) => v.isNotEmpty)
                .join(' / ')
          : value?.toString().trim() ?? '';
      if (text.isNotEmpty) credits.add(Text('$label：$text'));
    }
    final description = video.description.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 26),
        if (selector != null) selector!,
        if (description.isNotEmpty) ...[
          Text('简介', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          SelectableText(description),
        ],
        if (credits.isNotEmpty) ...[
          if (description.isNotEmpty) const SizedBox(height: 14),
          Wrap(spacing: 18, runSpacing: 8, children: credits),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class CatalogDetailHeader extends StatelessWidget {
  const CatalogDetailHeader({
    super.key,
    required this.poster,
    required this.metadata,
  });
  final Widget poster, metadata;

  @override
  Widget build(BuildContext context) => MediaQuery.sizeOf(context).width > 700
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            poster,
            const SizedBox(width: 28),
            Expanded(child: metadata),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: poster),
            const SizedBox(height: 20),
            metadata,
          ],
        );
}

class CatalogPoster extends StatelessWidget {
  const CatalogPoster({super.key, required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final candidates = urls
        .where((url) {
          final uri = Uri.tryParse(url);
          return uri != null &&
              uri.hasAuthority &&
              (uri.scheme == 'https' || uri.scheme == 'http');
        })
        .toSet()
        .toList();
    Widget at(int i) => i >= candidates.length
        ? Container(
            width: 180,
            height: 270,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.movie_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: CachedNetworkImage(
              cacheManager: ProxyAwareImageCacheManager.instance,
              imageUrl: candidates[i],
              width: 180,
              height: 270,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => at(i + 1),
            ),
          );
    return at(0);
  }
}

class CatalogEpisodePicker extends StatelessWidget {
  const CatalogEpisodePicker({
    super.key,
    required this.roads,
    required this.selected,
    required this.labels,
    required this.onRoad,
    required this.onEpisode,
  });
  final List<String> roads, labels;
  final int selected;
  final ValueChanged<int> onRoad, onEpisode;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '选集 · ${labels.length} 集',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      if (roads.isNotEmpty) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, name) in roads.indexed)
              ChoiceChip(
                label: Text(name),
                selected: i == selected,
                onSelected: (_) => onRoad(i),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      if (labels.isEmpty)
        const Text('当前番剧暂无可用选集')
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, label) in labels.indexed)
              OutlinedButton(onPressed: () => onEpisode(i), child: Text(label)),
          ],
        ),
    ],
  );
}
