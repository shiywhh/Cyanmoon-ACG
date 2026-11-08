import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:hive_ce/hive.dart';
import 'package:cyanmoon_acg/services/logging/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cyanmoon_acg/modules/bangumi/bangumi_item.dart';
import 'package:cyanmoon_acg/hive_registrar.g.dart';
import 'package:cyanmoon_acg/modules/history/history_module.dart';
import 'package:cyanmoon_acg/modules/collect/collect_module.dart';
import 'package:cyanmoon_acg/modules/collect/collect_change_module.dart';
import 'package:cyanmoon_acg/modules/search/search_history_module.dart';
import 'package:cyanmoon_acg/modules/download/download_module.dart';
import 'package:cyanmoon_acg/services/storage/history_storage_coordinator.dart';
import 'package:cyanmoon_acg/services/download/download_path_migration.dart';

import 'package:cyanmoon_acg/services/storage/settings_keys.dart';
export 'package:cyanmoon_acg/services/storage/settings_keys.dart';

class GStorage {
  /// Don't use favorites box, it's replaced by collectibles.
  static late Box<BangumiItem> favorites;
  static late Box<CollectedBangumi> collectibles;
  static late Box<History> histories;
  static late Box<CollectedBangumiChange> collectChanges;
  static late Box<String> shieldList;
  static late final Box<dynamic> _setting;
  static late Box<SearchHistory> searchHistory;
  static late Box<DownloadRecord> downloads;

  /// Hive directory path, initialized during init()
  static String? _hivePath;

  /// Queue to serialize write operations
  static Future<void> _collectChangesWriteQueue = Future.value();

  /// Next ID
  static int _nextCollectChangeId = 0;

  /// Flag to indicate if the next ID has initialized
  static bool _collectChangeIdInitialized = false;

  /// Ensure collect-related write sequentially
  static Future<T> _runCollectChangesWriteExclusive<T>(
    Future<T> Function() action,
  ) {
    final completer = Completer<T>();
    final previousWrite = _collectChangesWriteQueue;

    _collectChangesWriteQueue = (() async {
      try {
        await previousWrite;
      } catch (_) {}

      try {
        completer.complete(await action());
      } catch (e, stackTrace) {
        completer.completeError(e, stackTrace);
      }
    })();

    return completer.future;
  }

  /// init id generator
  static void _initializeNextCollectChangeIdLocked() {
    if (_collectChangeIdInitialized) {
      return;
    }

    var maxExistingId = 0;
    for (final key in collectChanges.keys) {
      if (key is int && key > maxExistingId) {
        maxExistingId = key;
      }
    }

    _nextCollectChangeId = maxExistingId;
    _collectChangeIdInitialized = true;
  }

  /// 设备槽位（0..7）：跨设备区分同一秒内产生的收藏变更 ID。
  /// 纯秒级时间戳在两台设备同一秒各写一条变更时会撞号，合并端据此把
  /// 本地变更误判为"已在远端"而静默丢弃（数据丢失）。
  static int? _collectChangeDeviceSlot;

  static int _collectChangeDeviceSlotLocked() {
    final cached = _collectChangeDeviceSlot;
    if (cached != null) {
      return cached;
    }
    const slotKey = 'collectChangeDeviceSlot';
    final stored = _setting.get(slotKey);
    int slot;
    if (stored is int && stored >= 0 && stored < 8) {
      slot = stored;
    } else {
      slot = Random.secure().nextInt(8);
      _setting.put(slotKey, slot);
    }
    _collectChangeDeviceSlot = slot;
    return slot;
  }

