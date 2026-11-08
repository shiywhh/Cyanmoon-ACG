import 'package:kazumi/plugins/plugins.dart';
import 'catalog_aggregator.dart';
import 'cycani_api.dart';

Plugin catalogPlugin(CatalogSource source) {
  final origin = switch (source) {
    CatalogSource.cycani => '${CycaniApi.origin}/',
    CatalogSource.xifan => 'https://next.xifanacg.com/',
    CatalogSource.giri => 'https://ani.girigirilove.com/',
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
