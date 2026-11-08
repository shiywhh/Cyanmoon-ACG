import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/cycani_source_accounts.dart';

void main() {
  final user = Platform.environment['GIRI_READ_USER'];
  final password = Platform.environment['GIRI_READ_PASSWORD'];
  final directory = Platform.environment['GIRI_READ_WORK'];
  final realHttp = HttpOverrides.current;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = realHttp;
  test(
    'Giri real original-account sign-in then read-only library acceptance',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = SourceAccounts();
      final png = await api.captcha();
      await File('$directory/giri-read-captcha.png').writeAsBytes(png);
      print('Captcha ready');
      final answer = File('$directory/giri-read-answer.private.txt');
      final until = DateTime.now().add(const Duration(seconds: 90));
      while (!await answer.exists()) {
        if (DateTime.now().isAfter(until))
          throw StateError('Captcha answer timed out');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      final code = (await answer.readAsString()).trim();
      await answer.delete();
      await api.giriLogin(user!, password!, code);
      final profile = await api.profile(true);
      expect(profile?['user_id'], isNotNull);
      final history = await api.allLibraryRows(true, history: true);
      final follows = await api.allLibraryRows(true, history: false);
      print(
        'Verified Giri profile and library reads: history=${history.length}, follows=${follows.length}',
      );
      final session = await const FlutterSecureStorage().read(
        key: 'cycani.giri.session.v1',
      );
      if (session != null) {
        final out = File('$directory/../giri-verified-session.private.json');
        final temp = File('${out.path}.tmp');
        await temp.writeAsString(session);
        await temp.rename(out.path);
      }
    },
    skip: user == null || password == null || directory == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
