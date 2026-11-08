import 'package:kazumi/plugins/plugins.dart';
import 'catalog_aggregator.dart';
import 'cycani_api.dart';

Plugin catalogPlugin(CatalogSource source) {
  final origin = switch (source) {
    CatalogSource.cycani => '${CycaniApi.origin}/',
    CatalogSource.xifan => 'https://next.xifanacg.com/',
    CatalogSource.giri => 'https://ani.girigirilove.com/',
    // Bangumi 条目不是播放目标（播放经合并后的站点成员解析），不应构造播放插件。
    CatalogSource.bangumi => throw StateError('catalogPlugin: bangumi not playable'),
  };
  return Plugin.fromJson({
    'api': '9',
    'type': 'anime',
    'name': source.label,
    'version': '1.0',
    'baseURL': origin,
    'referer': origin,
    'useWebview': true,
    'useNativePlayer': true,
  });
}
