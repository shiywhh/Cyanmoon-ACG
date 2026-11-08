enum CatalogSource {
  cycani('次元城'),
  xifan('稀饭'),
  giri('GiriGiri');

  const CatalogSource(this.label);
  final String label;
  Uri detail(int id) => Uri.parse(switch (this) {
    cycani => 'https://www.cycani.org/video/$id',
    xifan => 'https://next.xifanacg.com/anime/$id',
    giri => 'https://ani.girigirilove.com/detail/$id',
  });
}

/// Source plus raw server ID is the in-memory identity. Legacy numeric IDs
/// remain a persistence codec so existing histories/downloads keep working.
class SiteEntry {
  const SiteEntry(this.source, this.rawId) : assert(rawId > 0);
  final CatalogSource source;
  final int rawId;
  String get key => '${source.name}:$rawId';
  int get legacyId => -(source.index * 1000000000 + rawId);
  static SiteEntry? fromLegacy(int id) {
    if (id >= 0) return null;
    final value = -id, index = -id ~/ 1000000000;
    final raw = value % 1000000000;
    if (index >= CatalogSource.values.length || raw == 0) return null;
    return SiteEntry(CatalogSource.values[index], raw);
  }

  @override
  bool operator ==(Object other) => other is SiteEntry && other.key == key;
  @override
  int get hashCode => Object.hash(source, rawId);
}
