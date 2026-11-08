import 'cycani_api.dart';
import 'catalog_models.dart';
import 'site_native_catalog.dart';

class CatalogPlaybackResolver {
  const CatalogPlaybackResolver(this.matches, this.resolve);
  final bool Function(String) matches;
  final Future<String> Function(String) resolve;
}

abstract final class CatalogPlaybackResolvers {
  static final adapters = <CatalogPlaybackResolver>[
    CatalogPlaybackResolver(
      (url) => cycaniSectionId(url) != null,
      (url) => CycaniApi.instance.playUrl(cycaniSectionId(url)!),
    ),
    CatalogPlaybackResolver(
      (url) => NativeCatalogApi.xifanEpisode(url) != null,
      (url) {
        final id = NativeCatalogApi.xifanEpisode(url)!;
        // 源线路页地址带 #src=K 片段：优先探测第 K 个候选源。
        final prefer = int.tryParse(
              (Uri.tryParse(url)?.fragment ?? '').split('=').last,
            ) ??
            0;
        return NativeCatalogApi.instance.xifanPlayback(
          id.$1,
          id.$2,
          preferCandidate: prefer,
        );
      },
    ),
    CatalogPlaybackResolver(
      (url) => NativeCatalogApi.giriMedia(url) != null,
      (url) async => NativeCatalogApi.giriMedia(url)!.toString(),
    ),
  ];
  static CatalogPlaybackResolver? forUrl(String url) =>
      adapters.where((a) => a.matches(url)).firstOrNull;
}
