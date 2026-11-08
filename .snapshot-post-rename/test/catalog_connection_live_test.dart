import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/catalog_http.dart';

/// Live regression for the custom TCP connection factory: https through
/// CatalogHttp must complete a real TLS handshake (the SDK does not upgrade
/// factory-provided sockets itself — see HttpClient.connectionFactory in
/// dart-sdk lib/_http/http_impl.dart).
/// Run: CATALOG_TLS_LIVE=1 flutter test test/catalog_connection_live_test.dart
void main() {
  final enabled = Platform.environment['CATALOG_TLS_LIVE'] == '1';
  final skip = enabled ? false : 'Set CATALOG_TLS_LIVE=1 to run the live TLS check.';

  Dio appClient() {
    final dio = Dio();
    dio.httpClientAdapter = CatalogHttp.directAdapter();
    dio.options = BaseOptions(
      baseUrl: 'https://www.cycani.org/api',
      headers: {
        'Accept': 'application/json',
        'X-App-Name': 'cyc_web',
        'X-App-Version': 'cycweb',
        'X-Time-Zone': 'Asia/Shanghai',
        'Referer': 'https://www.cycani.org/',
      },
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: false,
      validateStatus: (code) => code != null && code < 600,
    );
    return dio;
  }

  test(
    'https through CatalogHttp performs TLS and reaches the real server',
    () async {
      final response = await appClient().get<dynamic>('/ranks');
      expect(response.statusCode, 200, reason: 'plaintext-to-443 would 400');
      final body = response.data;
      expect(body, isA<Map>());
      expect(body['code'], 0);
      expect(body['data']['list'], isA<List>());
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
