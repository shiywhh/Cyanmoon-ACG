
import 'package:dio/dio.dart';
import 'package:cyanmoon_acg/request/core/dio_factory.dart';
import 'package:cyanmoon_acg/request/core/network_error_mapper.dart';
import 'package:cyanmoon_acg/services/storage/storage.dart';
import 'package:cyanmoon_acg/utils/constants.dart';

class BangumiClient {
  BangumiClient._();

  static final BangumiClient instance = BangumiClient._();

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
    String? accessToken,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await DioFactory.bangumiDio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: _headers(
            requiresAuth: requiresAuth,
            accessToken: accessToken,
            url: url,
            method: 'GET',
          ),
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  Future<dynamic> post(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await DioFactory.bangumiDio.post(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          headers: _headers(
            requiresAuth: requiresAuth,
            url: url,
            method: 'POST',
            data: data,
          ),
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  Map<String, dynamic> _headers({
    required bool requiresAuth,
    String? accessToken,
    required String url,
    required String method,
    Object? data,
  }) {
    final headers = <String, dynamic>{...bangumiHTTPHeader};
    final bangumiSyncEnable = GStorage.getSetting(
      SettingsKeys.bangumiSyncEnable,
    );
    final token =
        (accessToken ??
                GStorage.getSetting<String>(SettingsKeys.bangumiAccessToken))
            .trim();
    if ((requiresAuth || bangumiSyncEnable) && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }


}
