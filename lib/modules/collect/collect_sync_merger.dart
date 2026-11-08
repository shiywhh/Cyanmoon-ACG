import 'package:cyanmoon_acg/modules/bangumi/bangumi_collection.dart';
import 'package:cyanmoon_acg/modules/bangumi/sync_priority.dart';
import 'package:cyanmoon_acg/modules/collect/collect_change_module.dart';
import 'package:cyanmoon_acg/modules/collect/collect_module.dart';
import 'package:cyanmoon_acg/modules/collect/collect_type_mapper.dart';

class CollectiblesMergeResult {
  const CollectiblesMergeResult({
    required this.collectibles,
    required this.changes,
  });

  final List<CollectedBangumi> collectibles;
  final List<CollectedBangumiChange> changes;
}

class BangumiUploadMutation {
  const BangumiUploadMutation({
    required this.bangumiId,
    required this.type,
  });

  final int bangumiId;
  final int type;
}

class BangumiLocalMutation {
  const BangumiLocalMutation({
    required this.collectible,
    required this.changeAction,
  });

  final CollectedBangumi collectible;
  final int changeAction;
}

class BangumiCollectiblesMergePlan {
  const BangumiCollectiblesMergePlan({
    required this.localOnlyUploads,
    required this.remoteOnlyPuts,
    required this.conflictUploads,
    required this.conflictLocalUpdates,
  });

  final List<BangumiUploadMutation> localOnlyUploads;
  final List<BangumiLocalMutation> remoteOnlyPuts;
  final List<BangumiUploadMutation> conflictUploads;
  final List<BangumiLocalMutation> conflictLocalUpdates;

  int get totalOperations =>
      localOnlyUploads.length +
      remoteOnlyPuts.length +
      conflictUploads.length +
      conflictLocalUpdates.length;
}

class CollectSyncMerger {
  static BangumiCollectiblesMergePlan planBangumi({
    required List<CollectedBangumi> localCollectibles,
    required List<BangumiCollection> remoteCollections,
    required BangumiSyncPriority priority,
  }) {
    final localMap = {
      for (final item in localCollectibles) item.bangumiItem.id: item,
    };
    final remoteMap = <int, BangumiCollection>{};
    for (final item in remoteCollections) {
      final remoteCollectType = item.type.toCollectType();
      if (!remoteCollectType.isCollected) {
        continue;
      }
      remoteMap[item.bangumiId] = item;
    }

    final localOnlyIds = localMap.keys
        .toSet()
        .difference(remoteMap.keys.toSet())
        .toList()
      ..sort();
    final remoteOnlyIds = remoteMap.keys
        .toSet()
        .difference(localMap.keys.toSet())
        .toList()
      ..sort();
    final sharedIds = localMap.keys
        .toSet()
        .intersection(remoteMap.keys.toSet())
        .toList()
      ..sort();
    final mismatchIds = <int>[];
    for (final id in sharedIds) {
      if (localMap[id]!.type != remoteMap[id]!.type.toCollectType().value) {
        mismatchIds.add(id);
      }
    }

    final localOnlyUploads = [
      for (final id in localOnlyIds)
        BangumiUploadMutation(bangumiId: id, type: localMap[id]!.type),
    ];
    final remoteOnlyPuts = [
      for (final id in remoteOnlyIds)
        BangumiLocalMutation(
          collectible: _fromBangumiCollection(remoteMap[id]!),
          changeAction: 1,
        ),
    ];

    final conflictUploads = <BangumiUploadMutation>[];
    final conflictLocalUpdates = <BangumiLocalMutation>[];
    if (priority == BangumiSyncPriority.localFirst) {
      for (final id in mismatchIds) {
        conflictUploads.add(
          BangumiUploadMutation(bangumiId: id, type: localMap[id]!.type),
        );
      }
    } else if (priority == BangumiSyncPriority.bangumiFirst) {
      for (final id in mismatchIds) {
        conflictLocalUpdates.add(
          BangumiLocalMutation(
            collectible: _fromBangumiCollection(remoteMap[id]!),
            changeAction: 2,
          ),
        );
      }
    } else if (priority == BangumiSyncPriority.timeFirst) {
      for (final id in mismatchIds) {
        final localTime = localMap[id]!.time;
        final remoteTime = remoteMap[id]!.updatedAt;
        if (localTime.isAfter(remoteTime) ||
            localTime.isAtSameMomentAs(remoteTime)) {
          conflictUploads.add(
            BangumiUploadMutation(bangumiId: id, type: localMap[id]!.type),
          );
        } else {
          conflictLocalUpdates.add(
            BangumiLocalMutation(
              collectible: _fromBangumiCollection(remoteMap[id]!),
              changeAction: 2,
            ),
          );
        }
      }
    }

    return BangumiCollectiblesMergePlan(
      localOnlyUploads: localOnlyUploads,
      remoteOnlyPuts: remoteOnlyPuts,
      conflictUploads: conflictUploads,
      conflictLocalUpdates: conflictLocalUpdates,
    );
  }

  static CollectedBangumi _fromBangumiCollection(BangumiCollection remote) {
    final localType = remote.type.toCollectType();
    return CollectedBangumi(
      remote.toBangumiItem(),
      remote.updatedAt,
      localType.value,
    );
  }

  CollectSyncMerger._();
}