  /// Generate id for collect change
  ///
  /// 新 ID 编码：`(UTC 秒 - 2024 纪元) * 8 + 设备槽位`，uint32 上限内可用到约
  /// 2041 年，同秒跨设备由槽位区分。本地已有更大 ID（历史遗留/远端同步）时
  /// 从 max+1 单调递增，保证 ID 不回退（保持与遗留数据的单调关系）。
  static int _generateCollectChangeIdLocked() {
    _initializeNextCollectChangeIdLocked();

    const schemeEpoch = 1704067200; // 2024-01-01 UTC
    final secondsSinceEpoch =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - schemeEpoch;
    final schemeId =
        secondsSinceEpoch > 0 ? secondsSinceEpoch * 8 : 0;
    final slotSchemeId = schemeId + _collectChangeDeviceSlotLocked();
    var nextId =
        slotSchemeId > _nextCollectChangeId ? slotSchemeId : _nextCollectChangeId + 1;
    while (collectChanges.containsKey(nextId)) {
      nextId++;
    }
    _nextCollectChangeId = nextId;
    return nextId;
  }

  /// Append a new collect change
  static Future<CollectedBangumiChange> appendCollectChange({
    required int bangumiId,
    required int action,
    required int type,
    int? timestamp,
  }) {
    return _runCollectChangesWriteExclusive(() async {
      final change = CollectedBangumiChange(
        _generateCollectChangeIdLocked(),
        bangumiId,
        action,
        type,
        timestamp ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      );
      await collectChanges.put(change.id, change);
      await collectChanges.flush();
      return change;
    });
  }

  /// Update an existing collect change
  static Future<void> putCollectChange(CollectedBangumiChange change) {
    return _runCollectChangesWriteExclusive(() async {
      _initializeNextCollectChangeIdLocked();
      if (change.id > _nextCollectChangeId) {
        _nextCollectChangeId = change.id;
      }
      await collectChanges.put(change.id, change);
      await collectChanges.flush();
    });
  }

  /// Put a collectible using the same write queue
  static Future<void> putCollectible(CollectedBangumi collectible) {
    return _runCollectChangesWriteExclusive(() async {
      await collectibles.put(collectible.bangumiItem.id, collectible);
      await collectibles.flush();
    });
  }

  /// Delete a collectible using the shared collect write queue.
  static Future<void> deleteCollectible(int bangumiId) {
    return _runCollectChangesWriteExclusive(() async {
      await collectibles.delete(bangumiId);
      await collectibles.flush();
    });
  }

  static Future init() async {
    _hivePath = '${(await getApplicationSupportDirectory()).path}/hive';

    Hive.registerAdapters();

    // Open each box with automatic recovery on corruption
    favorites = await _openBoxSafe<BangumiItem>('favorites');
    collectibles = await _openBoxSafe<CollectedBangumi>('collectibles');
    histories = await _openBoxSafe<History>('histories');
    _setting = await _openBoxSafe<dynamic>('setting');
    if (_setting.get('qingyue.baidu-images.v1') != true) {
      await _setting.put('imageAcceleration', 'baidu');
      await _setting.put('qingyue.baidu-images.v1', true);
    }
    collectChanges = await _openBoxSafe<CollectedBangumiChange>(
      'collectchanges',
    );
    shieldList = await _openBoxSafe<String>('shieldList');
    searchHistory = await _openBoxSafe<SearchHistory>('searchHistory');
    downloads = await _openBoxSafe<DownloadRecord>('downloads');
    if (Platform.isIOS) {
      await rebaseIosDownloadPaths(downloads);
    }
  }

  /// Open a Hive box with automatic recovery on corruption.
  ///
  /// 仅对真正的 Hive 数据损坏（HiveError，如校验和失败）执行删除重建；
  /// 其他异常（文件被杀软/备份进程短暂占用、瞬时 IO 错误等）先重试一次，
  /// 仍失败则向上抛出交给错误页处理，避免把 favorites/histories 等用户数据
  /// 无差别删除且不可恢复。
  static Future<Box<T>> _openBoxSafe<T>(String boxName) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await Hive.openBox<T>(boxName);
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    final e = lastError!;
    CyanmoonLogger().e(
      'GStorage: Box "$boxName" failed to open',
      error: e,
    );
    if (e is! HiveError) {
      throw e;
    }
    CyanmoonLogger().w(
      'GStorage: Box "$boxName" corrupted, attempting recovery',
    );

    // Delete the corrupted box files
    await _deleteBoxFiles(boxName);

