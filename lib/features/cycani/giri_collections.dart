import 'qingyue_home_page.dart' show catalogConfirm, CatalogError;
import 'package:flutter/material.dart';
import 'catalog_detail_page.dart';
import 'catalog_models.dart';
import 'site_accounts.dart';

class GiriCollectionsPage extends StatefulWidget {
  const GiriCollectionsPage({super.key, this.addVideoId, this.accountApi});
  final SourceAccounts? accountApi;
  final int? addVideoId;

  @override
  State<GiriCollectionsPage> createState() => _GiriCollectionsPageState();
}

class _GiriCollectionsPageState extends State<GiriCollectionsPage> {
  SourceAccounts get api => widget.accountApi ?? SourceAccounts.instance;
  int _generation = 0;
  List<CatalogJson> groups = [];
  final previews = <int, List<CatalogJson>>{};
  int? group;
  String? name, error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final selected = group;
    final session = api.librarySession(true), generation = ++_generation;
    bool current() =>
        mounted &&
        group == selected &&
        generation == _generation &&
        session == api.librarySession(true);
    setState(() {
      loading = true;
      error = null;
    });
    api.cachedGiriCollections(selected).then((cached) {
      if (!current() || !loading || cached == null) return;
      if (selected == null && groups.isNotEmpty ||
          selected != null && previews.containsKey(selected))
        return;
      setState(() {
        if (selected == null) {
          groups = cached;
        } else {
          previews[selected] = cached;
        }
      });
    });
    try {
      final rows = selected == null
          ? await api.giriCollectionGroups()
          : await api.giriCollectionItems(selected);
      if (!current()) return;
      await api.saveGiriCollections(selected, rows, expectedSession: session);
      if (!current()) return;
      setState(() {
        if (selected == null) {
          groups = rows;
        } else {
          previews[selected] = rows;
        }
      });
    } catch (e) {
      if (current())
        setState(() => error = e is StateError ? e.message : '收藏夹加载失败');
    } finally {
      if (mounted && generation == _generation)
        setState(() {
          loading = false;
          if (session != api.librarySession(true)) {
            groups = [];
            previews.clear();
            error = '请重新登录 GiriGiri';
          }
        });
    }
  }

  Future<void> _mutate(
    Future<void> Function() action, {
    bool close = false,
  }) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await action();
      if (!mounted) return;
      if (close) {
        Navigator.pop(context);
      } else {
        await _load();
      }
    } catch (e) {
      if (mounted)
        setState(() => error = e is StateError ? e.message : '收藏操作失败');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _create() async {
    var text = '';
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建收藏夹'),
        content: TextField(
          autofocus: true,
          onChanged: (v) => text = v,
          maxLength: 40,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (mounted && label != null && label.isNotEmpty)
      await _mutate(() => api.createGiriCollection(label));
  }

  Future<void> _delete(String title, Future<void> Function() action) async {
    final yes = await catalogConfirm(context, title);
    if (mounted && yes == true) await _mutate(action);
  }

  void _back() {
    if (group == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      group = null;
      name = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final active = group;
    final items = active == null
        ? groups
        : previews[active] ?? const <CatalogJson>[];
    return PopScope(
      canPop: active == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && active != null) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _back),
          title: Text(name ?? (widget.addVideoId == null ? '收藏夹' : '添加到收藏夹')),
          actions: [
            if (active == null)
              IconButton(
                tooltip: '新建收藏夹',
                onPressed: loading ? null : _create,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (loading) const LinearProgressIndicator(),
              if (error != null) CatalogError(error: error!, retry: _load),
              if (items.isEmpty && !loading && error == null)
                const Center(child: Text('暂无内容')),
              for (final row in items)
                if (active == null)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text((row['group_name'] ?? '收藏夹').toString()),
                    onTap: () {
                      final id = catalogInt(row['id'] ?? row['group_id']);
                      if (id <= 0 || loading) return;
                      if (widget.addVideoId case final video?) {
                        _mutate(
                          () => api.addGiriCollectionItem(id, video),
                          close: true,
                        );
                      } else {
                        setState(() {
                          group = id;
                          name = row['group_name']?.toString();
                        });
                        _load();
                      }
                    },
                    trailing: widget.addVideoId != null
                        ? null
                        : IconButton(
                            tooltip: '删除收藏夹',
                            onPressed: () => _delete(
                              '删除收藏夹？',
                              () => api.removeGiriCollection(
                                catalogInt(row['id'] ?? row['group_id']),
                              ),
                            ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                  )
                else
                  ListTile(
                    title: Text((row['vod_name'] ?? '').toString()),
                    onTap: () {
                      final id = catalogInt(row['vod_id']);
                      if (id <= 0) return;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CatalogDetailPage(
                            row: {
                              'video_id': id,
                              'title': row['vod_name'],
                              'cover_url': row['vod_pic'],
                              'catalog_source': 'giri',
                            },
                          ),
                        ),
                      );
                    },
                    trailing: IconButton(
                      tooltip: '移出收藏夹',
                      onPressed: () => _delete(
                        '移出收藏夹？',
                        () => api.removeGiriCollectionItem(
                          active,
                          catalogInt(row['vod_id']),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
