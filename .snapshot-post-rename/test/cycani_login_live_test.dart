import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/cycani_api.dart';
import 'package:kazumi/features/cycani/catalog_models.dart';
import 'package:kazumi/features/cycani/catalog_paging.dart';
import 'cycani_api_test.dart' show MemoryVault;

void main() {
  final user = Platform.environment['CYCANI_LOGIN_USER'];
  final password = Platform.environment['CYCANI_LOGIN_PASSWORD'];
  test(
    'real login normalizes server Bearer token and authenticates profile, libraries and playback',
    () async {
      final vault = MemoryVault();
      final api = CycaniApi(vault: vault);
      await api.login(user!, password!);
      expect(api.loggedIn, true);
      expect(vault.value?.contains('Bearer '), false);
      await api.profile();
      expect(api.user.isNotEmpty, true);
      final favorites = await api.favorites();
      final histories = await api.histories();
      expect(favorites['pager'], isA<Map>());
      expect(histories['cursor'], isA<Map>());
      for (final page in [
        CatalogPage.fromJson(favorites, page: 1),
        CatalogPage.fromJson(histories, page: 1, cursorBased: true),
      ]) {
        expect(page.items.every((row) => CatalogVideo(row).id > 0), isTrue);
      }
      final url = await api.playUrl(52391);
      expect(Uri.tryParse(url)?.scheme, 'https');
    },
    skip: user == null || password == null
        ? 'Opt-in real login credentials via environment.'
        : false,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
