import 'package:flutter_test/flutter_test.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_identity.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_models.dart';

void main() {
  group('SiteEntry legacy codec', () {
    test('round-trips every source (append-only enum keeps old codes)', () {
      for (final source in CatalogSource.values) {
        final entry = SiteEntry(source, 12345);
        final decoded = SiteEntry.fromLegacy(entry.legacyId);
        expect(decoded, entry, reason: 'source=${source.name}');
        expect(decoded?.key, '${source.name}:12345');
      }
    });

    test('bangumi encodes at index 3 without colliding', () {
      final bangumi = SiteEntry(CatalogSource.bangumi, 425590);
      expect(bangumi.legacyId, -(3 * 1000000000 + 425590));
      final decoded = SiteEntry.fromLegacy(bangumi.legacyId);
      expect(decoded?.source, CatalogSource.bangumi);
      expect(decoded?.rawId, 425590);
    });

    test('giri/xifan/cycani codes are distinct for the same raw id', () {
      final ids = {
        for (final source in CatalogSource.values)
          source: SiteEntry(source, 777).legacyId,
      };
      expect(ids.values.toSet().length, CatalogSource.values.length);
    });

    test('legacy decode rejects positive ids and zero raw ids', () {
      expect(SiteEntry.fromLegacy(12345), isNull);
      expect(SiteEntry.fromLegacy(-(1 * 1000000000)), isNull);
      expect(SiteEntry.fromLegacy(-999999999999), isNull);
    });

    test('detail uri points at the entry site', () {
      expect(
        SiteEntry(CatalogSource.bangumi, 425590).source.detail(425590).host,
        'bgm.tv',
      );
    });
  });

  group('CatalogVideo.toBangumi', () {
    test('cycani row keeps the legacy encoding', () {
      final video = CatalogVideo({
        'video_id': 321,
        'title': '测试',
        'cover_url': 'https://img.example.com/a.jpg',
        'catalog_source': 'cycani',
        'weekday': 5,
      });
      final item = video.toBangumi();
      expect(item.id, -321);
      expect(item.info, 'cycani:321');
    });

    test('giri/xifan rows are no longer hardcoded as cycani', () {
      final giri = CatalogVideo({
        'video_id': 321,
        'title': '测试',
        'catalog_source': 'giri',
      });
      final item = giri.toBangumi();
      expect(item.id, -(2 * 1000000000 + 321));
      expect(item.info, 'giri:321');

      final xifan = CatalogVideo({
        'video_id': 321,
        'title': '测试',
        'catalog_source': 'xifan',
      });
      expect(xifan.toBangumi().id, -(1 * 1000000000 + 321));
    });

    test('bangumi rows encode as the fourth source', () {
      final row = CatalogVideo({
        'video_id': 425590,
        'title': '孤独摇滚',
        'catalog_source': 'bangumi',
      });
      final item = row.toBangumi();
      expect(item.id, -(3 * 1000000000 + 425590));
      expect(item.info, 'bangumi:425590');
    });
  });
}
