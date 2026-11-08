import 'catalog_http.dart';
import 'cycani_read_retry.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'catalog_danmaku_codec.dart';
import 'dart:async';
import 'package:xml/xml.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'cycani_models.dart';
import 'cycani_danmaku_options.dart';

class GiriDanmakuApi {
  GiriDanmakuApi({Dio? api, Dio? xml})
    : _api = api ?? _client(),
      _xml = xml ?? _client() {
    for (final client in [_api, _xml]) {
      client.options.followRedirects = false;
      client.options.headers.removeWhere(
        (name, _) => const {
          'authorization',
          'cookie',
          'apikey',
          'x-appid',
          'x-appsecret',
        }.contains(name.toLowerCase()),
      );
    }
  }

  static final instance = GiriDanmakuApi();
  static const origin = 'https://m3u8.girigirilove.com';
  final Dio _api, _xml;

  static Dio _client() => CatalogHttp.client('', {});

  Future<Object?> _read(String operation, String playUrl) async {
    final uri = Uri.tryParse(playUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        !const ['http', 'https'].contains(uri.scheme)) {
      throw const FormatException('无效播放地址');
    }
    final response = await retryPublicCatalogRead(
      () => _api.post<dynamic>(
        '$origin/api.php/Scrolling/$operation',
        data: FormData.fromMap({'play_url': playUrl}),
      ),
    );
    final data = cycaniMap(response.data);
    if (cycaniInt(data['code']) != 1) throw StateError('GiriGiri 弹幕加载失败');
    return data['info'];
  }

  static List<DanmakuEntry> parseInternal(Object? rows) {
    final entries = <DanmakuEntry>[];
    for (final row in cycaniList(rows)) {
      try {
        final raw = row['scroll_json'];
        final data = cycaniMap(raw is String ? jsonDecode(raw) : raw);
        final time = double.tryParse('${data['time']}');
        final content =
            (data['content'] ?? data['text'])?.toString().trim() ?? '';
        if (time == null || !time.isFinite || time < 0 || content.isEmpty)
          continue;
        final color = CatalogDanmakuCodec.color(
          cycaniMap(data['style'])['color'] ?? data['color'],
        );
        entries.add(
          DanmakuEntry(
            message: content,
            time: time,
            type: CatalogDanmakuCodec.giriMode(data['mode']),
            color: color,
            source: CycaniDanmakuOptions.giriSource,
          ),
        );
      } catch (_) {
        // A malformed row must not discard other valid site comments.
      }
    }
    return entries..sort((a, b) => a.time.compareTo(b.time));
  }

  static List<DanmakuEntry> parseXml(String data) {
    final doc = XmlDocument.parse(data);
    final entries = <DanmakuEntry>[];
    for (final node in doc.findAllElements('d')) {
      final fields = (node.getAttribute('p') ?? '').split(',');
      if (fields.length < 4) continue;
      final time = double.tryParse(fields[0]);
      final content = node.innerText.trim();
      if (time == null || !time.isFinite || time < 0 || content.isEmpty)
        continue;
      entries.add(
        DanmakuEntry(
          message: content,
          time: time,
          type: CatalogDanmakuCodec.xmlMode(fields[1]),
          color: CatalogDanmakuCodec.color(fields[3]),
          source: CycaniDanmakuOptions.giriExternalSource,
        ),
      );
    }
    return entries..sort((a, b) => a.time.compareTo(b.time));
  }

  static Uri? fallbackXml(String playUrl) {
    final uri = Uri.tryParse(playUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.host.endsWith('.girigirilove.com') ||
        !uri.path.startsWith('/zijian/') ||
        !uri.path.endsWith('/playlist.m3u8'))
      return null;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.replaceFirst(RegExp(r'/playlist\.m3u8$'), '.xml'),
    );
  }

  Future<List<DanmakuEntry>> internal(String playUrl) async =>
      parseInternal(await _read('getScrolling', playUrl));

  Future<List<DanmakuEntry>> external(String playUrl) async {
    Uri? target;
    try {
      final data = await _read('getVodOutScrolling', playUrl);
      if (data is String && data.trim().isNotEmpty)
        target = Uri.tryParse(data.trim());
    } catch (_) {
      // Official player derives a companion XML when URL lookup is unavailable.
    }
    target ??= fallbackXml(playUrl);
    if (target == null) return [];
    if (target.scheme != 'https' ||
        !target.hasAuthority ||
        target.userInfo.isNotEmpty) {
      throw const FormatException('无效弹幕 XML 地址');
    }
    String body;
    try {
      body = await _xmlBody(target);
    } catch (error) {
      if (error is DioException && error.response != null) rethrow;
      // Some official CDN nodes close connections using the content hostname.
      // Resolve only the site's own frontend CNAME and preserve the XML Host.
      // Both original and alternate requests retain normal TLS verification.
      if (!target.host.endsWith('.girigirilove.com') ||
          !target.path.startsWith('/zijian/'))
        rethrow;
      final alias = await _cdnAlias();
      if (alias == null) rethrow;
      body = await _xmlBody(target.replace(host: alias), host: target.host);
    }
    return parseXml(body);
  }

  Future<String?> _cdnAlias() async {
    const endpoints = [
      'https://dns.alidns.com/resolve',
      'https://cloudflare-dns.com/dns-query',
    ];
    final result = Completer<String?>();
    final tokens = [for (final _ in endpoints) CancelToken()];
    var pending = endpoints.length;
    Future<void> query(int index) async {
      try {
        final dns = await _xml.get<dynamic>(
          endpoints[index],
          queryParameters: {'name': 'ani.girigirilove.com', 'type': 'CNAME'},
          cancelToken: tokens[index],
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: const Duration(seconds: 4),
            headers: {'Accept': 'application/dns-json'},
          ),
        );
        final alias = cycaniList(cycaniMap(dns.data)['Answer'])
            .where((row) => cycaniInt(row['type']) == 5)
            .map((row) => '${row['data']}'.replaceFirst(RegExp(r'\.$'), ''))
            .where(
              (name) =>
                  RegExp(r'^[a-zA-Z0-9-]+\.girigirilove\.com$').hasMatch(name),
            )
            .firstOrNull;
        if (alias != null && !result.isCompleted) result.complete(alias);
      } catch (_) {
        // A failed resolver must not win over a healthy concurrent resolver.
      } finally {
        if (--pending == 0 && !result.isCompleted) result.complete(null);
      }
    }

    for (var i = 0; i < endpoints.length; i++) {
      unawaited(query(i));
    }
    try {
      return await result.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    } finally {
      for (final token in tokens) {
        token.cancel('Resolver race complete');
      }
    }
  }

  Future<String> _xmlBody(Uri uri, {String? host}) async {
    Future<Response<String>> read() => _xml.getUri<String>(
      uri,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Referer': 'https://ani.girigirilove.com/',
          if (host != null) 'Host': host,
        },
      ),
    );
    final response = host == null
        ? await read()
        : await retryPublicCatalogRead(read);
    return response.data ?? '';
  }
}
