import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyanmoon_acg/features/cycani/site_accounts.dart';

void main() {
  final realHttp = HttpOverrides.current;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = realHttp;

  test(
    'Giri original account CAPTCHA endpoint returns a PNG and session cookie',
    () async {
      final bytes = await SourceAccounts().captcha();
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    },
    skip: Platform.environment['GIRI_CAPTCHA_LIVE'] != '1',
  );

  final path = Platform.environment['GIRI_LIVE_SESSION'];
  test(
    'Giri authenticated profile, history and follows are readable',
    () async {
      final stored = await File(path!).readAsString();
      final json = jsonDecode(stored);
      expect(json is Map && json['cookies'] is Map, isTrue);
      FlutterSecureStorage.setMockInitialValues({
        'cycani.giri.session.v1': stored,
      });
      final api = SourceAccounts();
      expect(await api.hasSession(true), isTrue);
      final profile = await api.profile(true);
      expect(int.tryParse('${profile?['user_id']}'), greaterThan(0));
      for (final history in [true, false]) {
        final (rows, _) = await api.libraryPage(
          true,
          history: history,
          page: 1,
        );
        expect(
          rows.every((r) => int.tryParse('${r['vod_id']}') != null),
          isTrue,
        );
      }
      await api.logout(true);
      expect(await api.cachedProfile(true), isNull);
    },
    skip: path == null
        ? 'Set GIRI_LIVE_SESSION to a private session file.'
        : false,
  );
}
