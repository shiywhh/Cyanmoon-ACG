import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/catalog_account_widgets.dart';
import 'package:kazumi/features/cycani/cycani_feed_widgets.dart';
import 'package:kazumi/features/cycani/cycani_source_accounts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('cooldown catches up after suspension and disposes its timer', (
    tester,
  ) async {
    var now = DateTime.utc(2026);
    final cooldown = VerificationCooldown(now: () => now);
    cooldown.start();
    expect(cooldown.remaining, 60);
    now = now.add(const Duration(seconds: 49));
    expect(cooldown.remaining, 11);
    now = now.add(const Duration(seconds: 70));
    await tester.pump(const Duration(seconds: 1));
    expect(cooldown.remaining, 0);
    cooldown.dispose();
  });
  testWidgets('account fields validate and obscure passwords consistently', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: form,
            child: CatalogAccountField(
              controller: controller,
              label: '密码',
              secret: true,
              required: true,
            ),
          ),
        ),
      ),
    );
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('请填写密码'), findsOneWidget);
    controller.text = 'fixture';
    expect(form.currentState!.validate(), isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('shared pagination only triggers near the visible viewport', (
    tester,
  ) async {
    var calls = 0, more = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 1800),
                  CatalogLoadMore(
                    loading: false,
                    hasMore: more,
                    loadMore: () async {
                      calls++;
                      setState(() => more = false);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(calls, 0);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1800),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
  test(
    'startup restores each source statistics synchronously without crossing owners',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        for (final name in ['giri', 'xifan']) ...{
          'cycani.$name.session.v1': '{}',
          'catalog.account.$name.profile.v1': jsonEncode({'id': name}),
          'catalog.account.$name.watch-stats.v1': jsonEncode({
            'owner': name,
            'watched': 3,
            'favorites': 2,
          }),
        },
      });
      final accounts = SourceAccounts();
      await accounts.restoreSnapshots();
      for (final giri in [false, true]) {
        final owner = giri ? 'giri' : 'xifan';
        expect(accounts.profileSnapshot(giri)?['id'], owner);
        expect(accounts.watchStatsSnapshot(giri, owner)?['watched'], 3);
        expect(accounts.watchStatsSnapshot(giri, 'other'), isNull);
      }
      await accounts.logout(true);
      expect(accounts.watchStatsSnapshot(true, 'giri'), isNull);
      expect(accounts.watchStatsSnapshot(false, 'xifan')?['favorites'], 2);
    },
  );
}
