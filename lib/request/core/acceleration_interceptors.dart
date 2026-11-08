import 'package:dio/dio.dart';
import 'package:cyanmoon_acg/request/config/api_endpoints.dart';
import 'package:cyanmoon_acg/request/core/ech_adapter.dart';
import 'package:cyanmoon_acg/services/network/bangumi_acceleration.dart';
import 'package:cyanmoon_acg/services/network/rules_mirror.dart';

class BangumiAccelerationInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final uri = options.uri;
    if (ApiEndpoints.bangumiPublicApiHosts.contains(uri.host)) {
      switch (BangumiAcceleration.current) {
        case BangumiAcceleration.direct:
          break;
        case BangumiAcceleration.ech:
          options.path = uri.replace(scheme: 'https').toString();
          options.queryParameters = {};
          options.requireEch();
      }
    }
    handler.next(options);
  }
}

class RulesMirrorInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final url = options.uri.toString();
    if (url.startsWith(ApiEndpoints.pluginShop)) {
      switch (RulesMirror.current) {
        case RulesMirror.direct:
          break;
        case RulesMirror.ghProxy:
          options.path = ApiEndpoints.ghProxyMirror + url;
          options.requireEch();
        case RulesMirror.ghfast:
          options.path = ApiEndpoints.ghfastMirror + url;
        case RulesMirror.gitcode:
          options.path =
              ApiEndpoints.gitcodeMirror +
              url.substring(ApiEndpoints.pluginShop.length);
      }
    }
    handler.next(options);
  }
}
