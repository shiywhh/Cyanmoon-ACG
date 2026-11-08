import 'catalog_snapshot.dart';
import 'catalog_http.dart';
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cyanmoon_acg/services/logging/logger.dart';
import 'catalog_models.dart';

abstract interface class CycaniVault {
  Future<String?> read();
  Future<void> write(String? value);
}

class CycaniSecureVault implements CycaniVault {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _key = 'cycani.native.session.v1';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String? value) => value == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: value);
}

class CycaniException implements Exception {
  const CycaniException(this.message, [this.code = -1]);
  final String message;
  final int code;
  @override
  String toString() => message;
}

String normalizeCycaniToken(Object? value) {
  if (value is! String) throw const CycaniException('登录信息无效，请重新登录', 401);
  var token = value.trim();
  final prefix = RegExp(r'^Bearer\s+', caseSensitive: false);
  while (prefix.hasMatch(token)) {
    token = token.replaceFirst(prefix, '').trim();
  }
  if (token.isEmpty || RegExp(r'\s').hasMatch(token)) {
    throw const CycaniException('登录信息无效，请重新登录', 401);
  }
  return token;
}

class CycaniApi extends ChangeNotifier {
  CycaniApi({Dio? dio, CycaniVault? vault, FlutterSecureStorage? libraryStore})
    : _dio = dio ?? Dio(),
      _vault = vault ?? CycaniSecureVault(),
      _libraryStore =
          libraryStore ??
          (vault == null ? const FlutterSecureStorage() : null) {
    _dio.options = BaseOptions(
      baseUrl: '$origin/api',
      followRedirects: false,
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'X-App-Name': 'cyc_web',
        'X-App-Version': 'cycweb',
        'X-Time-Zone': 'Asia/Shanghai',
        'Referer': '$origin/',
      },
    );
    if (dio == null) {
      // The site's regional gate rejects the machine's proxy exit. This
      // affects only this API client, never the user's global proxy settings.
      _dio.httpClientAdapter = CatalogHttp.directAdapter();
    }
  }
  static final instance = CycaniApi();
  static const origin = 'https://www.cycani.org';
  static const pluginName = '次元城';
  final Dio _dio;
  final CycaniVault _vault;
  String? _token;
  CatalogJson _user = {};
  CatalogJson _watchStats = {};
  int _epoch = 0;
  Future<void>? _refreshing;
  final Map<int, CatalogVideo> _details = {};
  bool includeSiteDanmaku = false;
  String? storageWarning;
  bool get loggedIn => _token?.isNotEmpty == true;
  CatalogJson get user => Map.unmodifiable(_user);
  int get sessionEpoch => _epoch;
  Object? get _owner => _user['id'] ?? _user['user_id'];
  CatalogJson get cachedWatchStats =>
      loggedIn && _owner != null && _watchStats['owner'] == _owner.toString()
      ? Map.unmodifiable(_watchStats)
      : {};

  Future<void> saveWatchStats(
    int watched,
    int favorites, {
    required int epoch,
  }) async {
    final owner = _owner;
    if (!loggedIn || owner == null || epoch != _epoch) return;
    _watchStats = {
      'owner': owner.toString(),
      'watched': watched,
      'favorites': favorites,
    };
    try {
      await _persist();
    } catch (_) {}
  }

  static const _libraryPrefix = 'cycani.native.library.v1.';
  final FlutterSecureStorage? _libraryStore;
  Future<void> _libraryWrites = Future.value();

  String? _libraryKey(int section, String category) {
    if (section == 5) return '${_libraryPrefix}history';
    if (section == 4 &&
        const {'', 'watching', 'want', 'watched'}.contains(category)) {
      return '${_libraryPrefix}favorites.$category';
    }
    return null;
  }

  Future<List<CatalogJson>?> readLibrarySnapshot(
    int section,
    String category,
  ) async {
    final store = _libraryStore;
    if (store == null) return null;
    final key = _libraryKey(section, category),
        owner = _owner?.toString(),
        epoch = _epoch;
    if (key == null || owner == null || !loggedIn) return null;
    try {
      final raw = await store.read(key: key);
      if (raw == null || !loggedIn || epoch != _epoch) return null;
      final data = catalogMap(jsonDecode(raw));
      if (data['owner'] != owner) return null;
      return catalogList(data['rows']);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLibrarySnapshot(
    int section,
    String category,
    List<CatalogJson> rows, {
    required int epoch,
  }) {
    final store = _libraryStore;
    if (store == null) return Future.value();
    final key = _libraryKey(section, category), owner = _owner?.toString();
    if (key == null || owner == null || !loggedIn || epoch != _epoch)
      return Future.value();
    _libraryWrites = _libraryWrites.then((_) async {
      if (!loggedIn || epoch != _epoch || owner != _owner?.toString()) return;
      try {
        final safe = [
          for (final row in rows.take(36))
            {
              ...catalogPickFields(row, const [
                'video_id',
                'id',
                'progress',
                'section_title',
                'category',
              ]),
              'video': catalogPickFields(
                row['video'] is Map ? catalogMap(row['video']) : row,
                const [
                  'video_id',
                  'id',
                  'title',
                  'cover_url',
                  'year',
                  'area',
                  'version',
                  'total',
                  'score',
                  'bangumi_id',
                ],
              ),
            },
        ];
        final data = jsonEncode({'owner': owner, 'rows': safe});
        if (data.length < 100000) await store.write(key: key, value: data);
      } catch (_) {}
    });
    return _libraryWrites;
  }

  Future<void> clearLibrarySnapshots() {
    final store = _libraryStore;
    if (store == null) return Future.value();
    _libraryWrites = _libraryWrites.then((_) async {
      try {
        for (final key in (await store.readAll()).keys.toList()) {
          if (key.startsWith(_libraryPrefix)) await store.delete(key: key);
        }
      } catch (_) {}
    });
    return _libraryWrites;
  }

  Future<void> restore() async {
    try {
      final raw = await _vault.read();
      if (raw == null) return;
      final data = catalogMap(jsonDecode(raw));
      _token = data['token'] == null
          ? null
          : normalizeCycaniToken(data['token']);
      _user = catalogMap(data['user']);
      _watchStats = catalogMap(data['watch_stats']);
      includeSiteDanmaku = data['site_danmaku'] == true;
      if (_token != data['token']) await _persist();
    } catch (_) {
      _token = null;
      _user = {};
      storageWarning = '登录存储读取失败，请重新登录；现有系统存储未被删除。';
    }
  }

  Future<void> _persist() async {
    await _vault.write(
      jsonEncode({
        'token': _token,
        'user': _user,
        'watch_stats': cachedWatchStats,
        'site_danmaku': includeSiteDanmaku,
      }),
    );
  }

  Future<void> setSiteDanmaku(bool enabled) async {
    includeSiteDanmaku = enabled;
    // 持久化失败不阻断状态广播：内存状态已生效，监听方必须刷新。
    try {
      await _persist();
    } catch (e) {
      CyanmoonLogger().w('CycaniApi: failed to persist session', error: e);
    }
    notifyListeners();
  }

  Future<void> logout() async {
    _epoch++;
    _token = null;
    _user = {};
    _watchStats = {};
    // 持久化失败不阻断状态广播：内存已登出，UI 必须同步刷新而不是卡在已登录态。
    try {
      await _vault.write(null);
    } catch (e) {
      CyanmoonLogger().w('CycaniApi: failed to clear session vault', error: e);
    }
    try {
      await clearLibrarySnapshots();
    } catch (e) {
      CyanmoonLogger().w('CycaniApi: failed to clear library snapshots', error: e);
    }
    notifyListeners();
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? query,
    dynamic body,
    bool auth = false,
    CancelToken? cancelToken,
    bool allowRefresh = true,
  }) async {
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('://')) {
      throw const CycaniException('无效的接口路径');
    }
    if (auth && !loggedIn) throw const CycaniException('请先登录次元城账户', 401);
    final epoch = _epoch;
    final token = _token;
    try {
      final response = await _dio.request<dynamic>(
        path,
        queryParameters: query,
        data: body,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 600,
          headers: {if (auth) 'Authorization': 'Bearer $token'},
        ),
      );
      if (auth && epoch != _epoch) throw const CycaniException('账户已切换，请重新操作');
      final data = catalogMap(response.data);
      final code = catalogInt(data['code'], -1);
      if ((response.statusCode == 401 || code == 401) && auth && allowRefresh) {
        await _refresh(epoch);
        return await request(
          path,
          method: method,
          query: query,
          body: body,
          auth: auth,
          cancelToken: cancelToken,
          allowRefresh: false,
        );
      }
      if (response.statusCode != 200 || code != 0) {
        throw CycaniException(
          '${data['msg'] ?? '接口请求失败 (${response.statusCode})'}',
          response.statusCode == 401 ? 401 : code,
        );
      }
      return data['data'];
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw const CycaniException('网络连接失败，请检查网络后重试');
    }
  }

  Future<void> _refresh(int epoch) async {
    final active = _refreshing;
    if (active != null) return active;
    final future = () async {
      try {
        final data = catalogMap(
          await request(
            '/auth/refresh',
            method: 'POST',
            auth: true,
            allowRefresh: false,
          ),
        );
        if (epoch != _epoch) throw const CycaniException('账户已切换');
        final next = data['token'];
        if (next is! String || next.isEmpty) {
          throw const CycaniException('登录已过期，请重新登录', 401);
        }
        _token = normalizeCycaniToken(next);
        if (data['user'] is Map) _user = catalogMap(data['user']);
        await _persist();
      } on CycaniException catch (e) {
        if (e.code == 401 && epoch == _epoch) await logout();
        rethrow;
      }
    }();
    _refreshing = future;
    try {
      await future;
    } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  Future<void> login(String username, String password) async {
    final data = catalogMap(
      await request(
        '/auth/login',
        method: 'POST',
        body: {'username': username.trim(), 'password': password},
      ),
    );
    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw const CycaniException('服务器未返回登录信息');
    }
    _epoch++;
    _token = normalizeCycaniToken(token);
    _user = catalogMap(data['user']);
    // 持久化失败不阻断状态广播：内存状态已生效，监听方必须刷新。
    try {
      await _persist();
    } catch (e) {
      CyanmoonLogger().w('CycaniApi: failed to persist session', error: e);
    }
    notifyListeners();
  }

  Future<void> importToken(String value) async {
    final token = normalizeCycaniToken(value);
    // Validate before replacing a previously working account session.
    final response = await _dio.get<dynamic>(
      '/user/me',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        followRedirects: false,
        validateStatus: (s) => s != null && s < 600,
      ),
    );
    final data = catalogMap(response.data);
    if (response.statusCode != 200 || data['code'] != 0) {
      throw const CycaniException('令牌无效或已过期', 401);
    }
    _epoch++;
    _token = token;
    _user = catalogMap(data['data']);
    // 持久化失败不阻断状态广播：内存状态已生效，监听方必须刷新。
    try {
      await _persist();
    } catch (e) {
      CyanmoonLogger().w('CycaniApi: failed to persist session', error: e);
    }
    notifyListeners();
  }

  Future<void> profile() async {
    final epoch = _epoch;
    final data = catalogMap(await request('/user/me', auth: true));
    if (epoch != _epoch) return;
    _user = data;
    // 持久化失败不阻断状态广播：内存状态已生效，监听方必须刷新。
    try {
      await _persist();
    } catch (e) {
      CyanmoonLogger().w('CycaniApi: failed to persist session', error: e);
    }
    notifyListeners();
  }

  Future<void> sendCode(String email, String type) => request(
    '/auth/send-code',
    method: 'POST',
    body: {'email': email.trim(), 'type': type},
  ).then((_) {});
  Future<void> register(CatalogJson fields) =>
      request('/v2/auth/register', method: 'POST', body: fields).then((_) {});
  Future<void> resetPassword(String email, String code, String password) =>
      request(
        '/auth/reset-password',
        method: 'POST',
        body: {
          'email': email.trim(),
          'code': code.trim(),
          'new_password': password,
        },
      ).then((_) {});
  Future<void> updateProfile(CatalogJson fields) async {
    await request('/user/me', method: 'PUT', body: fields, auth: true);
    await profile();
  }

  Future<void> changePassword(String old, String password) => request(
    '/user/me/password',
    method: 'PUT',
    auth: true,
    body: {'old_password': old, 'new_password': password},
  ).then((_) {});
  Future<void> bindEmail(String email, String code) async {
    await request(
      '/auth/bind-email',
      method: 'POST',
      auth: true,
      body: {'email': email.trim(), 'code': code.trim()},
    );
    await profile();
  }

  final _publicMetadata = <String, (DateTime, Future<List<CatalogJson>>)>{};
  Future<List<CatalogJson>> _metadata(String path) {
    final old = _publicMetadata[path];
    if (old != null &&
        DateTime.now().difference(old.$1) < const Duration(seconds: 45))
      return old.$2;
    late final Future<List<CatalogJson>> task;
    task = request(path).then(catalogList).catchError((Object error) {
      if (identical(_publicMetadata[path]?.$2, task))
        _publicMetadata.remove(path);
      throw error;
    });
    _publicMetadata[path] = (DateTime.now(), task);
    return task;
  }

  Future<List<CatalogJson>> recommendations() async =>
      catalogList(await request('/index/recommend'));
  Future<List<CatalogJson>> zones() => _metadata('/video-zones');
  Future<CatalogJson> videos({
    String keyword = '',
    int page = 1,
    int size = 36,
    int? zone,
    String? tag,
    String? year,
    String order = 'update_time',
    CancelToken? cancelToken,
  }) async => catalogMap(
    await request(
      keyword.isEmpty ? '/videos' : '/videos/search',
      query: {
        'page': page,
        'page_size': size.clamp(1, 100),
        if (keyword.isNotEmpty) 'q': keyword,
        if (zone != null || keyword.isEmpty) 'zone_id': zone ?? 1,
        if (tag?.isNotEmpty == true) 'tag': tag,
        if (year?.isNotEmpty == true) 'year': year,
        if (keyword.isEmpty) 'order_by': order,
      },
      cancelToken: cancelToken,
    ),
  );
  Future<CatalogVideo> detail(int id) async {
    final video = CatalogVideo(catalogMap(await request('/videos/$id')));
    _details[id] = video;
    return video;
  }

  int bangumiIdFor(int videoId) => _details[videoId]?.bangumiId ?? 0;
  Future<List<CatalogEpisodes>> episodes(int id, {CatalogVideo? video}) async {
    final detailValue = video ?? await detail(id);
    final result = await Future.wait(
      detailValue.sources.map((source) async {
        final code = '${source['code'] ?? ''}';
        if (code.isEmpty) return null;
        final items = <CatalogJson>[];
        var page = 1;
        while (true) {
          final data = catalogMap(
            await request(
              '/videos/$id/sections',
              query: {'player_code': code, 'page': page, 'page_size': 100},
            ),
          );
          final batch = catalogList(data);
          items.addAll(batch);
          final total = catalogInt(
            catalogMap(data['pager'])['total'],
            items.length,
          );
          if (batch.isEmpty || items.length >= total) break;
          if (page++ >= 1000) throw const CycaniException('选集分页响应异常');
        }
        if (items.isNotEmpty) {
          return CatalogEpisodes(
            name: '${source['title'] ?? code}',
            code: code,
            items: items,
          );
        }
        return null;
      }),
    );
    return result.whereType<CatalogEpisodes>().toList();
  }

  Future<String> playUrl(int sectionId) async {
    final data = catalogMap(
      await request('/v2/sections/$sectionId/play-url', auth: true),
    );
    final url = '${data['url'] ?? ''}';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const CycaniException('服务器未返回有效的视频地址');
    }
    return url;
  }

  Future<List<CatalogJson>> ranks() => _metadata('/ranks');
  Future<List<CatalogJson>> rankVideos(int id) async =>
      catalogList(await request('/ranks/$id/videos'));
  Future<List<CatalogJson>> schedule(int weekday) async =>
      catalogList(await request('/index/weekday', query: {'weekday': weekday}));
  int _favoriteRevision = 0, _historyRevision = 0;
  int libraryRevision(int section) =>
      section == 4 ? _favoriteRevision : _historyRevision;

  Future<void> _libraryChanged(int section, {bool clear = true}) async {
    if (section == 4) {
      _favoriteRevision++;
    } else {
      _historyRevision++;
    }
    if (clear) await clearLibrarySnapshots();
  }

  Future<CatalogJson> favorites({String? category, int page = 1}) async =>
      catalogMap(
        await request(
          '/user/favorites',
          auth: true,
          query: {
            'page': page,
            'page_size': 36,
            if (category != null && category.isNotEmpty) 'category': category,
          },
        ),
      );
  Future<CatalogJson> favoriteStatus(int id) async =>
      catalogMap(await request('/user/favorites/$id', auth: true));
  Future<void> favorite(int id, String category) => request(
    '/user/favorites',
    method: 'POST',
    auth: true,
    body: {'video_id': id, 'category': category},
  ).then((_) => _libraryChanged(4));
  Future<void> moveFavorites(List<int> ids, String category) => request(
    '/user/favorites/batch-category',
    method: 'POST',
    auth: true,
    body: {'video_ids': ids, 'to_category': category},
  ).then((_) => _libraryChanged(4));
  Future<void> removeFavorites(List<int> ids) => request(
    '/user/favorites/batch-delete',
    method: 'POST',
    auth: true,
    body: {'video_ids': ids},
  ).then((_) => _libraryChanged(4));
  Future<CatalogJson> histories({String? cursor}) async => catalogMap(
    await request(
      '/user/histories',
      auth: true,
      query: {'page_size': 36, 'cursor': ?cursor},
    ),
  );
  Future<CatalogJson> history(int id) async =>
      catalogMap(await request('/user/histories/$id', auth: true));
  Future<void> reportHistory(int sectionId, double progress, double duration) =>
      request(
        '/user/histories/report',
        method: 'POST',
        auth: true,
        body: {
          'section_id': sectionId,
          'progress': progress.isFinite
              ? (progress.clamp(0, 10000000) * 1000).round()
              : 0,
          'duration': duration.isFinite
              ? (duration.clamp(0, 10000000) * 1000).round()
              : 0,
        },
      ).then((_) => _libraryChanged(5, clear: false));
  Future<void> removeHistories(List<int> ids) => request(
    '/user/histories/batch-delete',
    method: 'POST',
    auth: true,
    body: {'video_ids': ids},
  ).then((_) => _libraryChanged(5));
  Future<void> clearHistories() => request(
    '/user/histories/clear',
    method: 'POST',
    auth: true,
  ).then((_) => _libraryChanged(5));
  Future<CatalogJson> comments(
    int id, {
    int page = 1,
    String order = 'time',
  }) async => catalogMap(
    await request(
      '/videos/$id/comments',
      query: {'page': page, 'page_size': 20, 'order_by': order},
    ),
  );
  Future<CatalogJson> replies(int id, {int page = 1}) async => catalogMap(
    await request(
      '/comments/$id/replies',
      query: {'page': page, 'page_size': 20},
    ),
  );
  Future<void> postComment(int videoId, String content, {int? parentId}) =>
      request(
        '/comments',
        method: 'POST',
        auth: true,
        body: {
          'video_id': videoId,
          'content': content.trim(),
          'parent_id': parentId,
        },
      ).then((_) {});
  Future<void> pinComment(int id, bool pinned) => request(
    '/comments/$id/pin',
    method: 'PUT',
    auth: true,
    body: {'pinned': pinned},
  ).then((_) {});
  Future<List<CatalogJson>> danmaku(int sectionId) async {
    final data = catalogMap(await request('/sections/$sectionId/danmaku'));
    return catalogList(data['items'] ?? data['list'] ?? data['danmaku']);
  }

  Future<void> postDanmaku(
    int sectionId,
    String content,
    double time, {
    String mode = 'normal',
    int color = 0xFFFFFF,
  }) => request(
    '/danmaku',
    method: 'POST',
    auth: true,
    body: {
      'section_id': sectionId,
      'content': content.trim(),
      'time_point': time,
      'mode': mode,
      'color': color,
    },
  ).then((_) {});
}
