import 'catalog_snapshot.dart';
import 'dart:async';
import 'cycani_catalog_disk_cache.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart';
import 'cycani_api.dart';
import 'cycani_catalog_sources.dart';
import 'cycani_paging.dart';
import 'cycani_feed_widgets.dart';
import 'cycani_home_page.dart' show CycaniError;

class CycaniSearchPage extends StatefulWidget {
  const CycaniSearchPage({super.key, this.initialKeyword = '', this.api});
  final String initialKeyword;
  final CycaniApi? api;
  @override
  State<CycaniSearchPage> createState() => _CycaniSearchPageState();
}

class _CycaniSearchPageState extends State<CycaniSearchPage> {
  late final text = TextEditingController(text: widget.initialKeyword);
  late final CycaniFeed feed;
  String keyword = '';
  final scroll = ScrollController();
  CycaniApi get api => widget.api ?? CycaniApi.instance;
  @override
  void initState() {
    super.initState();
    feed = CycaniFeed((page, _) async {
      final query = keyword;
      if (widget.api != null) {
        return CycaniPage.fromJson(
          await api.videos(keyword: query, page: page),
          page: page,
        );
      }
      final result = await CycaniCatalogSources.instance.search(query, page);
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
                  return CycaniError(error: feed.error!, retry: feed.loadMore);
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
                      CycaniVideoSliver(items: mergeCatalogRows(feed.items)),
                      SliverToBoxAdapter(child: CycaniLoadMore(feed: feed)),
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
