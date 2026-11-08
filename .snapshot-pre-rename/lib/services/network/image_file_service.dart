import 'dart:async';
import 'catalog_image_url.dart';
import 'dart:io' show HttpClientResponseCompressionState;

import 'package:ech_http/ech_http.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:kazumi/request/core/ech_transport.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/network/bangumi_image_url_rewriter.dart';
import 'package:kazumi/services/network/image_acceleration.dart';
import 'package:kazumi/services/network/image_file_response.dart';
import 'package:kazumi/utils/constants.dart' show bangumiHTTPHeader;

class ImageFileService extends FileService {
  ImageFileService({
    this.allowPublicProxy = true,
    this.clientFactory,
    this.modeOverride,
    this.directTimeout = const Duration(seconds: 8),
  });
  final Duration directTimeout;
  final http.Client Function()? clientFactory;
  final ImageAcceleration? modeOverride;
  http.Client _client() =>
      clientFactory?.call() ??
      IOClient(
        NetworkConfig.fromSettings()
            .copyWith(allowBadCertificates: false)
            .createHttpClient()
          ..connectionTimeout = const Duration(seconds: 4),
      );
  final bool allowPublicProxy;
  static int _active = 0;
  static final _waiting = <Completer<void>>[];
  static Future<void> _acquire() async {
    if (_active < 5) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future;
  }

  static void _unlock() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _active--;
    }
  }

  Future<FileServiceResponse> _publicProxy(Uri proxy) async {
    final client = _client();
    _clients.add(client);
    try {
      final response = await client
          .send(http.Request('GET', proxy))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '').toLowerCase().startsWith(
            'image/',
          )) {
        await response.stream.listen(null).cancel();
        throw const FormatException('Invalid image proxy response');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 8),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 12 * 1024 * 1024)
          throw const FormatException('Image too large');
      }
      if (bytes.length < 128)
        throw const FormatException('Image proxy placeholder');
      final jpeg = bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8;
      final png = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50;
      final gif =
          bytes.length > 6 && String.fromCharCodes(bytes.take(3)) == 'GIF';
      final webp =
          bytes.length > 12 &&
          String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
          String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP';
      if (gif &&
          ((bytes[6] | bytes[7] << 8) < 16 ||
              (bytes[8] | bytes[9] << 8) < 16)) {
        throw const FormatException('Image proxy tracking pixel');
      }
      if (!(jpeg || png || gif || webp))
        throw const FormatException('Invalid image bytes');
      return await createImageFileResponse(
        http.StreamedResponse(
          Stream.value(bytes),
          200,
          contentLength: bytes.length,
          headers: {...response.headers, 'cache-control': 'max-age=86400'},
        ),
        contentLength: bytes.length,
        onComplete: () {},
      );
    } finally {
      _release(client);
    }
  }

  final _clients = <http.Client>{};
  bool _closed = false;

  void close() {
    _closed = true;
    for (final client in _clients) {
      client.close();
    }
    _clients.clear();
  }

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    if (_closed) throw StateError('Image file service is closed');
    await _acquire();
    var handedOff = false;
    try {
      if (_closed) throw StateError('Image file service is closed');
      final mode = modeOverride ?? ImageAcceleration.current;
      if (allowPublicProxy && mode == ImageAcceleration.baidu) {
        final proxy = CatalogImageUrl.proxy(Uri.parse(url), headers: headers);
        if (proxy != null) {
          try {
            return await _publicProxy(proxy);
          } catch (_) {
            // Public acceleration is optional. Never forward origin headers.
          }
        }
      }
      var uri = Uri.parse(url);
      final ech =
          mode == ImageAcceleration.ech &&
          BangumiImageUrlRewriter.isBangumiImage(uri);
      if (ech) {
        uri = uri.replace(scheme: 'https');
      } else if (mode == ImageAcceleration.mirror) {
        uri = BangumiImageUrlRewriter.rewrite(uri);
      }

      final request = http.Request('GET', uri);
      final Future<http.StreamedResponse> Function(http.BaseRequest) send;
      final void Function() release;
      if (ech) {
        final lease = EchTransport.lease(uri);
        send = lease.send;
        release = lease.release;
        request.headers['user-agent'] = bangumiHTTPHeader['user-agent']!;
      } else {
        final client = _client();
        _clients.add(client);
        send = client.send;
        release = () => _release(client);
      }
      if (headers != null) request.headers.addAll(headers);

      final http.StreamedResponse response;
      try {
        response = await send(request).timeout(directTimeout);
      } catch (_) {
        release();
        rethrow;
      }
      handedOff = true;
      return await createImageFileResponse(
        response,
        idleTimeout: directTimeout,
        // ECH preserves wire lengths after decompression; decoded size is unknown.
        contentLength:
            response is EchResponse &&
                response.compressionState ==
                    HttpClientResponseCompressionState.decompressed
            ? null
            : response.contentLength,
        onComplete: () {
          release();
          _unlock();
        },
      );
    } finally {
      if (!handedOff) _unlock();
    }
  }

  void _release(http.Client client) {
    if (_clients.remove(client)) client.close();
  }
}
