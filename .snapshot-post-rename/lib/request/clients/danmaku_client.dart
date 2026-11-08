import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/utils/dandan_credentials.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/utils/crypto.dart';

class DanmakuClient {
  DanmakuClient._();

  static final DanmakuClient instance = DanmakuClient._();

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' ||
        !const [
          'api.dandanplay.net',
          'ext-danmaku.moedot.net',
        ].contains(uri.host)) {
      throw ArgumentError('无效的弹幕接口');
    }
    final official = uri.host == 'api.dandanplay.net';
    if (official && !hasDandanCredentials)
      throw const DandanConfigurationException();
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final requestHeaders = <String, dynamic>{
      'user-agent': getRandomUA(),
      'referer': '',
      ...headers,
      if (official) ...{
        'X-Auth': 1,
        'X-AppId': dandanCredentials['id'],
        'X-Timestamp': timestamp,
        'X-Signature': generateDandanSignature(uri.path, timestamp),
      },
    };
    if (!official) {
      requestHeaders.removeWhere(
        (key, _) => const [
          'authorization',
          'cookie',
          'x-auth',
          'x-appid',
          'x-appsecret',
          'x-signature',
          'x-timestamp',
        ].contains(key.toLowerCase()),
      );
    }

    try {
      final response = await DioFactory.apiDio.get(
        url,
        queryParameters: queryParameters,
        options: Options(headers: requestHeaders, followRedirects: false),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }
}
