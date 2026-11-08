import 'dart:io';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/cycani_api.dart';
import 'package:kazumi/features/cycani/catalog_danmaku_loader.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/utils/dandan_credentials.dart';

DanmakuEntry entry() => DanmakuEntry(
  message: 'original',
  time: 1,
  type: 1,
  color: const Color(0xFFFFFFFF),
  source: '[BiliBili]',
);
final originalResult = DanmakuLoadResult.success(
  danmakus: [entry()],
  bangumiID: 123,
);
const siteItems = [
  {'content': '站内', 'time_point': 5.61, 'mode': 'top', 'color': 16711680},
];
void main() {
  test(
    'offline cached comments work without any application credentials',
    () async {
      var networkCalls = 0;
      final result = await CatalogDanmakuLoader.load(
        loadCached: () async => [entry()],
        originalAvailable: false,
        mergeSiteDanmaku: false,
        loadOriginal: () async {
          networkCalls++;
          return originalResult;
        },
        loadSite: () async {
          networkCalls++;
          throw StateError('offline');
        },
      );
      expect(networkCalls, 0);
      expect(result.hasDanmakus, true);
    },
  );
  test('cache read failure still attempts the current site section', () async {
    final result = await CatalogDanmakuLoader.load(
      loadCached: () async => throw StateError('bad cache'),
      originalAvailable: false,
      mergeSiteDanmaku: false,
      loadOriginal: () async => originalResult,
      loadSite: () async => siteItems,
    );
    expect(result.hasDanmakus, true);
    expect(result.danmakus.single.message, '站内');
  });

  test(
    'missing credentials fail before an unsigned external request',
    // CI 会经 --dart-define 注入凭据：显式 skip 而不是在用例体里空转返回，
    // 否则测试报告永远显示绿色 pass 但实际没有执行任何断言。
    skip: hasDandanCredentials ? 'CI 已注入凭据，此用例仅适用于无凭据环境' : false,
    () async {
      expect(
        () => DanmakuClient.instance.get(
          'https://api.dandanplay.net/api/v2/search/episodes',
        ),
        throwsA(isA<DandanConfigurationException>()),
      );
    },
  );
  test(
    'unconfigured original source skips it and loads site even when merge is off',
    () async {
      var originalCalls = 0;
      final result = await CatalogDanmakuLoader.load(
        originalAvailable: false,
        mergeSiteDanmaku: false,
        loadOriginal: () async {
          originalCalls++;
          return originalResult;
        },
        loadSite: () async => siteItems,
      );
      expect(originalCalls, 0);
      expect(result.hasDanmakus, true);
      expect(result.danmakus.single.message, '站内');
    },
  );
  test('working original stays unchanged without merging', () async {
    var siteCalls = 0;
    final result = await CatalogDanmakuLoader.load(
      originalAvailable: true,
      mergeSiteDanmaku: false,
      loadOriginal: () async => originalResult,
      loadSite: () async {
        siteCalls++;
        return siteItems;
      },
    );
    expect(identical(result, originalResult), true);
    expect(siteCalls, 0);
  });
  test('merge retains original and site source identities', () async {
    final result = await CatalogDanmakuLoader.load(
      originalAvailable: true,
      mergeSiteDanmaku: true,
      loadOriginal: () async => originalResult,
      loadSite: () async => siteItems,
    );
    expect(result.bangumiID, 123);
    expect(result.danmakus.map((e) => e.source), [
      '[BiliBili]',
      CatalogDanmakuLoader.source,
    ]);
  });
  for (final throwsError in [false, true]) {
    test(
      'failed external source falls back to site (throws=$throwsError)',
      () async {
        final result = await CatalogDanmakuLoader.load(
          originalAvailable: true,
          mergeSiteDanmaku: false,
          loadOriginal: () async => throwsError
              ? throw StateError('403')
              : DanmakuLoadResult.failed(bangumiID: 9),
          loadSite: () async => siteItems,
        );
        expect(result.hasDanmakus, true);
        expect(result.danmakus.single.message, '站内');
      },
    );
  }
  test('empty original source still tries site without merge', () async {
    final result = await CatalogDanmakuLoader.load(
      originalAvailable: true,
      mergeSiteDanmaku: false,
      loadOriginal: () async =>
          DanmakuLoadResult.success(danmakus: [], bangumiID: 9),
      loadSite: () async => siteItems,
    );
    expect(result.hasDanmakus, true);
  });
  test('failed optional site must not discard working original', () async {
    final result = await CatalogDanmakuLoader.load(
      originalAvailable: true,
      mergeSiteDanmaku: true,
      loadOriginal: () async => originalResult,
      loadSite: () async => throw StateError('offline'),
    );
    expect(identical(result, originalResult), true);
  });
  test('successful empty site is empty, not a provider failure', () async {
    final result = await CatalogDanmakuLoader.load(
      originalAvailable: false,
      mergeSiteDanmaku: false,
      loadOriginal: () async => originalResult,
      loadSite: () async => [],
    );
    expect(result.status, DanmakuLoadStatus.empty);
    expect(result.hasDanmakus, false);
  });
  test('both unavailable sources report failure', () async {
    final result = await CatalogDanmakuLoader.load(
      originalAvailable: false,
      mergeSiteDanmaku: false,
      loadOriginal: () async => originalResult,
      loadSite: () async => throw StateError('offline'),
    );
    expect(result.isFailed, true);
  });
  test(
    'site parser retains seconds, RGB, Unicode and normal/top/bottom modes',
    () {
      final result = CatalogDanmakuLoader.parse([
        ...siteItems,
        {'content': '底部', 'time_point': '10.25', 'mode': 'bottom'},
        {'content': '普通', 'time_point': 0, 'mode': 'normal'},
        {'content': '负数', 'time_point': -1},
        {'content': 'NaN', 'time_point': 'NaN'},
        {'content': 'Infinity', 'time_point': 'Infinity'},
        {'content': '缺少时间'},
        {'content': ' ', 'time_point': 1},
        {'content': 123, 'time_point': 1},
      ]);
      expect(result.length, 3);
      expect(result[0].time, 5.61);
      expect(result[0].color, const Color(0xFFFF0000));
      expect(result.map((e) => e.type), [5, 4, 1]);
      expect(result[1].color, const Color(0xFFFFFFFF));
    },
  );
  test('live section loads through the same player fallback', () async {
    final api = CycaniApi();
    final result = await CatalogDanmakuLoader.load(
      originalAvailable: hasDandanCredentials,
      mergeSiteDanmaku: false,
      loadOriginal: () async => DanmakuLoadResult.failed(bangumiID: 0),
      loadSite: () => api.danmaku(52391),
    );
    expect(result.hasDanmakus, true);
    expect(result.danmakus.length, greaterThan(100));
    expect(result.danmakus.every((e) => e.time.isFinite && e.time >= 0), true);
    print(
      'Live native fallback: ${result.danmakus.length} comments; first timestamp ${result.danmakus.first.time}s',
    );
  }, skip: Platform.environment['CYCANI_DANMAKU_LIVE'] != '1');
}
