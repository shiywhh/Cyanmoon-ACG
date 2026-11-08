import 'package:cyanmoon_acg/features/cycani/catalog_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyanmoon_acg/features/cycani/cycani_detail_page.dart';

import 'package:cyanmoon_acg/features/cycani/catalog_models.dart';

void main() {
  for (final width in [360.0, 1600.0]) {
    testWidgets('shared synopsis ordering and content width at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const bodyKey = ValueKey('details-body');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CatalogDetailScroll(
              children: [
                SizedBox(key: bodyKey, height: 20),
                CatalogSynopsis(
                  video: CatalogVideo({
                    'description': '简介正文',
                    'actor': ['甲', '', '乙'],
                    'state': 'TV',
                  }),
                  selector: Text('选择来源'),
                ),
                Text('选集'),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(bodyKey)).width,
        width == 360 ? 312 : 1300,
      );
      final labels = ['选择来源', '简介', '简介正文', '演员：甲 / 乙', '选集'];
      for (var i = 1; i < labels.length; i++) {
        expect(
          tester.getTopLeft(find.text(labels[i])).dy,
          greaterThan(tester.getTopLeft(find.text(labels[i - 1])).dy),
        );
      }
      expect(find.text('状态：TV'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing cover shows a bounded poster fallback', (tester) async {
    const key = ValueKey('poster');
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: CatalogPoster(key: key, urls: ['', '/missing']),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(key)), const Size(180, 270));
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
  });

  testWidgets('shared episode picker routes both line and episode taps', (
    tester,
  ) async {
    int? road, episode;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogEpisodePicker(
            roads: const ['线路一', '线路二'],
            selected: 0,
            labels: const ['第1集', '第2集'],
            onRoad: (i) => road = i,
            onEpisode: (i) => episode = i,
          ),
        ),
      ),
    );
    await tester.tap(find.text('线路二'));
    await tester.tap(find.widgetWithText(OutlinedButton, '第2集'));
    expect(road, 1);
    expect(episode, 1);
  });
  test('Xifan resume requires both anime and episode identity', () {
    const urls = [
      'https://next.xifanacg.com/anime/99/play/42',
      'https://next.xifanacg.com/anime/10/play/42',
    ];
    expect(
      xifanResumeMatch(urls, 10, {'episode_id': 42, 'position_ms': 90000}),
      (1, 90),
    );
    expect(
      xifanResumeMatch(urls, 10, {'episode_id': 44, 'position_ms': 90000}),
      isNull,
    );
  });
}
