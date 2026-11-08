import 'catalog_snapshot.dart';
import 'cycani_week_selector.dart';
import 'cycani_catalog_sources.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'cycani_api.dart';
import 'cycani_models.dart';
import 'cycani_feed_widgets.dart';
import 'cycani_catalog_disk_cache.dart';

/// The homepage's calendar and rankings are independent from recommendation
/// loading; a failed secondary request must not blank the rest of the homepage.
class CycaniHomeOverview extends StatefulWidget {
  const CycaniHomeOverview({
    super.key,
    this.api,
    this.revision = 0,
    required this.onWeek,
    required this.onRanking,
  });
  final CycaniApi? api;
  final int revision;
  final ValueChanged<int> onWeek;
  final ValueChanged<String> onRanking;

  @override
  State<CycaniHomeOverview> createState() => _CycaniHomeOverviewState();
}

class _CycaniHomeOverviewState extends State<CycaniHomeOverview> {
  CycaniApi get api => widget.api ?? CycaniApi.instance;
  int day = DateTime.now().weekday;
  String ranking = 'TV番组';
  final _requests = <String, Future<List<CycaniJson>>>{};
  final _rows = <String, List<CycaniJson>>{};
  static final _recent = <String, List<CycaniJson>>{};

  String get weekKey => 'cycani-home-week:$day';
  String get rankKey => 'cycani-home-rank:$ranking';

  bool _restored = false;
  static const _selectionKey = 'cycani-home-overview-selection';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    final saved = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _selectionKey);
    if (saved is Map) {
      final savedDay = saved['day'];
      if (savedDay is int && savedDay >= 1 && savedDay <= 7) day = savedDay;
      if (const ['TV番组', '剧场番组'].contains(saved['ranking'])) {
        ranking = saved['ranking'] as String;
      }
    }
    _request(weekKey);
    _request(rankKey);
  }

  void _rememberSelection() => PageStorage.maybeOf(context)?.writeState(
    context,
    {'day': day, 'ranking': ranking},
    identifier: _selectionKey,
  );

  @override
  void didUpdateWidget(covariant CycaniHomeOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      _requests.clear();
      _rows.clear();
      _request(weekKey);
      _request(rankKey);
    } else if (oldWidget.revision != widget.revision) {
      _request(weekKey, refresh: true);
      _request(rankKey, refresh: true);
    }
  }

  Future<List<CycaniJson>> _fetch(String key) async {
    if (key.startsWith('cycani-home-week:')) {
      final groups = await api.schedule(int.parse(key.split(':').last));
      return groups.expand((g) => cycaniList(g['videos'])).take(12).toList();
    }
    final name = key.split(':').last;
    return (await CycaniCatalogSources(
      cycani: api,
    ).ranking(CatalogSource.cycani, movie: name == '剧场番组')).take(12).toList();
  }

  void _request(String key, {bool refresh = false}) {
    if (!refresh && _requests.containsKey(key)) return;
    if (widget.api == null && !_rows.containsKey(key)) {
      if (_recent[key] case final rows?) _rows[key] = rows;
      unawaited(
        restoreCatalogSnapshot(
          key,
          canApply: () => mounted && !_rows.containsKey(key),
          apply: (rows) => setState(() => _rows[key] = rows),
        ),
      );
    }
    late final Future<List<CycaniJson>> request;
    request = _fetch(key).then((rows) {
      if (mounted && identical(_requests[key], request)) {
        _rows[key] = rows;
        if (widget.api == null) {
          _recent[key] = rows;
          unawaited(CatalogDiskCache.write(key, rows));
        }
      }
      return rows;
    });
    _requests[key] = request;
  }

  Widget _section(
    String key,
    String title,
    Widget filters,
    VoidCallback more,
  ) => SliverMainAxisGroup(
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              TextButton(onPressed: more, child: const Text('查看更多')),
              IconButton(
                tooltip: '刷新$title',
                onPressed: () => setState(() => _request(key, refresh: true)),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(child: filters),
      FutureBuilder<List<CycaniJson>>(
        key: ValueKey(key),
        future: _requests[key],
        builder: (context, snapshot) {
          final rows = snapshot.data ?? _rows[key];
          if (rows != null && rows.isNotEmpty) {
            return CycaniVideoSliver(items: rows, horizontal: true);
          }
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: rows != null
                    ? const Text('暂无番剧')
                    : snapshot.hasError
                    ? TextButton(
                        onPressed: () =>
                            setState(() => _request(key, refresh: true)),
                        child: const Text('加载失败，重试'),
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
          );
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      _section(
        weekKey,
        '追番周表',
        CatalogWeekPicker(
          day: day,
          onChanged: (value) => setState(() {
            day = value;
            _rememberSelection();
            _request(weekKey);
          }),
        ),
        () => widget.onWeek(day),
      ),
      _section(
        rankKey,
        '排行榜',
        Wrap(
          spacing: 6,
          children: [
            for (final name in const ['TV番组', '剧场番组'])
              ChoiceChip(
                label: Text(name),
                selected: ranking == name,
                onSelected: (_) => setState(() {
                  ranking = name;
                  _rememberSelection();
                  _request(rankKey);
                }),
              ),
          ],
        ),
        () => widget.onRanking(ranking),
      ),
    ],
  );
}
