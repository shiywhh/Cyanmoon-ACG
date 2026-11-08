import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/cycani_catalog_sources.dart';
import 'package:kazumi/features/cycani/cycani_models.dart';

void main() {
  test(
    'Xifan official ranking parser respects rank, deduplicates and ignores recommendations',
    () {
      expect(
        CycaniCatalogSources.xifanRankingIds('''
      <a aria-label="第 2 名 第二名" href="/anime/20">second</a>
      <a aria-label="第 1 名 第一名" href="/anime/10">first</a>
      <a aria-label="第 1 名 第一名" href="/anime/10">mobile duplicate</a>
      <a aria-label="推荐番剧" href="/anime/80">not ranked</a>
    '''),
        [10, 20],
      );
    },
  );
  test('live rankings use both official ranking data sources', () async {
    final api = CycaniCatalogSources.instance;
    final x = await api.xifanWeeklyRanking();
    final groups = await api.giriRankingGroups();
    expect(x, isNotEmpty);
    expect(groups, isNotEmpty);
    final g = await api.giriRanking(cycaniInt(groups.first['id']));
    expect(g, isNotEmpty);
    expect(x.every((r) => catalogSource(r) == CatalogSource.xifan), isTrue);
    expect(g.every((r) => catalogSource(r) == CatalogSource.giri), isTrue);
  }, skip: Platform.environment['CYCANI_OFFICIAL_RANK_LIVE'] != '1');
}