    // Try to open again (will create a new empty box)
    try {
      final box = await Hive.openBox<T>(boxName);
      CyanmoonLogger().i(
        'GStorage: Box "$boxName" recovered successfully (data lost)',
      );
      return box;
    } catch (e2) {
      CyanmoonLogger().e(
        'GStorage: Failed to recover box "$boxName"',
        error: e2,
      );
      rethrow;
    }
  }

  /// Delete Hive box files for a given box name
  static Future<void> _deleteBoxFiles(String boxName) async {
    if (_hivePath == null) return;

    final boxFile = File('$_hivePath/$boxName.hive');
    final lockFile = File('$_hivePath/$boxName.lock');

    try {
      if (await boxFile.exists()) {
        await boxFile.delete();
        CyanmoonLogger().i('GStorage: Deleted corrupted box file: $boxName.hive');
      }
      if (await lockFile.exists()) {
        await lockFile.delete();
        CyanmoonLogger().i('GStorage: Deleted lock file: $boxName.lock');
      }
    } catch (e) {
      CyanmoonLogger().e(
        'GStorage: Failed to delete box files for "$boxName"',
        error: e,
      );
    }
  }

  static Future<void> backupBox(String boxName, String backupFilePath) async {
    final appDocumentDir = await getApplicationSupportDirectory();
    final hiveBoxFile = File('${appDocumentDir.path}/hive/$boxName.hive');
    if (await hiveBoxFile.exists()) {
      await hiveBoxFile.copy(backupFilePath);
      CyanmoonLogger().i('GStorage: backup success: $backupFilePath');
    } else {
      CyanmoonLogger().w('GStorage: Hive box does not exist: $boxName');
    }
  }

  static Future<void> patchHistory(String backupFilePath) async {
    final backupFile = File(backupFilePath);
    final backupContent = await backupFile.readAsBytes();
    final tempBox = await Hive.openBox('tempHistoryBox', bytes: backupContent);
    try {
      final tempBoxItems = tempBox.toMap().entries;
      await HistoryStorageCoordinator().run(() async {
        for (final tempBoxItem in tempBoxItems) {
          final tempHistory = tempBoxItem.value as History;
          tempHistory.entryKind = HistoryEntryKind.normalize(
            tempHistory.entryKind,
          );
          final targetKey = tempHistory.key;
          final existing = histories.get(targetKey);
          if (existing == null ||
              existing.lastWatchTime.isBefore(tempHistory.lastWatchTime)) {
            await histories.put(targetKey, tempHistory);
          }
        }
      });
    } finally {
      await tempBox.close();
    }
  }


  static T getSetting<T>(
    SettingKey<T> key, {
    SettingContext context = const SettingContext(),
  }) {
    final defaultValue = key.resolveDefault(context);
    final storedValue = _setting.get(key.name);
    if (storedValue is T) {
      return storedValue;
    }
    return defaultValue;
  }

  static Future<void> putSetting<T>(SettingKey<T> key, T value) async {
    await _setting.put(key.name, value);
  }

  static Stream<void> watchSettings(Iterable<SettingKey<Object?>> keys) {
    final names = keys.map((key) => key.name).toSet();
    return _setting
        .watch()
        .where((event) => names.contains(event.key))
        .map((_) {});
  }

  static List<String> getStringListSettingByName(
    String key, {
    List<String> defaultValue = const [],
  }) {
    final storedValue = _setting.get(key);
    if (storedValue is List) {
      return storedValue.whereType<String>().toList();
    }
    return defaultValue;
  }

  static Future<void> putStringListSettingByName(
    String key,
    List<String> value,
  ) async {
    await _setting.put(key, value);
  }

  static Future<void> resetSettings(Iterable<SettingKey<Object?>> keys) async {
    await _setting.deleteAll(keys.map((key) => key.name));
    await _setting.flush();
  }

  static Future<void> resetPlayerSettings() async {
    await resetSettings(SettingsKeys.byGroup(SettingGroup.player));
  }

  static Future<void> resetDanmakuSettings() async {
    await resetSettings(SettingsKeys.byGroup(SettingGroup.danmaku));
  }

  GStorage._();
}
