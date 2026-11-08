import 'qingyue_home_page.dart' show CatalogError;
import 'catalog_disk_cache.dart';
import 'catalog_aggregator.dart';
import 'catalog_detail_page.dart';
import 'dart:async';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cyanmoon_acg/bean/card/bangumi_card.dart';
import 'package:cyanmoon_acg/bean/card/bangumi_timeline_card.dart';
import 'package:cyanmoon_acg/utils/constants.dart';
import 'catalog_models.dart';
import 'catalog_paging.dart';

/// Same poster/timeline cards, spacing and breakpoints as the original UI.
class CatalogVideoSliver extends StatelessWidget {
  const CatalogVideoSliver({
    super.key,
    required this.items,
    this.horizontal = false,
    this.tileBuilder,
  });
  final List<CatalogJson> items;
  final bool horizontal;
  final Widget Function(BuildContext, int)? tileBuilder;
  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, box) {
      final width = box.crossAxisExtent;
      final count = horizontal
          ? (width > 1100
                ? 3
                : width > 650
                ? 2
                : 1)
          : (width > 840
                ? 6
                : width > 600
                ? 5
                : 3);
      final extent = horizontal
          ? BangumiTimelineCard.heightFor(MediaQuery.textScalerOf(context))
          : (width - (count - 1) * StyleString.cardSpace) / count / .65 +
                MediaQuery.textScalerOf(context).scale(52);
      return SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          mainAxisSpacing: StyleString.cardSpace,
          crossAxisSpacing: StyleString.cardSpace,
          mainAxisExtent: extent,
        ),
        delegate: SliverChildBuilderDelegate((context, i) {
          if (tileBuilder != null) return tileBuilder!(context, i);
          final raw = items[i];
          final video = CatalogVideo(
            raw['video'] is Map ? catalogMap(raw['video']) : raw,
          );
          void open() => unawaited(_openCatalogRow(context, raw, video.id));
          return horizontal
              ? BangumiTimelineCard(
                  bangumiItem: video.toBangumi(),
                  showRating: true,
                  onTap: open,
                )
              : BangumiCardV(
                  bangumiItem: video.toBangumi(),
                  enableHero: false,
                  onTap: open,
                );
        }, childCount: items.length),
      );
    },
  );
}

Future<void> _openCatalogRow(
  BuildContext context,
  CatalogJson row,
  int id,
) async {
  final item = row['video'] is Map ? catalogMap(row['video']) : row;
  if (id <= 0) return;
  if (catalogSource(item) == CatalogSource.bangumi) {
    // Bangumi 搜索结果直达应用内番剧详情页（资料/评分/吐槽）；
    // 行内 bangumi_id 即原始 subject id（toBangumi 产物是 legacy 负编码，需改写）。
    final video = CatalogVideo(item);
    final subjectId = video.bangumiId > 0 ? video.bangumiId : video.id;
    if (subjectId <= 0) return;
    final bangumiItem = video.toBangumi()..id = subjectId;
    await context.pushNamed('/info/', arguments: bangumiItem);
    return;
  }
  final series = catalogInt(item['xifan_series']);
  if (series > 0) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _XifanSeriesPage(id: series, title: CatalogVideo(item).title),
      ),
    );
    return;
  }
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => CatalogDetailPage(row: item)));
}

class _XifanSeriesPage extends StatefulWidget {
  const _XifanSeriesPage({required this.id, required this.title});
  final int id;
  final String title;

  @override
  State<_XifanSeriesPage> createState() => _XifanSeriesPageState();
}

class _XifanSeriesPageState extends State<_XifanSeriesPage> {
  List<CatalogJson>? _cached;
  String get _key => 'xifan-series:${widget.id}';
  late Future<List<CatalogJson>> request;
  @override
  void initState() {
    super.initState();
    CatalogDiskCache.read(_key).then((rows) {
      if (mounted && _cached == null && rows != null)
        setState(() => _cached = rows);
    });
    request = _load();
  }

  Future<List<CatalogJson>> _load() async {
    final rows = await CatalogAggregator.instance.xifanSeries(widget.id);
    _cached = rows;
    unawaited(CatalogDiskCache.write(_key, rows));
    return rows;
  }

  Future<void> _refresh() async {
    setState(() => request = _load());
    try {
      await request;
    } catch (_) {
      // FutureBuilder retains the last successful series on failure.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: FutureBuilder<List<CatalogJson>>(
      future: request,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? _cached;
        if (rows == null && snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (rows == null && snapshot.hasError) {
          return CatalogError(error: '系列加载失败', retry: _refresh);
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            key: PageStorageKey(_key),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (rows == null || rows.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('暂无番剧')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: CatalogVideoSliver(items: rows),
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// Feed-based adapter over the parameterized [CatalogLoadMore].
class CatalogFeedLoadMore extends StatelessWidget {
  const CatalogFeedLoadMore({super.key, required this.feed});
  final CatalogFeed feed;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: feed,
    builder: (context, _) => CatalogLoadMore(
      loading: feed.loading,
      hasMore: feed.hasMore,
      error: feed.error,
      loadMore: feed.loadMore,
    ),
  );
}

class CatalogLoadMore extends StatefulWidget {
  const CatalogLoadMore({
    super.key,
    required this.loading,
    required this.hasMore,
    required this.loadMore,
    this.error,
  });
  final bool loading, hasMore;
  final Object? error;
  final Future<void> Function() loadMore;
  @override
  State<CatalogLoadMore> createState() => _CatalogLoadMoreState();
}

class _CatalogLoadMoreState extends State<CatalogLoadMore> {
  ScrollPosition? position;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (next != position) {
      position?.removeListener(_check);
      position = next;
      position?.addListener(_check);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(covariant CatalogLoadMore oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  void _check() {
    if (!mounted ||
        widget.loading ||
        !widget.hasMore ||
        widget.error != null ||
        position == null ||
        !position!.hasContentDimensions)
      return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final top = viewport.getOffsetToReveal(box, 0).offset;
    if (top <= position!.pixels + position!.viewportDimension + 200 &&
        top + box.size.height >= position!.pixels - 200) {
      unawaited(widget.loadMore());
    }
  }

  @override
  void dispose() {
    position?.removeListener(_check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _schedule();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: widget.loading
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : widget.error != null
            ? TextButton.icon(
                onPressed: widget.loadMore,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              )
            : const SizedBox(height: 8),
      ),
    );
  }
}

class CatalogCategoryLinks extends StatelessWidget {
  const CatalogCategoryLinks({
    super.key,
    required this.categories,
    required this.onSelected,
  });

  final List<CatalogJson> categories;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in categories)
          ActionChip(
            label: Text('${item['name']}'),
            onPressed: () => onSelected('${item['id']}'),
          ),
      ],
    ),
  );
}
