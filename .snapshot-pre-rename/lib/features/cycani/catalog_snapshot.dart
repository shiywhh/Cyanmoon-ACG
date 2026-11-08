import 'cycani_models.dart';
import 'cycani_catalog_disk_cache.dart';

CycaniJson catalogPickFields(CycaniJson value, Iterable<String> fields) => {
  for (final field in fields)
    if (value.containsKey(field)) field: value[field],
};

/// Stale reads must never overwrite a network result or a newly selected view.
Future<void> restoreCatalogSnapshot(
  String key, {
  required bool Function() canApply,
  required void Function(List<CycaniJson>) apply,
  Future<List<CycaniJson>?> Function(String)? read,
}) async {
  final rows = await (read ?? CatalogDiskCache.read)(key);
  if (rows != null && canApply()) apply(rows);
}
