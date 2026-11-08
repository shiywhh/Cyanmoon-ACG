import 'package:dio/dio.dart';

Future<T> retryPublicCatalogRead<T>(Future<T> Function() read) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await read();
    } on DioException catch (error) {
      final retryable = switch (error.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout => true,
        _ => false,
      };
      if (!retryable || attempt >= 2) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
  }
}
