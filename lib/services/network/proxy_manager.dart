import 'package:cached_network_image/cached_network_image.dart';
import 'package:cyanmoon_acg/request/core/dio_factory.dart';
import 'package:cyanmoon_acg/request/core/ech_transport.dart';
import 'package:cyanmoon_acg/services/logging/logger.dart';
import 'package:cyanmoon_acg/services/network/proxy_aware_image_cache_manager.dart';

// WebView proxies are configured separately by their platform controllers.
class ProxyManager {
  ProxyManager._();

  static void applyProxy() {
    _resetClients();
    CyanmoonLogger().i('Proxy: 网络客户端配置已刷新');
  }

  static void clearProxy() {
    _resetClients();
    CyanmoonLogger().i('Proxy: 网络客户端代理已清除');
  }

  static void _resetClients() {
    DioFactory.reset();
    EchTransport.reset();
    CachedNetworkImageProvider.defaultCacheManager =
        ProxyAwareImageCacheManager.instance;
  }
}
