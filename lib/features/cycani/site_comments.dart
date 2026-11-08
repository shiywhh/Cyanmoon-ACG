import 'qingyue_home_page.dart' show CatalogError;
import 'catalog_action.dart';
import 'catalog_snapshot.dart';
import 'catalog_feed_widgets.dart';
import 'catalog_lru.dart';
import 'catalog_comment_widgets.dart';
import 'catalog_comment_date.dart';
export 'catalog_comment_date.dart';
import 'catalog_disk_cache.dart';
import 'package:flutter/material.dart';
import 'catalog_models.dart';
import 'site_accounts.dart';

CatalogJson publicSourceComment(
  CatalogJson row, {
  required bool giri,
  bool nested = false,
}) {
  if (giri) {
    return {
      ...catalogPickFields(row, [
        'comment_id',
        'comment_name',
        'comment_content',
        'comment_time',
        'comment_up',
        'comment_down',
      ]),
      if (!nested)
        'chile_list': [
          for (final child in catalogList(row['chile_list']))
            publicSourceComment(child, giri: true, nested: true),
        ],
    };
  }
  final author = catalogMap(row['author']);
  return {
    ...catalogPickFields(row, [
      'id',
      'content',
      'created_at',
      'reply_count',
      'like_count',
      'is_pinned',
    ]),
    'author': {'name': author['name']},
  };
}

class SourceComments extends StatefulWidget {
  const SourceComments({super.key, required this.giri, required this.videoId});
  final bool giri;
  final int videoId;

  @override
  State<SourceComments> createState() => _SourceCommentsState();
}

class _SourceCommentsState extends State<SourceComments> {
  final input = TextEditingController();
  final api = SourceAccounts.instance;
  static final cache = CatalogLru<(bool, int, String), List<CatalogJson>>();
  final replies = <Object, List<CatalogJson>>{};
  final replyCursor = <Object, Object>{};
  final _replyLoading = <Object>{};
  int _replyEpoch = 0;
  String? notice;

  String sort = 'latest';
  List<CatalogJson> rows = [];
  Object? cursor, parent;
  int page = 0;
  bool loading = false, more = false, saving = false;
  String? error;
  bool get giri => widget.giri;
  (bool, int, String) get cacheKey => (giri, widget.videoId, sort);

  String get _diskKey =>
      'comments:${giri ? 'giri' : 'xifan'}:${widget.videoId}:$sort';

  Future<void> _restoreDisk() async {
    if (rows.isNotEmpty) return;
    final key = _diskKey;
    await restoreCatalogSnapshot(
      key,
      canApply: () => mounted && _diskKey == key && rows.isEmpty && page == 0,
      apply: (value) => setState(() => rows = value),
    );
  }

