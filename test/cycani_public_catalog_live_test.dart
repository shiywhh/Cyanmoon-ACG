import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kazumi/features/cycani/catalog_aggregator.dart';
import 'package:kazumi/features/cycani/catalog_models.dart';
import 'package:kazumi/features/cycani/cycani_api.dart';
import 'package:kazumi/features/cycani/site_native_catalog.dart';
import 'package:kazumi/features/cycani/site_accounts.dart';

void main() {
  final realHttp = HttpOverrides.current;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = realHttp;
  FlutterSecureStorage.setMockInitialValues({});
  final enabled = Platform.environment['CATALOG_PUBLIC_LIVE'] == '1';
  final api = CatalogAggregator.instance;
  final skip = enabled ? false : 'Set CATALOG_PUBLIC_LIVE=1 to use live APIs.';

  // Bangumi 不在 live 站点链路测试范围（其数据经 BangumiApi，另有覆盖）。
  for (final source in const [
    CatalogSource.cycani,
    CatalogSource.xifan,
    CatalogSource.giri,
  ]) {
    test(
      '${source.label}: homepage links to readable detail and comments',
      () async {
        final sections = await api.recommendations(source);
        final titles = sections.expand((s) => catalogList(s['videos']));
        final entry = titles.map(CatalogVideo.new).firstWhere((r) => r.id > 0);
        final detail = source == CatalogSource.cycani
            ? await CycaniApi.instance.detail(entry.id)
            : (await NativeCatalogApi.instance.detail(source, entry.id)).video;
        final offset = switch (source) {
          CatalogSource.cycani => 0,
          CatalogSource.xifan => 1000000000,
          CatalogSource.giri => 2000000000,
          CatalogSource.bangumi => 3000000000,
        };
        expect(detail.id, entry.id + offset);
        expect(detail.title, isNot(anyOf(isEmpty, '未命名番剧')));
        final comments = source == CatalogSource.cycani
            ? await CycaniApi.instance.comments(entry.id)
            : await SourceAccounts.instance.readComments(
                source == CatalogSource.giri,
                entry.id,
              );
        expect(
          comments['items'] ?? comments['rows'] ?? comments['list'],
          isA<List>(),
        );
      },
      skip: skip,
    );
    test('${source.label}: official ranking contains titles', () async {
      final rows = switch (source) {
        CatalogSource.cycani => await api.ranking(source, movie: false),
        CatalogSource.xifan => await api.xifanWeeklyRanking(),
        CatalogSource.giri => await api.giriRanking(
          catalogInt((await api.giriRankingGroups()).first['id']),
        ),
        CatalogSource.bangumi => const <Map<String, dynamic>>[],
      };
      expect(rows.where((r) => CatalogVideo(r).id > 0), isNotEmpty);
    }, skip: skip);
  }
}
