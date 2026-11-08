import 'package:flutter_test/flutter_test.dart';
import 'package:cyanmoon_acg/modules/bangumi/bangumi_collection.dart';
import 'package:cyanmoon_acg/modules/bangumi/bangumi_collection_type.dart';
import 'package:cyanmoon_acg/modules/bangumi/bangumi_item.dart';
import 'package:cyanmoon_acg/modules/bangumi/sync_priority.dart';
import 'package:cyanmoon_acg/modules/bangumi/bangumi_tag.dart';
import 'package:cyanmoon_acg/modules/collect/collect_module.dart';
import 'package:cyanmoon_acg/modules/collect/collect_sync_merger.dart';
import 'package:cyanmoon_acg/modules/collect/collect_type.dart';

void main() {
  group('CollectSyncMerger', () {

    test('plans Bangumi changes after local and remote already diverged', () {
      // 原「WebDAV 合并后的本地状态」直接以字面量构造：
      // 本地 {1 在看@10} 与远端 {2 已看@5, 4 搁置@5} 按增量日志合并的结果。
      final collectibles = [
        _collect(2, CollectType.watched, 5),
        _collect(4, CollectType.onHold, 5),
        _collect(1, CollectType.watching, 10),
      ];

      final bangumiPlan = CollectSyncMerger.planBangumi(
        localCollectibles: collectibles,
        remoteCollections: [
          _remote(1, BangumiCollectionType.watched, 40),
          _remote(2, BangumiCollectionType.watched, 20),
          _remote(3, BangumiCollectionType.onHold, 30),
        ],
        priority: BangumiSyncPriority.bangumiFirst,
      );

      expect(bangumiPlan.totalOperations, 3);
      expect(
        bangumiPlan.localOnlyUploads.map((upload) => upload.bangumiId),
        [4],
      );
      expect(
          bangumiPlan.localOnlyUploads.single.type, CollectType.onHold.value);
      expect(
        bangumiPlan.remoteOnlyPuts.map(
          (mutation) => mutation.collectible.bangumiItem.id,
        ),
        [3],
      );
      expect(
        bangumiPlan.conflictLocalUpdates.map(
          (mutation) => mutation.collectible.bangumiItem.id,
        ),
        [1],
      );
      expect(
        bangumiPlan.conflictLocalUpdates.single.collectible.type,
        CollectType.watched.value,
      );
      expect(bangumiPlan.conflictUploads, isEmpty);
    });

    test('uses local priority and skips unsupported Bangumi collection types',
        () {
      final plan = CollectSyncMerger.planBangumi(
        localCollectibles: [
          _collect(1, CollectType.watching, 10),
        ],
        remoteCollections: [
          _remote(1, BangumiCollectionType.watched, 40),
          _remote(2, BangumiCollectionType.unknown, 50),
        ],
        priority: BangumiSyncPriority.localFirst,
      );

      expect(plan.totalOperations, 1);
      expect(plan.conflictUploads.single.bangumiId, 1);
      expect(plan.conflictUploads.single.type, CollectType.watching.value);
      expect(plan.remoteOnlyPuts, isEmpty);
      expect(plan.conflictLocalUpdates, isEmpty);
    });

    test('resolves conflicts with timeFirst (local newer, remote newer, same moment)', () {
      final plan = CollectSyncMerger.planBangumi(
        localCollectibles: [
          // id 1: local newer (timestamp 50 vs remote 10)
          _collect(1, CollectType.watching, 50),
          // id 2: remote newer (timestamp 10 vs remote 50)
          _collect(2, CollectType.planToWatch, 10),
          // id 3: same moment (timestamp 30 vs remote 30) -> default to local (conflictUploads)
          _collect(3, CollectType.onHold, 30),
          // id 4: local only
          _collect(4, CollectType.watched, 20),
        ],
        remoteCollections: [
          _remote(1, BangumiCollectionType.watched, 10),
          _remote(2, BangumiCollectionType.watched, 50),
          _remote(3, BangumiCollectionType.abandoned, 30),
          // id 5: remote only
          _remote(5, BangumiCollectionType.planToWatch, 40),
        ],
        priority: BangumiSyncPriority.timeFirst,
      );

      expect(plan.totalOperations, 5);
      // local only upload
      expect(plan.localOnlyUploads.map((u) => u.bangumiId), [4]);
      expect(plan.localOnlyUploads.single.type, CollectType.watched.value);
      // remote only put
      expect(plan.remoteOnlyPuts.map((p) => p.collectible.bangumiItem.id), [5]);
      expect(plan.remoteOnlyPuts.single.collectible.type, CollectType.planToWatch.value);
      // conflict uploads: id 1 (local newer), id 3 (same moment)
      expect(plan.conflictUploads.map((u) => u.bangumiId), [1, 3]);
      expect(plan.conflictUploads.firstWhere((u) => u.bangumiId == 1).type, CollectType.watching.value);
      expect(plan.conflictUploads.firstWhere((u) => u.bangumiId == 3).type, CollectType.onHold.value);
      // conflict local updates: id 2 (remote newer)
      expect(plan.conflictLocalUpdates.map((u) => u.collectible.bangumiItem.id), [2]);
      expect(plan.conflictLocalUpdates.single.collectible.type, CollectType.watched.value);
    });
  });

  group('BangumiSyncPriority', () {
    test('fromValue maps correctly including timeFirst and fallback', () {
      expect(BangumiSyncPriority.fromValue(0), BangumiSyncPriority.localFirst);
      expect(BangumiSyncPriority.fromValue(1), BangumiSyncPriority.bangumiFirst);
      expect(BangumiSyncPriority.fromValue(2), BangumiSyncPriority.timeFirst);
      expect(BangumiSyncPriority.fromValue(999), BangumiSyncPriority.localFirst);
      expect(BangumiSyncPriority.timeFirst.value, 2);
      expect(BangumiSyncPriority.timeFirst.label, '最新优先');
    });
  });

  group('BangumiCollection.fromJson', () {
    test('parses normal JSON correctly', () {
      final collection = BangumiCollection.fromJson({
        'updated_at': '2026-08-30T14:00:00Z',
        'type': 2,
        'subject': {
          'id': 12345,
          'date': '2026-04-01',
          'name': 'Original Name',
          'name_cn': '中文名',
          'short_summary': '这是一部动画',
          'score': 8.5,
          'eps': 24,
          'rank': 42,
          'images': {
            'large': 'https://example.com/large.jpg',
          },
          'tags': [
            {'name': '科幻', 'count': 100},
          ],
        },
      });

      expect(collection.bangumiId, 12345);
      expect(collection.name, 'Original Name');
      expect(collection.nameCn, '中文名');
      expect(collection.shortSummary, '这是一部动画');
      expect(collection.score, 8.5);
      expect(collection.eps, 24);
      expect(collection.rank, 42);
      expect(collection.type, BangumiCollectionType.watched);
      expect(collection.updatedAt, DateTime.parse('2026-08-30T14:00:00Z'));
      expect(collection.images['large'], 'https://example.com/large.jpg');
      expect(collection.tags.length, 1);
    });

    test('handles missing or malformed fields defensively while requiring valid updated_at', () {
      final collection = BangumiCollection.fromJson({
        'updated_at': '2026-08-30T14:00:00Z',
        'type': 1,
        'subject': {
          'id': 999,
          'score': 7, // integer instead of double
          // missing short_summary, eps, rank, images, tags
        },
      });

      expect(collection.bangumiId, 999);
      expect(collection.score, 7.0);
      expect(collection.shortSummary, '');
      expect(collection.eps, 0);
      expect(collection.rank, 0);
      expect(collection.updatedAt, DateTime.parse('2026-08-30T14:00:00Z'));
      expect(collection.images['large'], '');
      expect(collection.tags, isEmpty);
    });

    test('throws FormatException on missing, empty, or invalid updated_at', () {
      expect(
        () => BangumiCollection.fromJson({
          'type': 1,
          'subject': {'id': 999},
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => BangumiCollection.fromJson({
          'updated_at': '',
          'type': 1,
          'subject': {'id': 999},
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => BangumiCollection.fromJson({
          'updated_at': 'invalid-date-string',
          'type': 1,
          'subject': {'id': 999},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('falls back to subject_id when subject.id is missing', () {
      final collection = BangumiCollection.fromJson({
        'updated_at': '2026-08-30T14:00:00Z',
        'subject_id': 888,
        'type': 1,
        'subject': {
          'name': 'Fallback Name',
        },
      });
      expect(collection.bangumiId, 888);
      expect(collection.name, 'Fallback Name');
    });

    test('throws FormatException when subject id is missing or invalid', () {
      expect(
        () => BangumiCollection.fromJson({
          'type': 1,
          'subject': {
            'name': 'No ID',
          },
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => BangumiCollection.fromJson({
          'subject_id': 0,
          'type': 1,
          'subject': {
            'id': 0,
            'name': 'Zero ID',
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

CollectedBangumi _collect(int id, CollectType type, int timestamp) {
  return CollectedBangumi(
    _item(id),
    DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
    type.value,
  );
}

BangumiCollection _remote(
  int id,
  BangumiCollectionType type,
  int timestamp,
) {
  return BangumiCollection(
    id,
    '2026-01-01',
    DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
    type,
    'subject $id',
    '条目 $id',
    '',
    0,
    12,
    0,
    const {
      'large': '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    },
    const [],
  );
}

BangumiItem _item(int id) {
  return BangumiItem(
    id: id,
    type: 2,
    name: 'subject $id',
    nameCn: '条目 $id',
    summary: '',
    airDate: '2026-01-01',
    airWeekday: 4,
    rank: 0,
    images: const {
      'large': '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    },
    tags: const <BangumiTag>[],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

