import 'catalog_snapshot.dart';
import 'catalog_comment_widgets.dart';
import 'catalog_comment_date.dart';
import 'dart:async';
import 'cycani_catalog_disk_cache.dart';
import 'cycani_paging.dart';
import 'cycani_feed_widgets.dart';
import 'package:flutter/material.dart';
import 'cycani_api.dart';
import 'cycani_models.dart';
import 'cycani_home_page.dart' show CycaniError, cycaniToast;

class CycaniComments extends StatefulWidget {
  const CycaniComments({
    super.key,
    required this.videoId,
    this.parentId,
    this.api,
    this.onPosted,
    this.cacheEnabled,
  });
  final CycaniApi? api;
  final VoidCallback? onPosted;
  final bool? cacheEnabled;
  final int videoId;
  final int? parentId;
  @override
  State<CycaniComments> createState() => _CycaniCommentsState();
}

class _CycaniCommentsState extends State<CycaniComments> {
  CycaniApi get api => widget.api ?? CycaniApi.instance;
  final text = TextEditingController();
  late final CycaniFeed feed;
  String order = 'time';
  bool sending = false;
  @override
  void initState() {
    super.initState();
    feed = CycaniFeed(_page);
    _reload();
  }

  bool get _cacheEnabled => widget.cacheEnabled ?? widget.api == null;
  String get _key =>
      'cycani-comments:${widget.videoId}:${widget.parentId ?? 'root'}:$order';

  Future<CycaniPage> _page(int page, String? _) async {
    final videoId = widget.videoId, parent = widget.parentId;
    final sort = order, key = _key, useCache = _cacheEnabled;
    final result = CycaniPage.fromJson(
      parent == null
          ? await api.comments(videoId, page: page, order: sort)
          : await api.replies(parent, page: page),
      page: page,
      size: 20,
    );
    if (page == 1 && useCache) {
      final publicRows = [
        for (final row in result.items)
          catalogPickFields(row, [
            'id',
            'user_nickname',
            'content',
            'create_time',
            'reply_count',
            'pinned',
          ]),
      ];
      unawaited(CatalogDiskCache.write(key, publicRows));
    }
    return result;
  }

  @override
  void didUpdateWidget(covariant CycaniComments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId ||
        oldWidget.parentId != widget.parentId ||
        oldWidget.api != widget.api) {
      text.clear();
      order = 'time';
      _reload(reset: true);
    }
  }

  void _reload({bool reset = false}) {
    if (reset) feed.clear();
    if (_cacheEnabled && feed.items.isEmpty) {
      final key = _key;
      unawaited(
        restoreCatalogSnapshot(
          key,
          canApply: () => mounted && key == _key,
          apply: feed.showCached,
        ),
      );
    }
    unawaited(feed.refresh());
  }

  @override
  void dispose() {
    feed.dispose();
    text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (sending || text.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      await api.postComment(
        widget.videoId,
        text.text,
        parentId: widget.parentId,
      );
      if (mounted) {
        text.clear();
        widget.onPosted?.call();
        _reload();
      }
    } catch (e) {
      if (mounted) {
        cycaniToast(this.context, '$e');
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  String _date(Object? value) => sourceCommentDate(value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CatalogCommentHeader(
        title: widget.parentId == null ? '次元城评论' : '回复',
        sort: widget.parentId == null
            ? DropdownButton<String>(
                value: order,
                items: const [
                  DropdownMenuItem(value: 'time', child: Text('最新')),
                  DropdownMenuItem(value: 'hot', child: Text('热门')),
                ],
                onChanged: (v) {
                  if (v == null || v == order) return;
                  setState(() => order = v);
                  _reload(reset: true);
                },
              )
            : null,
        refresh: _reload,
      ),
      const SizedBox(height: 10),
      CatalogCommentComposer(
        controller: text,
        busy: sending,
        hint: api.loggedIn ? '写下你的感想…' : '登录账户后可发表评论',
        send: api.loggedIn ? _send : null,
      ),
      AnimatedBuilder(
        animation: feed,
        builder: (context, _) {
          if (feed.page == 0 && feed.loading && feed.items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (feed.page == 0 && feed.error != null && feed.items.isEmpty) {
            return SizedBox(
              height: 230,
              child: CycaniError(error: feed.error!, retry: _reload),
            );
          }
          final list = feed.items;
          return Column(
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Text('还没有评论'),
                ),
              for (final item in list)
                CatalogCommentCard(
                  author: '${item['user_nickname'] ?? '用户'}',
                  content: '${item['content'] ?? ''}',
                  date: _date(item['create_time']),
                  pinned: item['pinned'] == true,
                  headerActions: [
                    if ('${api.user['role']}'.contains('admin') ||
                        api.user['is_admin'] == true)
                      IconButton(
                        tooltip: '切换置顶',
                        icon: const Icon(Icons.push_pin_outlined),
                        onPressed: () async {
                          try {
                            await api.pinComment(
                              cycaniInt(item['id']),
                              item['pinned'] != true,
                            );
                            if (mounted) _reload();
                          } catch (e) {
                            if (context.mounted) cycaniToast(context, '$e');
                          }
                        },
                      ),
                  ],
                  actions: [
                    if (widget.parentId == null)
                      TextButton(
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (context) => FractionallySizedBox(
                            heightFactor: .85,
                            child: SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(
                                24,
                                24,
                                24,
                                MediaQuery.viewInsetsOf(context).bottom + 24,
                              ),
                              child: CycaniComments(
                                videoId: widget.videoId,
                                parentId: cycaniInt(item['id']),
                                api: api,
                                cacheEnabled: _cacheEnabled,
                                onPosted: () {
                                  if (mounted) _reload();
                                },
                              ),
                            ),
                          ),
                        ),
                        child: Text('回复 (${item['reply_count'] ?? 0})'),
                      ),
                  ],
                ),
              CycaniLoadMore(feed: feed),
            ],
          );
        },
      ),
    ],
  );
}
