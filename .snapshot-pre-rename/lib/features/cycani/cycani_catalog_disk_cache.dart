import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'cycani_models.dart';

/// Disk snapshots are for public catalogue data only.
class CatalogDiskCache {
  CatalogDiskCache._();
  static const _maxBytes = 512 * 1024;
  static const _maxAge = Duration(days: 7);
  static DateTime? _lastPrune;
  static final _writing = <String, Future<void>>{};

  static Future<File> _file(String key) async {
    final directory = await getTemporaryDirectory();
    final id = sha256.convert(utf8.encode(key)).toString();
    return File(
      '${directory.path}${Platform.pathSeparator}catalog-v2-$id.json',
    );
  }

  static Future<List<CycaniJson>?> read(String key) async {
    try {
      final file = await _file(key);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size >
              (key.startsWith('danmaku.channel.')
                  ? 4 * 1024 * 1024
                  : _maxBytes) ||
          DateTime.now().difference(stat.modified) > _maxAge)
        return null;
      final value = jsonDecode(await file.readAsString());
      return value is List ? cycaniList(value) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _prune(Directory directory) async {
    final now = DateTime.now();
    if (_lastPrune != null &&
        now.difference(_lastPrune!) < const Duration(minutes: 1))
      return;
    _lastPrune = now;
    final files = <(File, DateTime)>[];
    await for (final item in directory.list()) {
      if (item is! File ||
          !RegExp(r'catalog-v2-[0-9a-f]{64}\.json$').hasMatch(item.path))
        continue;
      final stat = await item.stat();
      files.add((item, stat.modified));
    }
    files.sort((a, b) => b.$2.compareTo(a.$2));
    for (final (i, entry) in files.indexed) {
      if (i >= 200 || now.difference(entry.$2) > _maxAge) {
        try {
          await entry.$1.delete();
        } catch (_) {}
      }
    }
  }

  static Future<void> write(String key, List<CycaniJson> rows) {
    final previous = _writing[key] ?? Future.value();
    final task = previous.then((_) async {
      try {
        final bytes = utf8.encode(jsonEncode(rows));
        if (bytes.length >
            (key.startsWith('danmaku.channel.') ? 4 * 1024 * 1024 : _maxBytes))
          return;
        final file = await _file(key);
        final temp = File('${file.path}.tmp');
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(file.path);
        await _prune(file.parent);
      } catch (_) {
        // Public snapshots never block the network-backed view.
      }
    });
    _writing[key] = task;
    return task.whenComplete(() {
      if (identical(_writing[key], task)) _writing.remove(key);
    });
  }
}
