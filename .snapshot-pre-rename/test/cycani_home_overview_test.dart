import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/cycani_api.dart';
import 'package:kazumi/features/cycani/cycani_models.dart';
import 'package:kazumi/features/cycani/cycani_home_overview.dart';
import 'cycani_api_test.dart' show MemoryVault;

class _OverviewApi extends CycaniApi {
  _OverviewApi() : super(vault: MemoryVault());
  final days = <int>[], rankIds = <int>[];
  bool fail = false;
  @override
  Future<List<CycaniJson>> schedule(int day) async {
    days.add(day);
    if (fail) throw StateError('offline');
    return [
      {'videos': <CycaniJson>[]},
    ];
  }

  @override
  Future<List<CycaniJson>> ranks() async => [
    {'id': 10, 'name': 'TV 番组'},
    {'id': 20, 'name': '剧场番组'},
  ];
  @override
  Future<List<CycaniJson>> rankVideos(int id) async {
    rankIds.add(id);
    if (fail) throw StateError('offline');
    return [];
  }
}

void main() {
  testWidgets('home overview remembers selected day and ranking after return', (
    tester,
  ) async {
    final api = _OverviewApi();
    final bucket = PageStorageBucket();
    Widget pane() => MaterialApp(
      home: Scaffold(
        body: PageStorage(
          bucket: bucket,
          child: CustomScrollView(
            slivers: [
              CycaniHomeOverview(api: api, onWeek: (_) {}, onRanking: (_) {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(pane());
    await tester.pumpAndSettle();
    final day = api.days.single == 1 ? 2 : 1;
    await tester.tap(find.text(day == 1 ? '周一' : '周二'));
    await tester.tap(find.text('剧场番组'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(pane());
    await tester.pumpAndSettle();
    expect(api.days.last, day);
    expect(api.rankIds.last, 20);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '剧场番组'))
          .selected,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });

  testWidgets(
    'homepage calendar/ranking select, cache and route actual filters',
    (tester) async {
      final api = _OverviewApi();
      int? selectedDay;
      String? selectedRank;
      Widget pane(int revision) => MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              CycaniHomeOverview(
                api: api,
                revision: revision,
                onWeek: (day) => selectedDay = day,
                onRanking: (rank) => selectedRank = rank,
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(pane(0));
      await tester.pumpAndSettle();
      expect(find.text('追番周表'), findsOneWidget);
      expect(find.text('排行榜'), findsOneWidget);
      expect(api.rankIds, [10]);
      final initial = api.days.single;
      final target = initial == 1 ? 2 : 1;
      final label = target == 1 ? '周一' : '周二';
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(api.days, [initial, target]);
      await tester.tap(find.text('剧场番组'));
      await tester.pumpAndSettle();
      expect(api.rankIds, [10, 20]);
      await tester.tap(find.text('TV番组'));
      await tester.pumpAndSettle();
      expect(api.rankIds, [10, 20]);
      await tester.tap(find.text('查看更多').first);
      await tester.tap(find.text('查看更多').last);
      expect(selectedDay, target);
      expect(selectedRank, 'TV番组');
      api.fail = true;
      await tester.pumpWidget(pane(1));
      await tester.pumpAndSettle();
      expect(api.days.last, target);
      expect(api.rankIds.last, 10);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('暂无番剧'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    },
  );
}
