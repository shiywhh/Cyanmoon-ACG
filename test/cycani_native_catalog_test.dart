import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_aggregator.dart';
import 'package:cyanmoon_acg/features/cycani/site_native_catalog.dart';
import 'package:cyanmoon_acg/features/cycani/site_accounts.dart';

void main() {
  test(
    'native media parsing restricts HTTPS and matches real episode identities',
    () {
      expect(
        NativeCatalogApi.xifanEpisode(
          'https://next.xifanacg.com/anime/3432/play/203779',
        ),
        (3432, 203779),
      );
      expect(
        NativeCatalogApi.xifanEpisode(
          'https://next.xifanacg.com.evil.test/anime/3432/play/203779',
        ),
        isNull,
      );
      expect(
        NativeCatalogApi.giriMedia(
          'https://giri.girigirilove.top/01/index.m3u8',
        ),
        isNotNull,
      );
      expect(
        NativeCatalogApi.giriMedia(
          'https://girigirilove.top.evil.test/index.m3u8',
        ),
        isNull,
      );
    },
  );
  test('Giri groups retain language lines and skip unrelated media hosts', () {
    final roads = NativeCatalogApi.giriRoads({
      'vod_play_from': r'cht$$$chs',
      'vod_play_url':
          r'01$https://giri.girigirilove.top/1.m3u8#02$https://invalid.test/2.m3u8$$$01$https://giri.girigirilove.top/a.mp4',
    });
    expect(roads.map((r) => r.name), ['繁体', '简体']);
    expect(roads.first.identifier, ['01']);
  });
  test('live native metadata and Xifan issue endpoint', () async {
    final api = NativeCatalogApi();
    final d = await Future.wait([
      api.detail(CatalogSource.xifan, 3432),
      api.detail(CatalogSource.giri, 27203),
    ]);
    expect(d.every((d) => d.roads.isNotEmpty), true);
    expect(Uri.parse(await api.xifanPlayback(3432, 203779)).scheme, 'https');
    final png = await SourceAccounts().captcha();
    expect(png.take(4), [0x89, 0x50, 0x4e, 0x47]);
    print(
      'Live native metadata, playback issuance and Giri image captcha passed',
    );
  }, skip: Platform.environment['CYCANI_NATIVE_CATALOG_LIVE'] != '1');
}
