import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/site_accounts.dart';

void main() {
  final email = Platform.environment['XIFAN_LIVE_EMAIL'];
  final password = Platform.environment['XIFAN_LIVE_PASSWORD'];
  final realHttp = HttpOverrides.current;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = realHttp;
  FlutterSecureStorage.setMockInitialValues({});

  test(
    'Xifan account reads authenticated profile, history and follows',
    () async {
      final api = SourceAccounts();
      await api.xifanLogin(email!, password!);
      final profile = await api.profile(false);
      expect(
        profile?['id'],
        isA<String>().having((id) => id.isNotEmpty, 'nonempty', true),
      );
      for (final history in [true, false]) {
        final (rows, _) = await api.libraryPage(
          false,
          history: history,
          page: 1,
        );
        expect(rows.every((row) => row['anime_id'] != null), isTrue);
      }
      await api.logout(false);
      expect(await api.cachedProfile(false), isNull);
    },
    skip: email == null || password == null
        ? 'Opt-in Xifan credentials via environment.'
        : false,
  );
}