  @override
  void initState() {
    super.initState();
    rows = cache[cacheKey] ?? [];
    _restoreDisk();
    load();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Object? id(CatalogJson r) => r[giri ? 'comment_id' : 'id'];

  Future<void> load({bool append = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    final next = append ? page + 1 : 1;
    try {
      final d = await api.readComments(
        giri,
        widget.videoId,
        page: next,
        cursor: append ? cursor : null,
        sort: sort,
      );
      if (!mounted) return;
      final data = catalogList(d[giri ? 'rows' : 'items']);
      setState(() {
        final seen = <Object?>{};
        rows = [
          if (append) ...rows else if (!giri) ...catalogList(d['pinned']),
          ...data,
        ].where((r) => id(r) == null || seen.add(id(r))).toList();
        if (!append) {
          cache[cacheKey] = rows
              .map((r) => publicSourceComment(r, giri: giri))
              .toList();
        }
        if (!giri && !append) {
          final body = catalogMap(d['notice'])['content']?.toString().trim();
          notice = body == null || body.isEmpty ? null : body;
        }
        page = next;
        more = giri
            ? data.isNotEmpty &&
                  next * catalogInt(d['limit'], 20) < catalogInt(d['total'])
            : d['next_cursor'] != null &&
                  d['next_cursor'].toString() != cursor.toString();
        cursor = d['next_cursor'];
      });
      if (!append) {
        await CatalogDiskCache.write(_diskKey, cache[cacheKey] ?? []);
      }
    } catch (_) {
      if (mounted) setState(() => error = '评论加载失败');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadReplies(Object key) async {
    if (!_replyLoading.add(key)) return;
    final epoch = _replyEpoch;
    final disk = 'xifan-comment-replies:${widget.videoId}:$key';
    final append =
        replyCursor.containsKey(key) &&
        replyCursor[key] is! _RetryFirstReplyPage;
    try {
      if (!append && !replies.containsKey(key)) {
        final old = await CatalogDiskCache.read(disk);
        if (!mounted || epoch != _replyEpoch) return;
        if (old != null && old.isNotEmpty) setState(() => replies[key] = old);
      }
      final d = await api.readComments(
        false,
        widget.videoId,
        parent: key,
        cursor: append ? replyCursor[key] : null,
      );
      if (!mounted || epoch != _replyEpoch) return;
      final seen = <Object?>{};
      final next = [
        if (append) ...?replies[key],
        ...catalogList(d['items']),
      ].where((r) => id(r) == null || seen.add(id(r))).toList();
      setState(() {
        replies[key] = next;
        if (d['next_cursor'] case final Object after
            when after.toString() != replyCursor[key].toString()) {
          replyCursor[key] = after;
        } else {
          replyCursor.remove(key);
        }
      });
      await CatalogDiskCache.write(
        disk,
        next.map((r) => publicSourceComment(r, giri: false)).toList(),
      );
    } catch (_) {
      if (mounted && epoch == _replyEpoch) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('回复加载失败')));
        if (!append && replies.containsKey(key))
          setState(() => replyCursor[key] = const _RetryFirstReplyPage());
      }
    } finally {
      _replyLoading.remove(key);
    }
  }

  Future<void> mutate(Future<void> Function() action, {bool clear = false}) =>
      runCatalogAction(
        busy: saving || loading,
        active: () => mounted,
        setBusy: (value) => setState(() => saving = value),
        action: () async {
          await action();
          if (!mounted) return;
          if (clear) {
            input.clear();
            parent = null;
          }
          _replyEpoch++;
          replies.clear();
          replyCursor.clear();
          await load();
        },
        onError: (error) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error is StateError ? error.message : '评论操作失败'),
          ),
        ),
      );

  Widget card(CatalogJson r, {bool nested = false}) {
    final key = id(r);
    final name =
        (giri ? r['comment_name'] : catalogMap(r['author'])['name']) ?? '用户';
    final body = r[giri ? 'comment_content' : 'content'] ?? '';
    final time = sourceCommentDate(r[giri ? 'comment_time' : 'created_at']);

    final children = giri ? catalogList(r['chile_list']) : replies[key] ?? [];
    return CatalogCommentCard(
      author: name.toString(),
      content: body.toString(),
      date: time,
      pinned: r['is_pinned'] == true,
      actions: [
        if (key != null)
          Wrap(
            children: [
              TextButton(
                onPressed: () => setState(() => parent = key),
                child: const Text('回复'),
              ),
              if (!giri) ...[
                if (!nested &&
                    catalogInt(r['reply_count']) > 0 &&
                    (!replies.containsKey(key) || replyCursor.containsKey(key)))
                  TextButton(
                    onPressed: () => loadReplies(key),
                    child: Text('查看回复 (${r['reply_count'] ?? 0})'),
                  ),
                for (final (reaction, label) in [
                  ('like', '赞'),
                  ('dislike', '踩'),
                ])
                  TextButton(
                    onPressed: () => mutate(
                      () => api.xifanCommentAction('toggle_comment_reaction', {
                        'p_comment_id': key,
                        'p_reaction': reaction,
                      }),
                    ),
                    child: Text(
                      reaction == 'like'
                          ? '$label ${catalogInt(r['like_count'])}'
                          : label,
                    ),
                  ),
                if (r['is_mine'] == true)
                  TextButton(
                    onPressed: () => mutate(
                      () => api.xifanCommentAction('delete_own_comment', {
                        'p_comment_id': key,
                      }),
                    ),
                    child: const Text('删除'),
                  ),
              ],
            ],
          ),
      ],
      replies: [
        if (!nested)
          for (final child in children) card(child, nested: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CatalogCommentHeader(
        title: giri ? 'GiriGiri 评论' : '稀饭评论',
        sort: !giri
            ? DropdownButton<String>(
                value: sort,
                items: const [
                  DropdownMenuItem(value: 'latest', child: Text('最新')),
                  DropdownMenuItem(value: 'most_liked', child: Text('最多赞')),
                  DropdownMenuItem(value: 'most_replies', child: Text('最多回复')),
                ],
                onChanged: loading
                    ? null
                    : (v) {
                        if (v == null || v == sort) return;
                        setState(() {
                          sort = v;
                          rows = cache[cacheKey] ?? [];
                          cursor = null;
                          page = 0;
                          more = false;
                        });
                        _restoreDisk();
                        load();
                      },
              )
            : null,
        refresh: loading ? null : () => load(),
      ),
      if (notice != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(notice!),
          ),
        ),
      if (parent != null)
        Align(
          alignment: Alignment.centerLeft,
          child: InputChip(
            label: const Text('回复评论'),
            onDeleted: () => setState(() => parent = null),
          ),
        ),
      CatalogCommentComposer(
        controller: input,
        busy: saving,
        send: loading
            ? null
            : () {
                final value = input.text.trim();
                if (value.isNotEmpty)
                  mutate(
                    () => api.postComment(
                      giri,
                      widget.videoId,
                      value,
                      parent: parent,
                    ),
                    clear: true,
                  );
              },
      ),
      if (loading && rows.isEmpty) const LinearProgressIndicator(),
      if (error != null && rows.isEmpty)
        CatalogError(error: error!, retry: () => load()),
      if (!loading && error == null && rows.isEmpty) const Text('暂无评论'),
      for (final row in rows) card(row),
      CatalogLoadMore(
        loading: loading && rows.isNotEmpty,
        hasMore: more,
        error: rows.isNotEmpty ? error : null,
        loadMore: () => load(append: page > 0),
      ),
    ],
  );
}

class _RetryFirstReplyPage {
  const _RetryFirstReplyPage();
}
