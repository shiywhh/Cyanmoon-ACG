import 'catalog_snapshot.dart';
import 'dart:async';
import 'catalog_disk_cache.dart';
import 'package:flutter/material.dart';
import 'package:cyanmoon_acg/bean/appbar/drag_to_move_bar.dart';
import 'cycani_api.dart';
import 'catalog_aggregator.dart';
import 'catalog_paging.dart';
import 'catalog_feed_widgets.dart';
import 'qingyue_home_page.dart' show CatalogError;

class CatalogSearchPage extends StatefulWidget {
  const CatalogSearchPage({super.key, this.initialKeyword = '', this.api});
  final String initialKeyword;
  final CycaniApi? api;
  @override
  State<CatalogSearchPage> createState() => _CatalogSearchPageState();
}

class _CatalogSearchPageState extends State<CatalogSearchPage> {
  late final text = TextEditingController(text: widget.initialKeyword);
  late final CatalogFeed feed;
  String keyword = '';
  final scroll = ScrollController();
  CycaniApi get api => widget.api ?? CycaniApi.instance;
  @override
  void initState() {
    super.initState();
    feed = CatalogFeed((page, _) async {
      final query = keyword;
      if (widget.api != null) {
        return CatalogPage.fromJson(
          await api.videos(keyword: query, page: page),
          page: page,
        );
      }
      final result = await CatalogAggregator.instance.search(query, page);
      if (page == 1)
        unawaited(CatalogDiskCache.write('search:$query', result.items));
      return result;
    }, keyOf: catalogRowKey);
    if (widget.initialKeyword.trim().isNotEmpty) _search(widget.initialKeyword);
  }

  void _search(String value) {
    final oldKeyword = keyword;
    keyword = value.trim();
    if (keyword.isNotEmpty) {
      if (widget.api != null) {
        feed.reset();
      } else {
        final query = keyword;
        if (oldKeyword != query) feed.clear();
        unawaited(
          restoreCatalogSnapshot(
            'search:$query',
            canApply: () => mounted && keyword == query,
            apply: feed.showCached,
          ),
        );
        feed.refresh();
      }
    } else {
      feed.clear();
    }
    if (scroll.hasClients) scroll.jumpTo(0);
    setState(() {});
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    feed.dispose();
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 80,
      title: DragToMoveArea(
        child: Text(
          '搜索',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    ),
    body: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          TextField(
            controller: text,
            autofocus: widget.initialKeyword.isEmpty,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: '搜索番剧',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                tooltip: '搜索',
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _search(text.text),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: AnimatedBuilder(
              animation: feed,
              builder: (context, _) {
                if (keyword.isEmpty)
                  return const Center(
                    child: Icon(Icons.search_rounded, size: 48),
                  );
                if (feed.page == 0 && feed.loading && feed.items.isEmpty)
                  return const Center(child: CircularProgressIndicator());
                if (feed.page == 0 && feed.error != null && feed.items.isEmpty)
                  return CatalogError(error: feed.error!, retry: feed.loadMore);
                return RefreshIndicator(
                  onRefresh: feed.refresh,
                  child: CustomScrollView(
                    controller: scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (feed.total != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text('共 ${feed.total} 个结果'),
                          ),
                        ),
                      if (feed.items.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: Text('未找到番剧')),
                        ),
                      CatalogVideoSliver(items: mergeCatalogRows(feed.items)),
                      SliverToBoxAdapter(child: CatalogFeedLoadMore(feed: feed)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
