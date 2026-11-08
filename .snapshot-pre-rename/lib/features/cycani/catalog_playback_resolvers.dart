import 'cycani_api.dart';
import 'cycani_models.dart';
import 'cycani_native_catalog.dart';

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
        return NativeCatalogApi.instance.xifanPlayback(id.$1, id.$2);
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
