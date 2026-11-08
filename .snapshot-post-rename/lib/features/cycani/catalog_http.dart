import 'catalog_connection.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Each adapter owns its client; credentials are never shared across sites.
abstract final class CatalogHttp {
  static IOHttpClientAdapter directAdapter() => IOHttpClientAdapter(
    createHttpClient: () => HttpClient()
      ..connectionFactory = CatalogConnection().call
      ..findProxy = (_) => 'DIRECT',
  );

  static Dio client(
    String origin,
    Map<String, String> headers, {
    Duration receiveTimeout = const Duration(seconds: 15),
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: origin,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0',
          ...headers,
        },
        followRedirects: false,
        connectTimeout: const Duration(seconds: 4),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: receiveTimeout,
      ),
    );
    dio.httpClientAdapter = directAdapter();
    final owner = Uri.tryParse(origin);
    if (owner != null && owner.hasAuthority) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            if (request.uri.origin != owner.origin) {
              handler.reject(
                DioException(
                  requestOptions: request,
                  error: 'Cross-origin request rejected',
                ),
              );
              return;
            }
            handler.next(request);
          },
        ),
      );
    }
    return dio;
  }
}
