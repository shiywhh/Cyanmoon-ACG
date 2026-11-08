import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/catalog_snapshot.dart';
import 'package:kazumi/features/cycani/catalog_library_widgets.dart';
import 'package:kazumi/features/cycani/catalog_plugins.dart';
import 'package:kazumi/features/cycani/catalog_danmaku_codec.dart';
import 'package:kazumi/features/cycani/catalog_aggregator.dart';
import 'package:kazumi/features/cycani/catalog_detail_page.dart';
import 'package:kazumi/features/cycani/catalog_models.dart';

void main() {
  test(
    'snapshot restore cannot overwrite a newer view or network response',
    () async {
      final read = Completer<List<CatalogJson>?>();
      var current = true;
      var writes = 0;
      final task = restoreCatalogSnapshot(
        'first',
        read: (_) => read.future,
        canApply: () => current,
        apply: (_) => writes++,
      );
      current = false;
      read.complete([
        {'id': 1},
      ]);
      await task;
      expect(writes, 0);
      await restoreCatalogSnapshot(
        'second',
        read: (_) async => [
          {'id': 2},
        ],
        canApply: () => true,
        apply: (_) => writes++,
      );
      expect(writes, 1);
    },
  );
  test('snapshot whitelist drops account secrets and internal fields', () {
    expect(
      catalogPickFields(
        {
          'id': 1,
          'content': 'text',
          'token': 'secret',
          'author_email': 'private',
        },
        ['id', 'content'],
      ),
      {'id': 1, 'content': 'text'},
    );
  });
  test('Giri resume is one road and valid episode only', () {
    final value = {'road': 1, 'episode_index': 3, 'position_ms': 12500};
    expect(giriResumeMatch(12, 1, value), (3, 12));
    expect(giriResumeMatch(12, 0, value), isNull);
    expect(giriResumeMatch(3, 1, value), isNull);
    expect(
      giriResumeMatch(12, 1, {
        'road': 1,
        'episode_index': -1,
        'position_ms': 1200,
      }),
      isNull,
    );
  });
  test('libraries normalize independent identities and image origins', () {
    final giri = catalogLibraryItem(
      {'vod_id': 6, 'vod_name': 'G', 'vod_pic': 'upload/vod/a.webp'},
      giri: true,
      history: false,
    );
    expect(
      CatalogVideo(giri).cover,
      'https://jpg.girigirilove.com/upload/vod/a.webp',
    );
    final xifan = catalogLibraryItem(
      {
        'anime_id': 6,
        'animes': {'title': 'X', 'cover_url': 'https://img2.xfmanga.top/a.jpg'},
        'episode_id': 8,
        'position_ms': 1000,
      },
      giri: false,
      history: true,
    );
    expect(CatalogVideo(xifan).title, 'X');
    expect(xifan['resume_episode_id'], 8);
    expect(giri['catalog_source'], isNot(xifan['catalog_source']));
  });
  test('three plugin descriptors use the same native playback contract', () {
    for (final source in CatalogSource.values) {
      final plugin = catalogPlugin(source);
      expect(plugin.name, source.label);
      expect(plugin.useWebview, isTrue);
      expect(plugin.useNativePlayer, isTrue);
    }
  });
  test(
    'mode/color conversion shares encoding without confusing Giri numeric modes',
    () {
      expect(CatalogDanmakuCodec.namedMode('top'), 5);
      expect(CatalogDanmakuCodec.giriMode(2), 5);
      expect(CatalogDanmakuCodec.xmlMode(2), 1);
      expect(CatalogDanmakuCodec.color('#123456').toARGB32(), 0xff123456);
      expect(CatalogDanmakuCodec.color('invalid').toARGB32(), 0xffffffff);
    },
  );
}
