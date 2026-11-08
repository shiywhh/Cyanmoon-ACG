import 'package:kazumi/features/cycani/catalog_feed_widgets.dart';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:kazumi/features/cycani/cycani_api.dart';
import 'package:kazumi/features/cycani/cycani_profile_settings.dart';
import 'cycani_api_test.dart' show FakeAdapter, MemoryVault, ok;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/site_accounts.dart';

void main() {
  testWidgets('homepage category links forward actual site type IDs', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: CatalogCategoryLinks(
              categories: const [
                {'id': '3', 'name': '美番'},
                {'id': '24', 'name': 'BD副音轨'},
                {'id': '26', 'name': '演唱会及其他'},
              ],
              onSelected: (id) => selected = id,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('BD副音轨'));
    expect(selected, '24');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'source account does not flash previous session profile on reopen',
    (tester) async {
      const tokenKey = 'cycani.xifan.session.v1';
      String session(String token) =>
          jsonEncode({'access_token': token, 'expires_at': 4102444800});
      FlutterSecureStorage.setMockInitialValues({tokenKey: session('old')});
      final next = Completer<ResponseBody>();
      var old = true;
      final api = SourceAccounts(
        xifan: Dio()
          ..httpClientAdapter = FakeAdapter((r) async {
            if (old)
              return ResponseBody.fromString(
                jsonEncode({
                  'id': 'old-owner',
                  'user_metadata': {'nickname': 'Old profile'},
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            return next.future;
          }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SourceAccountsPage(initialGiri: false, accountApi: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old profile'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await api.logout(false);
      old = false;
      await const FlutterSecureStorage().write(
        key: tokenKey,
        value: session('new'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SourceAccountsPage(initialGiri: false, accountApi: api),
        ),
      );
      await tester.pump();
      expect(find.text('Old profile'), findsNothing);
      next.complete(
        ResponseBody.fromString(
          jsonEncode({
            'id': 'new-owner',
            'user_metadata': {'nickname': 'New profile'},
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('New profile'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('all three accounts have equal entry points', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SourceAccountsPage()));
    for (final name in ['次元城', '稀饭', 'GiriGiri']) {
      expect(
        find.ancestor(of: find.text(name), matching: find.byType(Card)),
        findsOneWidget,
      );
    }
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('both external account back buttons return to source list', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SourceAccountsPage()));
    for (final name in ['稀饭', 'GiriGiri']) {
      await tester.tap(find.text(name));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('来源账号'), findsOneWidget);
    }
  });
  testWidgets(
    'Cycani profile and security return to the selected source account',
    (tester) async {
      final api = CycaniApi(
        vault: MemoryVault()
          ..value = jsonEncode({
            'token': 'fixture',
            'user': {'id': 7, 'nickname': 'fixture'},
          }),
        dio: Dio()
          ..httpClientAdapter = FakeAdapter(
            (_) async => ok({'id': 7, 'nickname': 'fixture'}),
          ),
      );
      await api.restore();
      await tester.pumpWidget(
        MaterialApp(home: SourceAccountsPage(cycaniApi: api)),
      );
      await tester.tap(find.text('次元城'));
      await tester.pumpAndSettle();
      expect(find.byType(CycaniSourceAccount), findsOneWidget);
      for (final (label, type) in [
        ('个人资料', CycaniProfileSettingsPage),
        ('账户与安全', CycaniSecuritySettingsPage),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(type), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(CycaniSourceAccount), findsOneWidget);
      }
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('来源账号'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    },
  );
}
