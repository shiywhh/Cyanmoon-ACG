import 'package:cyanmoon_acg/services/logging/logger.dart';
import 'package:cyanmoon_acg/bean/dialog/dialog.dart';
import 'catalog_account_layout.dart';
import 'qingyue_my_page.dart' show CycaniAvatar;
import 'catalog_action.dart';
import 'site_avatar.dart';
import 'catalog_library_widgets.dart';
import 'catalog_account_widgets.dart';
import 'catalog_feed_widgets.dart';
import 'package:cyanmoon_acg/bean/card/bangumi_card.dart';
import 'package:cyanmoon_acg/bean/card/bangumi_timeline_card.dart';
import 'qingyue_home_page.dart' show catalogConfirm, QingyueHomePage;
import 'catalog_http.dart';
import 'package:cyanmoon_acg/bean/settings/settings_detail_scaffold.dart';
import 'xifan_challenge.dart';
import 'giri_collections.dart';
import 'catalog_avatar_store.dart';
import 'package:url_launcher/url_launcher.dart';
import 'catalog_read_retry.dart';
import 'cycani_profile_settings.dart';
import 'cycani_account_page.dart';
import 'cycani_api.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'catalog_models.dart';
import 'catalog_detail_page.dart';
import 'cycani_remote_danmaku.dart';

class SourceAccounts {
  SourceAccounts({Dio? giri, Dio? xifan, FlutterSecureStorage? storage})
    : _giri =
          giri ??
          _client('https://m3u8.girigirilove.com', {
            'Origin': 'https://ani.girigirilove.com',
            'Referer': 'https://ani.girigirilove.com/login',
          }),
      _xifan =
          xifan ??
          _client('https://api.xifanacg.com', {
            'apikey': CycaniRemoteDanmaku.publicClientKey,
            'Origin': 'https://next.xifanacg.com',
          }),
      _storage = storage ?? const FlutterSecureStorage();
  static final instance = SourceAccounts();
  final Dio _giri, _xifan;
  final FlutterSecureStorage _storage;
  static const _gKey = 'cycani.giri.session.v1',
      _xKey = 'cycani.xifan.session.v1';
  static Dio _client(String origin, Map<String, String> headers) =>
      CatalogHttp.client(origin, headers);

  final _cookie = <String, String>{};
  Future<CatalogJson?>? _giriSessionCheck;
  int _giriSessionEpoch = 0;
  int? _challenge;
  void _rememberCookies(Response<dynamic> res) {
    for (final raw in res.headers['set-cookie'] ?? const <String>[]) {
      try {
        final c = Cookie.fromSetCookieValue(raw);
        if (c.maxAge == 0 || c.value.isEmpty) {
          _cookie.remove(c.name);
        } else {
          _cookie[c.name] = c.value;
        }
      } catch (_) {}
    }
  }

  Options _gOptions({ResponseType? type, String? csrf}) => Options(
    responseType: type,
    headers: {
      if (csrf != null) 'X-CSRF-Token': csrf,
      if (_cookie.isNotEmpty)
        'Cookie': _cookie.entries.map((e) => '${e.key}=${e.value}').join('; '),
    },
  );
  Future<Uint8List> captcha() async {
    final id = 100 + Random.secure().nextInt(900);
    final res = await _giri.get<List<int>>(
      '/index.php/verify/index.html',
      queryParameters: {'id': id, '_t': DateTime.now().millisecondsSinceEpoch},
      options: _gOptions(type: ResponseType.bytes),
    );
    _rememberCookies(res);
    final b = res.data ?? [];
    if (b.length < 8 ||
        b[0] != 0x89 ||
        b[1] != 0x50 ||
        b[2] != 0x4e ||
        b[3] != 0x47 ||
        _cookie.isEmpty)
      throw const FormatException('验证码获取失败');
    _challenge = id;
    return Uint8List.fromList(b);
  }

  int _xEpoch = 0;
  Future<void> _sessionWrites = Future.value();

  int _sessionEpoch(bool giri) => giri ? _giriSessionEpoch : _xEpoch;

  Future<void> _writeSession(
    bool giri,
    int epoch,
    String? value, {
    bool clear = false,
  }) {
    final key = giri ? _gKey : _xKey;
    final task = _sessionWrites.then((_) async {
      if (epoch != _sessionEpoch(giri)) throw StateError('账户已切换');
      if (clear) {
        _statsSnapshots.remove(giri);
        _profileSnapshots.remove(giri);
        await _clearPrivateSnapshots(giri);
      }
      if (epoch != _sessionEpoch(giri)) throw StateError('账户已切换');
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    });
    // One failing write must not block subsequent logout or login writes.
    _sessionWrites = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return task;
  }

  Future<String> giriLogin(String user, String password, String verify) async {
    final id = _challenge;
    if (id == null || verify.trim().isEmpty)
      throw const FormatException('请输入验证码');
    _challenge = null;
    final epoch = ++_giriSessionEpoch;
    _giriSessionCheck = null;
    final r = await _giri.post<dynamic>(
      '/index.php/user/login',
      data: FormData.fromMap({
        'user_name': user.trim(),
        'user_pwd': password,
        'verify': verify.trim(),
        'id': '$id',
      }),
      options: _gOptions(),
    );
    if (epoch != _giriSessionEpoch) throw StateError('账户已切换');
    _rememberCookies(r);
    if (catalogInt(catalogMap(r.data)['code']) != 1)
      throw StateError('登录失败，请检查账号、密码和验证码');
    final status = await _giri.get<dynamic>(
      '/index.php/sso/status',
      options: _gOptions(),
    );
    if (epoch != _giriSessionEpoch) throw StateError('账户已切换');
    _rememberCookies(status);
    final d = catalogMap(catalogMap(status.data)['info']);
    final name = '${catalogMap(d['user'])['user_name'] ?? ''}';
    if (d['authenticated'] != true || name.isEmpty) throw StateError('登录会话未生效');
    await _writeSession(
      true,
      epoch,
      jsonEncode({'cookies': _cookie, 'name': name}),
      clear: true,
    );
    return name;
  }

  Future<CatalogJson> _xToken(
    String grant,
    CatalogJson body, {
    int? expectedEpoch,
    bool clear = false,
  }) async {
    final epoch = expectedEpoch ?? _xEpoch;
    if (epoch != _xEpoch) throw StateError('账户已切换');
    final d = catalogMap(
      (await _xifan.post<dynamic>(
        '/auth/v1/token',
        queryParameters: {'grant_type': grant},
        data: body,
      )).data,
    );
    if (d['access_token'] is! String || d['refresh_token'] is! String)
      throw StateError('登录会话无效');
    final session = {
      'access_token': d['access_token'],
      'refresh_token': d['refresh_token'],
      'expires_at':
          d['expires_at'] ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000 +
              catalogInt(d['expires_in']),
    };
    await _writeSession(false, epoch, jsonEncode(session), clear: clear);
    return session;
  }

  Future<void> xifanLogin(String email, String password) async {
    final epoch = ++_xEpoch;
    _xRefresh = null;
    await _xToken(
      'password',
      {'email': email.trim(), 'password': password, 'gotrue_meta_security': {}},
      expectedEpoch: epoch,
      clear: true,
    );
  }

  Future<CatalogJson>? _xRefresh;
  Future<Options?> _xOptions() async {
    final epoch = _xEpoch;
    await _sessionWrites.timeout(const Duration(seconds: 2), onTimeout: () {
      CyanmoonLogger().w('Xifan session read skipped a stuck write queue after 2s');
    });
    final raw = await _storage.read(key: _xKey);
    if (raw == null || epoch != _xEpoch) return null;
    var s = catalogMap(jsonDecode(raw));
    if (catalogInt(s['expires_at']) <=
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30) {
      final refresh = _xRefresh ??= _xToken('refresh_token', {
        'refresh_token': s['refresh_token'],
      }, expectedEpoch: epoch);
      try {
        s = await refresh;
      } on DioException catch (e) {
        if (identical(_xRefresh, refresh)) _xRefresh = null;
        // refresh_token 已失效（撤销/过期）：清掉死会话自动登出。
        // 否则 hasSession 持续返回 true 而 API 全部失败，页面卡死在已登录态。
        final status = e.response?.statusCode ?? 0;
        if (status == 400 || status == 401 || status == 403) {
          await logout(false);
          return null;
        }
        rethrow;
      } finally {
        if (identical(_xRefresh, refresh)) _xRefresh = null;
      }
    }
    if (epoch != _xEpoch) return null;
    return Options(headers: {'Authorization': 'Bearer ${s['access_token']}'});
  }

  Future<List<CatalogJson>> xifanHistory({int page = 1}) async {
    final options = await _xOptions();
    if (options == null) return [];
    return catalogList(
      (await _xifan.post<dynamic>(
        '/rest/v1/rpc/get_continue_watching',
        data: {'p_limit': 30, 'p_offset': (page - 1) * 30},
        options: options,
      )).data,
    );
  }

  Future<CatalogJson?> xifanProgressFor(int animeId) async {
    if (animeId <= 0) return null;
    final epoch = _xEpoch;
    final options = await _xOptions();
    if (options == null || epoch != _xEpoch) return null;
    const size = 100;
    final seen = <int>{};
    for (var offset = 0; offset < 3000; offset += size) {
      final response = await _xifan.post<dynamic>(
        '/rest/v1/rpc/get_continue_watching',
        data: {'p_limit': size, 'p_offset': offset},
        options: options,
      );
      if (epoch != _xEpoch) return null;
      final rows = catalogList(response.data);
      var added = false;
      for (final row in rows) {
        final id = catalogInt(row['anime_id']);
        if (id == animeId) return row;
        if (id > 0 && seen.add(id)) added = true;
      }
      if (!added || rows.length < size) return null;
    }
    return null;
  }

  Future<List<CatalogJson>> xifanFollows({int page = 1}) async {
    final options = await _xOptions();
    if (options == null) return [];
    return catalogList(
      (await _xifan.get<dynamic>(
        '/rest/v1/anime_favorites',
        queryParameters: {
          'select': 'anime_id,status,animes(id,title,cover_url)',
          'limit': 100,
          'offset': (page - 1) * 100,
          'order': 'anime_id.asc',
        },
        options: options,
      )).data,
    );
  }

  Future<void> removeHistory(bool giri, int id) async {
    if (id <= 0) throw ArgumentError.value(id);
    if (giri) {
      final session = await _giriSession();
      if (session == null) throw StateError('请先登录 GiriGiri');
      final csrf = session['csrf_token'];
      if (csrf is! String || csrf.isEmpty) throw StateError('登录会话无效');
      _giriData(
        await _giri.post<dynamic>(
          '/api.php/vod/historyDelete',
          data: {'user_id': _giriUser(session), 'vod_id': id},
          options: _gOptions(
            csrf: csrf,
          ).copyWith(contentType: Headers.formUrlEncodedContentType),
        ),
      );
    } else {
      final options = await _xOptions();
      if (options == null) throw StateError('请先登录稀饭');
      final response = await _xifan.post<dynamic>(
        '/rest/v1/rpc/delete_play_progress',
        data: {'p_anime_id': id},
        options: options,
      );
      final result = catalogMap(response.data);
      if (result['ok'] != true) throw StateError('删除历史失败');
    }
  }

  Future<int?> followStatus(bool giri, int id) async {
    if (giri) {
      final rows = await giriFollows();
      final row = rows.where((r) => catalogInt(r['vod_id']) == id).firstOrNull;
      return row == null
          ? null
          : catalogInt(row['status'] ?? row['follow_status'], 1);
    }
    final options = await _xOptions();
    if (options == null) return null;
    final result = await _xifan.get<dynamic>(
      '/rest/v1/anime_favorites',
      queryParameters: {'select': 'status', 'anime_id': 'eq.$id', 'limit': 1},
      options: options,
    );
    final row = catalogList(result.data).firstOrNull;
    return row == null ? null : catalogInt(row['status']);
  }

  Future<(List<CatalogJson>, bool)> libraryPage(
    bool giri, {
    required bool history,
    required int page,
  }) async {
    if (page < 1) throw ArgumentError.value(page);
    if (giri && !history)
      return (page == 1 ? await giriFollows() : <CatalogJson>[], false);
    final rows = history
        ? giri
              ? await giriHistory(page: page)
              : await xifanHistory(page: page)
        : await xifanFollows(page: page);
    return (
      rows,
      rows.length >=
          (giri
              ? 20
              : history
              ? 30
              : 100),
    );
  }

  Future<List<CatalogJson>> allLibraryRows(
    bool giri, {
    required bool history,
  }) async {
    final rows = <CatalogJson>[], seen = <int>{};
    for (var page = 1; page <= 100; page++) {
      final (next, more) = await libraryPage(
        giri,
        history: history,
        page: page,
      );
      final count = rows.length;
      for (final row in next) {
        final id = catalogInt(row[giri ? 'vod_id' : 'anime_id']);
        if (id > 0 && seen.add(id)) rows.add(row);
      }
      if (rows.length == count || !more) break;
    }
    return rows;
  }

  Future<void> setXifanFollow(int animeId, int? status) async {
    final options = await _xOptions();
    if (options == null) throw StateError('请先登录稀饭');
    final result = catalogMap(
      (await _xifan.post<dynamic>(
        '/rest/v1/rpc/set_anime_favorite',
        data: {'p_anime_id': animeId, 'p_status': status},
        options: options,
      )).data,
    );
    if (result['ok'] != true) throw StateError('追番更新失败');
  }

  Future<void> recordXifanProgress(
    int episodeId,
    int position,
    int duration,
  ) async {
    if (episodeId <= 0 || position <= 0 || duration <= 0) return;
    final options = await _xOptions();
    if (options == null) return;
    final result = catalogMap(
      (await _xifan.post<dynamic>(
        '/rest/v1/rpc/set_play_progress',
        data: {
          'p_episode_id': episodeId,
          'p_position_ms': position.clamp(0, duration),
          'p_duration_ms': duration,
        },
        options: options,
      )).data,
    );
    if (result['ok'] != true) throw StateError('播放进度同步失败');
  }

  Future<CatalogJson?> _giriSession() {
    final inFlight = _giriSessionCheck;
    if (inFlight != null) return inFlight;
    final epoch = _giriSessionEpoch;
    late final Future<CatalogJson?> pending;
    pending = _checkGiriSession(epoch).whenComplete(() {
      if (identical(_giriSessionCheck, pending)) _giriSessionCheck = null;
    });
    _giriSessionCheck = pending;
    return pending;
  }

  Future<CatalogJson?> _checkGiriSession(int epoch) async {
    await _sessionWrites.timeout(const Duration(seconds: 2), onTimeout: () {
      CyanmoonLogger().w('Giri session read skipped a stuck write queue after 2s');
    });
    final raw = await _storage.read(key: _gKey);
    if (raw == null || epoch != _giriSessionEpoch) return null;
    final saved = catalogMap(jsonDecode(raw));
    // 整体替换而非 clear 后逐条填充：无 await 间隙，并发的验证码请求不会读到半截 Cookie。
    final previousCookies = Map<String, String>.from(_cookie);
    _cookie
      ..clear()
      ..addAll({
        for (final entry in catalogMap(saved['cookies']).entries)
          if (entry.value is String) entry.key: entry.value as String,
      });
    final response = await _giri.get<dynamic>(
      '/index.php/sso/status',
      options: _gOptions(),
    );
    if (epoch != _giriSessionEpoch) return null;
    _rememberCookies(response);
    final info = catalogMap(catalogMap(response.data)['info']);
    if (info['authenticated'] != true) {
      await logout(true);
      return null;
    }
    // 仅在 cookie 实际变化时回写，避免每次会话检查都做一遍平台通道存储写入。
    final changed = _cookie.length != previousCookies.length ||
        _cookie.entries.any((e) => previousCookies[e.key] != e.value);
    if (changed) {
      await _writeSession(
        true,
        epoch,
        jsonEncode({'cookies': _cookie, 'name': saved['name']}),
      );
    }
    return info;
  }

  int _giriUser(CatalogJson session) {
    final id = catalogInt(catalogMap(session['user'])['user_id']);
    if (id <= 0) throw StateError('登录会话无效');
    return id;
  }

  Future<List<CatalogJson>> giriHistory({int page = 1}) async {
    final session = await _giriSession();
    if (session == null) return [];
    final data = _giriData(
      await _giri.get<dynamic>(
        '/api.php/Vod/history',
        queryParameters: {'user_id': _giriUser(session), 'page': page},
        options: _gOptions(),
      ),
    );
    return catalogList(data is Map ? data['rows'] : data);
  }

  dynamic _giriData(Response<dynamic> response) {
    final body = catalogMap(response.data);
    if (catalogInt(body['code']) != 1) {
      throw StateError('GiriGiri 历史同步失败');
    }
    return body['info'];
  }

  Future<void> recordGiriHistory(int vodId) async {
    if (vodId <= 0) throw ArgumentError.value(vodId);
    final session = await _giriSession();
    if (session == null) return;
    final csrf = session['csrf_token'];
    if (csrf is! String || csrf.isEmpty) throw StateError('登录会话无效');
    _giriData(
      await _giri.post<dynamic>(
        '/api.php/vod/historyRecord',
        data: {'user_id': _giriUser(session), 'vod_id': vodId},
        options: _gOptions(
          csrf: csrf,
        ).copyWith(contentType: Headers.formUrlEncodedContentType),
      ),
    );
  }

  Future<dynamic> _giriCollectionCall(
    String operation,
    CatalogJson data, {
    bool write = false,
  }) async {
    final epoch = _giriSessionEpoch;
    final session = await _giriSession();
    if (epoch != _giriSessionEpoch || session == null)
      throw StateError('请先登录 GiriGiri');
    final csrf = session['csrf_token'];
    if (write && (csrf is! String || csrf.isEmpty)) throw StateError('登录会话无效');
    return _giriData(
      await _giri.post<dynamic>(
        '/api.php/App2/$operation',
        data: FormData.fromMap({'user_id': _giriUser(session), ...data}),
        options: _gOptions(csrf: write ? csrf as String : null),
      ),
    );
  }

  Future<double> giriProgress(int vodId, int episodeNumber) async {
    if (vodId <= 0 || episodeNumber < 1) throw ArgumentError('无效剧集');
    final epoch = _giriSessionEpoch;
    final value = await _giriCollectionCall('getVodPlayTime', {
      'vod_id': '$vodId',
      'no': '$episodeNumber',
    });
    if (epoch != _giriSessionEpoch) throw StateError('账户已切换');
    final seconds =
        double.tryParse('${value is Map ? value['time'] : value}') ?? 0;
    return seconds.isFinite && seconds > 0 ? seconds : 0;
  }

  Future<void> recordGiriProgress(
    int vodId,
    int episodeNumber,
    double seconds,
  ) async {
    if (vodId <= 0 || episodeNumber < 1 || !seconds.isFinite || seconds <= 0) {
      throw ArgumentError('无效观看进度');
    }
    await _giriCollectionCall('setVodPlayTime', {
      'vod_id': '$vodId',
      'no': '$episodeNumber',
      'time': '$seconds',
    }, write: true);
  }

  Future<List<CatalogJson>> giriCollectionGroups() async =>
      catalogList(await _giriCollectionCall('collectGroupList', {}));

  Future<List<CatalogJson>> giriCollectionItems(int group) async => catalogList(
    await _giriCollectionCall('collectGroupIdsList', {
      'group_id': '$group',
      'order': 'click_time',
    }),
  );

  Future<void> createGiriCollection(String title) async {
    await _giriCollectionCall('collectGroupAdd', {
      'group_name': title,
      'sort': '0',
    }, write: true);
  }

  Future<void> removeGiriCollection(int group) async {
    await _giriCollectionCall('collectGroupDelete', {
      'id': '$group',
    }, write: true);
  }

  Future<void> addGiriCollectionItem(int group, int id) async {
    await _giriCollectionCall('collectGroupIdsAdd', {
      'group_id': '$group',
      'vod_id': '$id',
    }, write: true);
  }

  Future<void> removeGiriCollectionItem(int group, int id) async {
    await _giriCollectionCall('collectGroupIdsDelete', {
      'group_id': '$group',
      'vod_ids': '$id',
    }, write: true);
  }

  int? _giriHomeSnapshotEpoch;
  List<CatalogJson> _giriHomeSnapshot = [];
  List<CatalogJson> get cachedGiriHomeAccountSections =>
      _giriHomeSnapshotEpoch == _giriSessionEpoch ? _giriHomeSnapshot : [];

  Future<List<CatalogJson>> giriHomeAccountSections() async {
    final epoch = _giriSessionEpoch;
    final session = await _giriSession();
    if (session == null || epoch != _giriSessionEpoch) return [];
    final previous = cachedGiriHomeAccountSections;
    final id = _giriUser(session);
    Future<List<CatalogJson>> read(
      String name,
      String path,
      Map<String, dynamic> data,
    ) async {
      try {
        final result = await _giri.post<dynamic>(
          path,
          data: FormData.fromMap({'user_id': id, ...data}),
          options: _gOptions(),
        );
        return [
          for (final row in catalogList(_giriData(result)))
            if (catalogInt(row['vod_id']) > 0)
              {
                'video_id': row['vod_id'],
                'title': row['vod_name'],
                'cover_url': row['vod_pic'],
                'year': row['vod_year'],
                'catalog_source': 'giri',
              },
        ];
      } catch (_) {
        return catalogList(
          previous.where((r) => r['name'] == name).firstOrNull?['videos'],
        );
      }
    }

    final sections = await Future.wait([
      read('追番更新', '/api.php/App2/collectList', {'status': '1', 'order': ''}),
      read('为你推荐', '/api.php/App2/likeList', {'pageSize': '12'}),
    ]);
    if (epoch != _giriSessionEpoch) return [];
    _giriHomeSnapshotEpoch = epoch;
    return _giriHomeSnapshot = [
      if (sections[0].isNotEmpty)
        {'name': '追番更新', 'videos': sections[0].take(10).toList()},
      if (sections[1].isNotEmpty) {'name': '为你推荐', 'videos': sections[1]},
    ];
  }

  Future<List<CatalogJson>> giriFollows() async {
    final session = await _giriSession();
    if (session == null) return [];
    return _giriFollows(session);
  }

  Future<List<CatalogJson>> _giriFollows(CatalogJson session) async {
    return catalogList(
      _giriData(
        await _giri.post<dynamic>(
          '/api.php/App2/collectList',
          data: FormData.fromMap({
            'user_id': _giriUser(session),
            'status': '',
            'order': '',
          }),
          options: _gOptions(),
        ),
      ),
    );
  }

  Future<void> setGiriFollow(int vodId, int status) async {
    if (vodId <= 0 || status < 0 || status > 3) throw ArgumentError('追番参数无效');
    final epoch = _sessionEpoch(true);
    final session = await _giriSession();
    if (session == null) throw StateError('请先登录 GiriGiri');
    final csrf = session['csrf_token'];
    if (csrf is! String || csrf.isEmpty) throw StateError('登录会话无效');
    final exists = (await _giriFollows(
      session,
    )).any((row) => catalogInt(row['vod_id']) == vodId);
    if (epoch != _sessionEpoch(true)) throw StateError('账户已切换');
    if (status == 0 && !exists) return;
    final op = status == 0
        ? 'Delete'
        : exists
        ? 'Edit'
        : 'Add';
    _giriData(
      await _giri.post<dynamic>(
        '/api.php/App2/collect$op',
        data: FormData.fromMap({
          'user_id': _giriUser(session),
          'vod_id': vodId,
          if (status != 0) 'status': status,
        }),
        options: _gOptions(csrf: csrf),
      ),
    );
  }

  Future<CatalogJson> readComments(
    bool giri,
    int id, {
    int page = 1,
    Object? cursor,
    Object? parent,
    String sort = 'latest',
  }) async {
    if (giri) {
      return catalogMap(
        _giriData(
          await retryPublicCatalogRead(
            () => _giri.get<dynamic>(
              '/api.php/Comment/get_list',
              queryParameters: {'vod_id': id, 'page': page},
            ),
          ),
        ),
      );
    }
    final rpc = parent == null ? 'get_comments' : 'get_comment_replies';
    return catalogMap(
      (await _xifan.post<dynamic>(
        '/rest/v1/rpc/$rpc',
        data: {
          if (parent == null) 'p_anime_id': id else 'p_parent_id': parent,
          if (parent == null) 'p_sort': sort,
          'p_limit': 20,
          if (cursor != null) 'p_cursor': cursor,
        },
        options: await _xOptions(),
      )).data,
    );
  }

  Future<void> postComment(
    bool giri,
    int id,
    String content, {
    Object? parent,
  }) async {
    if (giri) {
      final session = await _giriSession();
      if (session == null) throw StateError('请先登录 GiriGiri');
      final csrf = session['csrf_token'];
      if (csrf is! String || csrf.isEmpty) throw StateError('登录会话无效');
      final r = await _giri.post<dynamic>(
        '/api.php/Comment/add',
        data: FormData.fromMap({
          'user_id': _giriUser(session),
          'vod_id': id,
          'p_id': parent ?? 0,
          'content': content,
        }),
        options: _gOptions(csrf: csrf),
      );
      if (catalogInt(catalogMap(r.data)['code']) != 1) throw StateError('发布失败');
    } else {
      await xifanCommentAction('post_comment', {
        'p_anime_id': id,
        'p_content': content,
        if (parent != null) 'p_parent_id': parent,
      });
    }
  }

  Future<void> xifanCommentAction(String operation, CatalogJson data) async {
    if (!const {
      'post_comment',
      'delete_own_comment',
      'toggle_comment_reaction',
    }.contains(operation)) {
      throw ArgumentError.value(operation);
    }
    final options = await _xOptions();
    if (options == null) throw StateError('请先登录稀饭');
    final result = await _xifan.post<dynamic>(
      '/rest/v1/rpc/$operation',
      data: data,
      options: options,
    );
    if (catalogMap(result.data)['ok'] != true) throw StateError('评论操作失败');
  }

  static void _checkDanmaku(
    String content,
    double time,
    String mode,
    int color,
  ) {
    if (content.trim().isEmpty ||
        !time.isFinite ||
        time < 0 ||
        !const ['normal', 'top', 'bottom'].contains(mode) ||
        color < 0 ||
        color > 0xFFFFFF) {
      throw ArgumentError('弹幕参数无效');
    }
  }

  Future<void> postXifanDanmaku(
    int episodeId,
    String content,
    double time, {
    String mode = 'normal',
    int color = 0xFFFFFF,
  }) async {
    _checkDanmaku(content, time, mode, color);
    if (episodeId <= 0) throw ArgumentError.value(episodeId);
    final epoch = _xEpoch;
    final options = await _xOptions();
    if (options == null || epoch != _xEpoch) throw StateError('请先登录稀饭');
    final response = await _xifan.post<dynamic>(
      '/rest/v1/rpc/send_danmaku',
      options: options,
      data: {
        'p_episode_id': episodeId,
        'p_content': content.trim(),
        'p_v_time': time,
        'p_mode': mode == 'normal' ? 'scroll' : mode,
        'p_color': '#${color.toRadixString(16).padLeft(6, '0')}',
      },
    );
    if (catalogMap(response.data)['ok'] != true) throw StateError('弹幕发送失败');
  }

  Future<void> reportXifanDanmaku(int id, String reason) async {
    if (id <= 0 || reason.trim().isEmpty) throw ArgumentError('举报参数无效');
    final epoch = _xEpoch;
    final options = await _xOptions();
    if (options == null || epoch != _xEpoch) throw StateError('请先登录稀饭');
    final response = await _xifan.post<dynamic>(
      '/rest/v1/rpc/report',
      options: options,
      data: {
        'p_target_type': 'danmaku',
        'p_target_id': id,
        'p_reason': reason.trim(),
      },
    );
    if (catalogMap(response.data)['ok'] != true) throw StateError('举报失败');
  }

  Future<void> postGiriDanmaku(
    String playUrl,
    String content,
    double time, {
    String mode = 'normal',
    int color = 0xFFFFFF,
  }) async {
    _checkDanmaku(content, time, mode, color);
    final uri = Uri.tryParse(playUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        !const ['http', 'https'].contains(uri.scheme)) {
      throw ArgumentError.value(playUrl);
    }
    final epoch = _giriSessionEpoch;
    final session = await _giriSession();
    if (session == null || epoch != _giriSessionEpoch) {
      throw StateError('请先登录 GiriGiri');
    }
    final response = await _giri.post<dynamic>(
      '/api.php/Scrolling/add',
      options: _gOptions(
        csrf: session['csrf_token'] is String
            ? session['csrf_token'] as String
            : null,
      ),
      data: FormData.fromMap({
        'play_url': playUrl,
        'scroll_json': jsonEncode({
          'stime': 0,
          'mode': switch (mode) {
            'top' => 2,
            'bottom' => 3,
            _ => 1,
          },
          'text': '',
          'color': '',
          'time': time,
          'content': content.trim(),
          'style': {
            'color': '#${color.toRadixString(16).padLeft(6, '0')}',
            'border': 'var(--theme) solid 2px',
          },
          'duration': 8,
        }),
      }),
    );
    if (catalogInt(catalogMap(response.data)['code']) != 1) {
      throw StateError('弹幕发送失败');
    }
  }

  Future<void> reportGiriDanmaku(int scrollId) async {
    if (scrollId <= 0) throw ArgumentError.value(scrollId);
    final epoch = _giriSessionEpoch;
    final session = await _giriSession();
    if (session == null || epoch != _giriSessionEpoch) {
      throw StateError('请先登录 GiriGiri');
    }
    final response = await _giri.get<dynamic>(
      '/api.php/Scrolling/remove',
      options: _gOptions(
        csrf: session['csrf_token'] is String
            ? session['csrf_token'] as String
            : null,
      ),
      queryParameters: {'scroll_id': '$scrollId'},
    );
    if (catalogInt(catalogMap(response.data)['code']) != 1) {
      throw StateError('举报失败');
    }
  }

  Future<String> requestXifanEmailChange(
    String email,
    Map<String, String> challenge,
  ) async {
    final normalized = email.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      throw StateError('请输入有效邮箱');
    }
    final data = parseXifanChallenge(challenge);
    if (data == null) throw StateError('请完成安全验证');
    final options = await _xOptions();
    if (options == null) throw StateError('请先登录稀饭');
    final response = await _xifan.post<dynamic>(
      '/functions/v1/request-email-change',
      data: {'new_email': normalized, 'geetest': data},
      options: options,
    );
    final result = catalogMap(response.data);
    if (result['sent'] != true || result['masked_email'] is! String)
      throw StateError('验证码发送失败');
    return result['masked_email'] as String;
  }

  Future<String> confirmXifanEmailChange(String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) throw StateError('请输入六位验证码');
    final options = await _xOptions();
    if (options == null) throw StateError('请先登录稀饭');
    final response = await _xifan.post<dynamic>(
      '/rest/v1/rpc/confirm_email_change',
      data: {'p_code': code.trim()},
      options: options,
    );
    final result = catalogMap(response.data);
    if (result['success'] != true || result['new_email'] is! String)
      throw StateError('邮箱换绑失败');
    return result['new_email'] as String;
  }

  Future<void> changeXifanPassword(
    String currentPassword,
    String newPassword,
  ) async {
    if (currentPassword.isEmpty ||
        newPassword.length < 6 ||
        currentPassword == newPassword) {
      throw StateError('请填写当前密码和不同的新密码');
    }
    final epoch = _xEpoch;
    final current = await profile(false);
    final email = current?['email'];
    if (email is! String || email.isEmpty) throw StateError('请先登录稀饭');
    CatalogJson reauthenticated;
    try {
      reauthenticated = await _xToken('password', {
        'email': email,
        'password': currentPassword,
        'gotrue_meta_security': {},
      }, expectedEpoch: epoch);
    } on DioException catch (e) {
      if (e.response?.statusCode == 400 || e.response?.statusCode == 401) {
        throw StateError('当前密码验证失败');
      }
      rethrow;
    }
    final response = await _xifan.put<dynamic>(
      '/auth/v1/user',
      data: {'password': newPassword},
      options: Options(
        headers: {'Authorization': 'Bearer ${reauthenticated['access_token']}'},
      ),
    );
    final updated = catalogMap(response.data);
    if (updated['id'] != current?['id']) throw StateError('密码修改结果未确认');
  }

  Future<void> updateXifanProfile({
    String? displayName,
    String? avatarUrl,
  }) async {
    final options = await _xOptions();
    if (options == null) throw StateError('请先登录稀饭');
    final r = await _xifan.post<dynamic>(
      '/rest/v1/rpc/update_profile',
      data: {
        if (displayName != null) 'p_display_name': displayName,
        if (avatarUrl != null) 'p_avatar_url': avatarUrl,
      },
      options: options,
    );
    if (catalogMap(r.data)['ok'] != true) throw StateError('资料保存失败');
  }

  Future<CatalogJson> giriAccount() async {
    if (await _giriSession() == null) throw StateError('请先登录 GiriGiri');
    return catalogMap(
      _giriData(
        await _giri.get<dynamic>(
          '/index.php/sso/account',
          options: _gOptions(),
        ),
      ),
    );
  }

  Future<Uri> startGiriReauthentication() async {
    final account = await giriAccount();
    final user = catalogInt(catalogMap(account['user'])['user_id']);
    final csrf = account['csrf_token'];
    final rules = catalogMap(account['reauthentication']);
    if (user <= 0 || csrf is! String || csrf.isEmpty)
      throw StateError('登录会话无效');
    final response = await _giri.post<dynamic>(
      '/index.php/sso/reauth',
      data: {
        'expected_user_id': '$user',
        'csrf_token': csrf,
        'return_to': 'https://ani.girigirilove.com/profile',
        if (rules['default_source'] case final String source
            when source.isNotEmpty)
          'source': source,
      },
      options: _gOptions().copyWith(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    final info = catalogMap(_giriData(response));
    final url = Uri.tryParse('${info['authorization_url'] ?? ''}');
    final query = url?.queryParametersAll;
    if (catalogInt(info['expires_in']) != 60 ||
        url == null ||
        url.scheme != 'https' ||
        url.host != 'm3u8.girigirilove.com' ||
        url.hasPort ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        url.path != '/index.php/sso/reauth' ||
        query?.length != 1 ||
        query?['ticket']?.length != 1 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(query!['ticket']!.single)) {
      throw StateError('身份验证链接无效');
    }
    return url;
  }

  Future<void> renameGiri(String username, String nickname) async {
    final account = await giriAccount();
    final rules = catalogMap(account['reauthentication']);
    if (rules['required'] != false) throw StateError('请先在 GiriGiri 官网完成身份验证');
    final userId = catalogInt(catalogMap(account['user'])['user_id']);
    final token = account['csrf_token'];
    if (userId <= 0 || token is! String || token.isEmpty)
      throw StateError('登录会话无效');
    _giriData(
      await _giri.post<dynamic>(
        '/index.php/sso/rename',
        data: {
          'expected_user_id': '$userId',
          'csrf_token': token,
          'user_name': username,
          'user_nick_name': nickname,
        },
        options: _gOptions().copyWith(
          contentType: Headers.formUrlEncodedContentType,
        ),
      ),
    );
  }

  String _privateSnapshotKey(bool giri, String kind) =>
      'catalog.account.${giri ? 'giri' : 'xifan'}.$kind.v1';

  Future<List<CatalogJson>?> cachedGiriCollections(int? group) async {
    final epoch = _sessionEpoch(true);
    try {
      if (await _storage.read(key: _gKey) == null) return null;
      final key = _privateSnapshotKey(
        true,
        group == null ? 'collections' : 'collection-$group',
      );
      final saved = await _storage.read(key: key);
      if (epoch != _sessionEpoch(true)) return null;
      return saved == null ? null : catalogList(jsonDecode(saved));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveGiriCollections(
    int? group,
    List<CatalogJson> rows, {
    int? expectedSession,
  }) {
    final epoch = expectedSession ?? _sessionEpoch(true);
    return _writePrivateSnapshot(true, epoch, () async {
      if (await _storage.read(key: _gKey) == null ||
          epoch != _sessionEpoch(true))
        return;
      final key = _privateSnapshotKey(
        true,
        group == null ? 'collections' : 'collection-$group',
      );
      final data = jsonEncode(rows.take(100).toList());
      if (data.length < 150000) await _storage.write(key: key, value: data);
    });
  }

  Future<CatalogJson?> cachedWatchStats(bool giri, String owner) async {
    if (owner.isEmpty) return null;
    final epoch = _sessionEpoch(giri);
    try {
      final profile = await cachedProfile(giri);
      if ((profile?['id'] ?? profile?['user_id'])?.toString() != owner)
        return null;
      final raw = await _storage.read(
        key: _privateSnapshotKey(giri, 'watch-stats'),
      );
      final value = raw == null ? null : catalogMap(jsonDecode(raw));
      if (epoch != _sessionEpoch(giri) || value?['owner'] != owner) return null;
      if (value != null) _statsSnapshots[giri] = value;
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePrivateSnapshot(
    bool giri,
    int epoch,
    Future<void> Function() write,
  ) {
    final task = _sessionWrites
        .then((_) async {
          if (epoch != _sessionEpoch(giri)) return;
          await write();
        })
        .catchError((Object _, StackTrace __) {});
    _sessionWrites = task;
    return task;
  }

  Future<void> saveWatchStats(
    bool giri,
    String owner,
    int watched,
    int favorites, {
    int? expectedSession,
  }) {
    if (owner.isEmpty) return Future.value();
    final epoch = expectedSession ?? _sessionEpoch(giri);
    return _writePrivateSnapshot(giri, epoch, () async {
      final profile = await cachedProfile(giri);
      if (epoch != _sessionEpoch(giri) ||
          (profile?['id'] ?? profile?['user_id'])?.toString() != owner)
        return;
      final value = <String, dynamic>{
        'owner': owner,
        'watched': watched,
        'favorites': favorites,
      };
      _statsSnapshots[giri] = value;
      await _storage.write(
        key: _privateSnapshotKey(giri, 'watch-stats'),
        value: jsonEncode(value),
      );
    });
  }

  final _statsSnapshots = <bool, CatalogJson>{};
  CatalogJson? watchStatsSnapshot(bool giri, String owner) {
    final saved = _statsSnapshots[giri];
    return owner.isNotEmpty && saved?['owner'] == owner ? saved : null;
  }

  Future<void> _restoreSourceSnapshots(bool giri) async {
    final profile = await cachedProfile(giri);
    final owner = (profile?['id'] ?? profile?['user_id'] ?? '').toString();
    if (owner.isNotEmpty) await cachedWatchStats(giri, owner);
  }

  final _profileSnapshots = <bool, CatalogJson>{};
  CatalogJson? profileSnapshot(bool giri) => _profileSnapshots[giri];
  Future<void> restoreSnapshots() async {
    await Future.wait([
      for (final source in [false, true]) _restoreSourceSnapshots(source),
    ]);
  }

  Future<CatalogJson?> cachedProfile(bool giri) async {
    final epoch = _sessionEpoch(giri);
    try {
      if (await _storage.read(key: giri ? _gKey : _xKey) == null) return null;
      final saved = await _storage.read(
        key: _privateSnapshotKey(giri, 'profile'),
      );
      final value = saved == null ? null : catalogMap(jsonDecode(saved));
      if (epoch != _sessionEpoch(giri)) return null;
      if (value != null) _profileSnapshots[giri] = value;
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<List<CatalogJson>?> cachedLibrary(bool giri, int library) async {
    final epoch = _sessionEpoch(giri);
    try {
      if (await _storage.read(key: giri ? _gKey : _xKey) == null) return null;
      final saved = await _storage.read(
        key: _privateSnapshotKey(giri, 'library-$library'),
      );
      if (epoch != _sessionEpoch(giri)) return null;
      return saved == null ? null : catalogList(jsonDecode(saved));
    } catch (_) {
      return null;
    }
  }

  int librarySession(bool giri) => _sessionEpoch(giri);

  Future<void> saveLibrary(
    bool giri,
    int library,
    List<CatalogJson> rows, {
    int? expectedSession,
  }) {
    final epoch = expectedSession ?? _sessionEpoch(giri);
    final task = _sessionWrites
        .then((_) async {
          if (epoch != _sessionEpoch(giri)) return;
          final session = await _storage.read(key: giri ? _gKey : _xKey);
          if (session == null || epoch != _sessionEpoch(giri)) return;
          final snapshot = jsonEncode(rows.take(100).toList());
          if (snapshot.length < 200000) {
            await _storage.write(
              key: _privateSnapshotKey(giri, 'library-$library'),
              value: snapshot,
            );
          }
        })
        .catchError((Object _, StackTrace __) {});
    _sessionWrites = task;
    return task;
  }

  Future<void> _clearPrivateSnapshots(bool giri) async {
    for (final key in [
      'profile',
      'library-4',
      'library-5',
      'watch-stats',
      if (giri) 'collections',
    ]) {
      await _storage.delete(key: _privateSnapshotKey(giri, key));
    }
    if (giri) {
      final keys = (await _storage.readAll()).keys.where(
        (key) => key.startsWith('catalog.account.giri.collection-'),
      );
      for (final key in keys.toList()) {
        await _storage.delete(key: key);
      }
    }
  }

  Future<CatalogJson?> profile(bool giri) async {
    final epoch = _sessionEpoch(giri);
    final result = await _readProfile(giri);
    if (result == null || epoch != _sessionEpoch(giri)) return null;
    _profileSnapshots[giri] = result;
    await _writePrivateSnapshot(giri, epoch, () async {
      final session = await _storage.read(key: giri ? _gKey : _xKey);
      if (session == null || epoch != _sessionEpoch(giri)) return;
      final safe = {
        for (final field in [
          'id',
          'user_id',
          'nickname',
          'email',
          'avatar_url',
        ])
          if (result[field] != null) field: result[field],
      };
      await _storage.write(
        key: _privateSnapshotKey(giri, 'profile'),
        value: jsonEncode(safe),
      );
    });
    return epoch == _sessionEpoch(giri) ? result : null;
  }

  Future<CatalogJson?> _readProfile(bool giri) async {
    if (giri) {
      final session = await _giriSession();
      if (session == null) return null;
      final user = catalogMap(session['user']);
      return {
        ...user,
        'nickname': user['user_nick_name'] ?? user['user_name'],
        'avatar_url': user['user_portrait'],
      };
    }
    final options = await _xOptions();
    if (options == null) return null;
    final user = catalogMap(
      (await _xifan.get<dynamic>('/auth/v1/user', options: options)).data,
    );
    final meta = catalogMap(user['user_metadata']);
    return {
      ...user,
      'nickname': meta['nickname'] ?? meta['username'],
      'avatar_url': meta['avatar_url'],
    };
  }

  Future<bool> hasSession(bool giri) async => giri
      ? await _giriSession() != null
      : await _storage.read(key: _xKey) != null;

  Future<void> logout(bool giri) async {
    final epoch = giri ? ++_giriSessionEpoch : ++_xEpoch;
    _profileSnapshots.remove(giri);
    _statsSnapshots.remove(giri);
    if (giri) {
      _giriSessionCheck = null;
      _cookie.clear();
      _challenge = null;
    } else {
      _xRefresh = null;
    }
    await _writeSession(giri, epoch, null, clear: true);
  }
}

class SourceAccountsPage extends StatefulWidget {
  const SourceAccountsPage({
    super.key,
    this.initialGiri,
    this.library,
    this.cycaniApi,
    this.accountApi,
  });
  final CycaniApi? cycaniApi;
  final SourceAccounts? accountApi;
  final bool? initialGiri;
  final int? library;
  @override
  State<SourceAccountsPage> createState() => _SourceAccountsPageState();
}

class _SourceAccountsPageState extends State<SourceAccountsPage> {
  final _librarySearch = TextEditingController();
  bool _listMode = false, _selectLibrary = false;
  int _libraryStatus = -1;
  final _selectedLibrary = <int>{};
  static final _libraryViews = <(bool, int), (String, bool, int)>{};
  void _saveLibraryView() {
    if (widget.library != null)
      _libraryViews[(giri, widget.library!)] = (
        _librarySearch.text,
        _listMode,
        _libraryStatus,
      );
  }

  AppLifecycleListener? _lifecycle;
  int? _pendingGiriVerification;
  bool _reopenGiriVerification = false;

  void _resumeGiriVerification() {
    if (!mounted || _pendingGiriVerification == null) return;
    if (busy) {
      _reopenGiriVerification = true;
      return;
    }
    final id = _pendingGiriVerification!;
    _pendingGiriVerification = null;
    _giriSettings(expectedUser: id);
  }

  SourceAccounts get api => widget.accountApi ?? SourceAccounts.instance;
  final user = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController();
  bool giri = false, busy = false;
  bool? logged;
  CatalogJson? profile;
  static final _snapshotSessions = <bool, (SourceAccounts, int)>{};
  static final _sessions = <bool, bool>{};

  void _validateSnapshots() {
    final session = (api, api.librarySession(giri));
    if (_snapshotSessions[giri] == session) return;
    _snapshotSessions[giri] = session;
    _sessions.remove(giri);
    _profiles.remove(giri);
    _rows.remove((giri, 4));
    _rows.remove((giri, 5));
    _paging.remove((giri, 4));
    _paging.remove((giri, 5));
  }

  static final _profiles = <bool, CatalogJson>{};
  static final _rows = <(bool, int), List<CatalogJson>>{};
  static final _paging = <(bool, int), (int, bool)>{};

  Uint8List? image;
  String? error;
  List<CatalogJson> history = [], follows = [];
  int _libraryPage = 0, _libraryGeneration = 0;
  bool _libraryHasMore = false, _libraryLoading = false, _refreshing = false;
  String? _loadMoreError;

  Future<void> _appendLibrary() async {
    final library = widget.library;
    if (library == null ||
        logged != true ||
        !_libraryHasMore ||
        _libraryLoading ||
        _refreshing ||
        busy)
      return;
    final generation = _libraryGeneration, next = _libraryPage + 1;
    final session = api.librarySession(giri);
    setState(() {
      _libraryLoading = true;
      _loadMoreError = null;
    });
    try {
      final (rows, more) = await api.libraryPage(
        giri,
        history: library == 5,
        page: next,
      );
      if (!mounted ||
          generation != _libraryGeneration ||
          session != api.librarySession(giri))
        return;
      final current = library == 5 ? history : follows;
      final seen = current
          .map((r) => catalogInt(r[giri ? 'vod_id' : 'anime_id']))
          .toSet();
      final incoming = rows.where((r) {
        final id = catalogInt(r[giri ? 'vod_id' : 'anime_id']);
        return id > 0 && seen.add(id);
      }).toList();
      final updated = [...current, ...incoming];
      setState(() {
        _libraryPage = next;
        _libraryHasMore = more && incoming.isNotEmpty;
        if (library == 5) {
          history = updated;
        } else {
          follows = updated;
        }
        _rows[(giri, library)] = updated;
        _paging[(giri, library)] = (_libraryPage, _libraryHasMore);
      });
      await api.saveLibrary(giri, library, updated, expectedSession: session);
    } catch (_) {
      if (mounted && generation == _libraryGeneration)
        setState(() => _loadMoreError = '加载更多失败，重试');
    } finally {
      if (mounted && generation == _libraryGeneration)
        setState(() => _libraryLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    giri = widget.initialGiri ?? false;
    final view = _libraryViews[(giri, widget.library ?? 0)];
    if (view != null) {
      _librarySearch.text = view.$1;
      _listMode = view.$2;
      _libraryStatus = view.$3;
    }
    if (giri)
      _lifecycle = AppLifecycleListener(onResume: _resumeGiriVerification);
    if (widget.initialGiri != null) {
      _validateSnapshots();
      logged = _sessions[giri];
      profile = _profiles[giri] ?? api.profileSnapshot(giri);
      if (profile != null) logged = true;
      history = _rows[(giri, 5)] ?? [];
      follows = _rows[(giri, 4)] ?? [];
      final paging = _paging[(giri, widget.library ?? 0)];
      if (paging != null) {
        _libraryPage = paging.$1;
        _libraryHasMore = paging.$2;
      }
      _restoreDisk();
      _refresh();
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _librarySearch.dispose();
    user.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _openItem(CatalogJson row, {required bool isHistory}) async {
    final item = catalogLibraryItem(row, giri: giri, history: isHistory);
    if (CatalogVideo(item).id <= 0) return;
    final session = api.librarySession(giri);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CatalogDetailPage(row: item)),
    );
    if (mounted && session == api.librarySession(giri)) await _refresh();
  }

  Future<void> _restoreDisk() async {
    final session = api.librarySession(giri);
    final library = widget.library;
    final saved = await api.cachedProfile(giri);
    final rows = library == null
        ? null
        : await api.cachedLibrary(giri, library);
    if (!mounted ||
        session != api.librarySession(giri) ||
        logged == false ||
        _libraryPage > 0 ||
        saved == null && rows == null)
      return;
    setState(() {
      logged = true;
      profile ??= saved;
      if (library == 4 && rows != null && follows.isEmpty) follows = rows;
      if (library == 5 && rows != null && history.isEmpty) history = rows;
    });
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final selected = giri, library = widget.library;
    final session = api.librarySession(selected);
    ++_libraryGeneration;
    setState(() {
      _refreshing = true;
      _libraryLoading = false;
      _loadMoreError = null;
    });
    try {
      final has = await api.hasSession(selected);
      final details = has && library == null
          ? await api.profile(selected)
          : null;
      final rows = <CatalogJson>[];
      var more = false, pages = 0;
      if (has && library != null) {
        final targetPages = max(1, _libraryPage);
        final seen = <int>{};
        for (var page = 1; page <= targetPages; page++) {
          final (incoming, hasMore) = await api.libraryPage(
            selected,
            history: library == 5,
            page: page,
          );
          if (!mounted || session != api.librarySession(selected)) return;
          var added = 0;
          for (final row in incoming) {
            final id = catalogInt(row[selected ? 'vod_id' : 'anime_id']);
            if (id > 0 && seen.add(id)) {
              rows.add(row);
              added++;
            }
          }
          pages = page;
          more = hasMore && added > 0;
          if (!more) break;
        }
      }
      if (!mounted ||
          selected != giri ||
          session != api.librarySession(selected))
        return;
      _validateSnapshots();
      _sessions[selected] = has;
      if (details != null) _profiles[selected] = details;
      if (library != null) {
        _rows[(selected, library)] = rows;
        _paging[(selected, library)] = (pages, more);
      }
      setState(() {
        logged = has;
        error = null;
        profile = has ? details ?? _profiles[selected] : null;
        _libraryPage = max(1, pages);
        _libraryHasMore = more;
        if (library == 5) history = rows;
        if (library == 4) follows = rows;
      });
      if (library != null && has)
        await api.saveLibrary(
          selected,
          library,
          rows,
          expectedSession: session,
        );
    } catch (_) {
      if (mounted &&
          selected == giri &&
          session == api.librarySession(selected)) {
        setState(() => error = '读取失败，下拉重试');
      }
    } finally {
      if (mounted)
        setState(() {
          _refreshing = false;
          if (selected == giri && session != api.librarySession(selected)) {
            _validateSnapshots();
            logged = false;
            profile = null;
            history = [];
            follows = [];
            _libraryPage = 0;
            _libraryHasMore = false;
            _selectedLibrary.clear();
          }
        });
    }
  }

  Future<void> _removeHistory(CatalogJson row) async {
    if (busy) return;
    final id = catalogInt(row[giri ? 'vod_id' : 'anime_id']);
    if (id <= 0) return;
    final confirmed = await catalogConfirm(context, '删除观看记录？');
    if (!mounted || confirmed != true) return;
    setState(() => busy = true);
    try {
      final session = api.librarySession(giri);
      await api.removeHistory(giri, id);
      if (!mounted || session != api.librarySession(giri)) return;
      setState(() {
        history = history
            .where(
              (item) => catalogInt(item[giri ? 'vod_id' : 'anime_id']) != id,
            )
            .toList();
        _rows[(giri, 5)] = history;
      });
      await api.saveLibrary(giri, 5, history, expectedSession: session);
      await _refresh();
    } catch (e) {
      if (mounted)
        setState(() => error = e is StateError ? e.message : '删除历史失败');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _changeXifanEmail() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => _XifanEmailPage(api: api)));
    if (mounted) await _refresh();
  }

  Future<void> _changeXifanPassword() async {
    final credentials = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _XifanPasswordDialog(),
    );
    if (!mounted || credentials == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await api.changeXifanPassword(credentials.$1, credentials.$2);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码已修改')));
    } catch (e) {
      if (mounted)
        setState(() => error = e is StateError ? e.message : '密码修改失败');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _giriSettings({int? expectedUser}) async {
    setState(() => busy = true);
    try {
      final account = await api.giriAccount();
      if (!mounted) return;
      final user = catalogMap(account['user']);
      final userId = catalogInt(user['user_id']);
      if (expectedUser != null && userId != expectedUser)
        throw StateError('账户已切换');

      final email = catalogMap(account['email']);
      final rules = catalogMap(account['reauthentication']);
      final changes = await showDialog<(String, String)>(
        context: context,
        builder: (_) => _XifanProfileDialog(
          profile: {
            'nickname': user['user_nick_name'],
            'username': user['user_name'],
          },
          giri: true,
          emailVerified: email['verified'] == true,
          editable: rules['required'] == false,
          onVerify: rules['required'] == false
              ? null
              : () => _openGiriVerification(userId),
        ),
      );
      if (changes != null && mounted) {
        await api.renameGiri(changes.$2, changes.$1);
        await _refresh();
      }
    } catch (e) {
      if (mounted)
        setState(() => error = e is StateError ? e.message : '读取账户资料失败');
    } finally {
      if (mounted) setState(() => busy = false);
      if (_reopenGiriVerification) {
        _reopenGiriVerification = false;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _resumeGiriVerification(),
        );
      }
    }
  }

  Future<void> _openGiriVerification(int userId) async {
    final url = await api.startGiriReauthentication();
    _pendingGiriVerification = userId;
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('打开身份验证失败');
      }
    } catch (_) {
      _pendingGiriVerification = null;
      rethrow;
    }
  }

  Future<void> _editXifan() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _XifanProfileDialog(profile: profile ?? {}),
    );
    if (result == null || !mounted) return;
    setState(() => busy = true);
    try {
      final (name, avatar) = result;
      await api.updateXifanProfile(
        displayName: name.isEmpty ? null : name,
        avatarUrl: avatar.isEmpty ? null : avatar,
      );
      await _refresh();
    } catch (e) {
      if (mounted)
        setState(() => error = e is StateError ? e.message : '资料保存失败');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _captcha() async {
    if (busy) return;
    setState(() {
      busy = true;
      image = null;
      error = null;
      code.clear();
    });
    try {
      final bytes = await api.captcha();
      if (mounted) setState(() => image = bytes);
    } catch (_) {
      if (mounted) setState(() => error = '验证码获取失败');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _login() async {
    if (busy ||
        user.text.trim().isEmpty ||
        password.text.isEmpty ||
        (giri && code.text.trim().isEmpty))
      return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (giri) {
        await api.giriLogin(user.text, password.text, code.text);
      } else {
        await api.xifanLogin(user.text, password.text);
      }
      password.clear();
      await _refresh();
    } catch (_) {
      if (mounted)
        setState(() {
          error = '登录失败，请核对输入';
          image = null;
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  int _rowId(CatalogJson row) => catalogInt(row[giri ? 'vod_id' : 'anime_id']);

  int _followState(CatalogJson row) {
    final status = catalogInt(row['status'] ?? row['follow_status'], 1);
    return giri
        ? status
        : switch (status) {
            0 => 2,
            2 => 3,
            _ => 1,
          };
  }

  void _toggleLibrary(int id) {
    if (busy || id <= 0) return;
    setState(() {
      if (!_selectedLibrary.add(id)) _selectedLibrary.remove(id);
    });
  }

  Future<void> _changeLibrary(Set<int> ids, {int? followState}) async {
    if (busy || ids.isEmpty) return;
    final selectedSource = giri, library = widget.library!;
    final session = api.librarySession(selectedSource);
    final deleting = library == 5 || followState == 0;
    if (deleting && !await catalogConfirm(context, '删除所选记录？')) return;
    if (!mounted || session != api.librarySession(selectedSource)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      for (final id in ids.toList()) {
        if (!mounted || session != api.librarySession(selectedSource)) return;
        if (library == 5) {
          await api.removeHistory(selectedSource, id);
        } else if (selectedSource) {
          await api.setGiriFollow(id, followState!);
        } else {
          await api.setXifanFollow(id, switch (followState) {
            0 => null,
            2 => 0,
            3 => 2,
            _ => 1,
          });
        }
        if (!mounted || session != api.librarySession(selectedSource)) return;
        final current = library == 5 ? history : follows;
        final updated = <CatalogJson>[
          for (final row in current)
            if (_rowId(row) != id)
              row
            else if (!deleting)
              {
                ...row,
                'status': selectedSource
                    ? followState
                    : switch (followState) {
                        2 => 0,
                        3 => 2,
                        _ => 1,
                      },
              },
        ];
        setState(() {
          if (library == 5) {
            history = updated;
          } else {
            follows = updated;
          }
          _rows[(selectedSource, library)] = updated;
          _selectedLibrary.remove(id);
        });
        // Save each confirmed success. Failed rows remain selected for retry.
        await api.saveLibrary(
          selectedSource,
          library,
          updated,
          expectedSession: session,
        );
      }
    } catch (_) {
      if (mounted && session == api.librarySession(selectedSource))
        setState(() => error = '部分操作失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _libraryPageView() {
    final isHistory = widget.library == 5;
    final raw = isHistory ? history : follows;
    final query = _librarySearch.text.trim().toLowerCase();
    final shown = raw
        .where(
          (row) =>
              (isHistory ||
                  _libraryStatus < 0 ||
                  _followState(row) == _libraryStatus) &&
              CatalogVideo(
                catalogLibraryItem(row, giri: giri, history: isHistory),
              ).title.toLowerCase().contains(query),
        )
        .toList();
    final items = shown
        .map((row) => catalogLibraryItem(row, giri: giri, history: isHistory))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(isHistory ? '观看历史' : '我的追番'),
        actions: [
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    _selectLibrary = !_selectLibrary;
                    _selectedLibrary.clear();
                  }),
            child: Text(_selectLibrary ? '完成' : '批量管理'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            CatalogLibraryToolbar(
              search: _librarySearch,
              listMode: _listMode,
              onSearch: (_) => setState(_saveLibraryView),
              onView: (value) => setState(() {
                _listMode = value;
                _saveLibraryView();
              }),
            ),
            const SizedBox(height: 12),
            if (!isHistory || _selectLibrary)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!isHistory)
                      for (final entry in {
                        -1: '全部',
                        1: '在看',
                        2: '想看',
                        3: '看过',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _libraryStatus == entry.key,
                          onSelected: busy
                              ? null
                              : (_) => setState(() {
                                  _libraryStatus = entry.key;
                                  _saveLibraryView();
                                }),
                        ),
                    if (_selectLibrary) ...[
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                final ids = shown
                                    .map(_rowId)
                                    .where((id) => id > 0)
                                    .toSet();
                                if (ids.isNotEmpty &&
                                    _selectedLibrary.containsAll(ids)) {
                                  _selectedLibrary.removeAll(ids);
                                } else {
                                  _selectedLibrary.addAll(ids);
                                }
                              }),
                        child: const Text('选择当前列表'),
                      ),
                      Text('已选 ${_selectedLibrary.length}'),
                      if (!isHistory)
                        PopupMenuButton<int>(
                          tooltip: '移动已选',
                          enabled: !busy && _selectedLibrary.isNotEmpty,
                          onSelected: (state) => _changeLibrary(
                            Set.of(_selectedLibrary),
                            followState: state,
                          ),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 1, child: Text('在看')),
                            PopupMenuItem(value: 2, child: Text('想看')),
                            PopupMenuItem(value: 3, child: Text('看过')),
                          ],
                          child: const Chip(label: Text('移动已选')),
                        ),
                      TextButton.icon(
                        onPressed: busy || _selectedLibrary.isEmpty
                            ? null
                            : () => _changeLibrary(
                                Set.of(_selectedLibrary),
                                followState: 0,
                              ),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除已选'),
                      ),
                    ],
                  ],
                ),
              ),
            if (busy) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: CustomScrollView(
                  key: PageStorageKey(
                    'library-$giri-${widget.library}-${api.librarySession(giri)}',
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (error != null)
                      SliverToBoxAdapter(
                        child: TextButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: Text(error!),
                        ),
                      ),
                    if (shown.isEmpty && !_refreshing)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('暂无内容')),
                        ),
                      ),
                    CatalogVideoSliver(
                      items: items,
                      horizontal: _listMode,
                      tileBuilder: (context, index) {
                        final row = shown[index],
                            video = CatalogVideo(items[index]);
                        final card = _listMode
                            ? BangumiTimelineCard(
                                bangumiItem: video.toBangumi(),
                                showRating: false,
                                onTap: () => _selectLibrary
                                    ? _toggleLibrary(video.id)
                                    : _openItem(row, isHistory: isHistory),
                              )
                            : BangumiCardV(
                                bangumiItem: video.toBangumi(),
                                enableHero: false,
                                onTap: () => _selectLibrary
                                    ? _toggleLibrary(video.id)
                                    : _openItem(row, isHistory: isHistory),
                              );
                        return Stack(
                          children: [
                            Positioned.fill(child: card),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Material(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                                shape: const CircleBorder(),
                                child: _selectLibrary
                                    ? Checkbox(
                                        value: _selectedLibrary.contains(
                                          video.id,
                                        ),
                                        onChanged: busy
                                            ? null
                                            : (_) => _toggleLibrary(video.id),
                                      )
                                    : isHistory
                                    ? IconButton(
                                        tooltip: '删除观看记录',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: busy
                                            ? null
                                            : () => _removeHistory(row),
                                      )
                                    : PopupMenuButton<int>(
                                        tooltip: '追番状态',
                                        enabled: !busy,
                                        onSelected: (state) => _changeLibrary({
                                          video.id,
                                        }, followState: state),
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 1,
                                            child: Text('在看'),
                                          ),
                                          PopupMenuItem(
                                            value: 2,
                                            child: Text('想看'),
                                          ),
                                          PopupMenuItem(
                                            value: 3,
                                            child: Text('看过'),
                                          ),
                                          PopupMenuItem(
                                            value: 0,
                                            child: Text('取消追番'),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    SliverToBoxAdapter(
                      child: CatalogLoadMore(
                        loading: _libraryLoading || _refreshing,
                        hasMore: _libraryHasMore,
                        error: _loadMoreError,
                        loadMore: _appendLibrary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountDashboard() {
    final user = profile ?? const <String, dynamic>{};
    final id = '${user['id'] ?? user['user_id'] ?? ''}';
    final avatars = CatalogAvatarStore.instance;
    return Scaffold(
      appBar: AppBar(title: Text(giri ? 'GiriGiri' : '稀饭')),
      body: CatalogAccountDashboard(
        header: ListenableBuilder(
          listenable: avatars,
          builder: (context, _) => CatalogProfileHeader(
            avatar: SiteAvatar(
              path: avatars.sourcePath(giri ? 'giri' : 'xifan', id),
              url: '${user['avatar_url'] ?? ''}',
            ),
            name: catalogAccountName(user),
            id: id,
          ),
        ),
        refresh: _refresh,
        busy: busy,
        error: error,
        logout: () => runCatalogAction(
          busy: busy,
          active: () => mounted,
          setBusy: (value) => setState(() => busy = value),
          action: () async {
            await api.logout(giri);
            if (!mounted) return;
            _validateSnapshots();
            _sessions[giri] = false;
            await _refresh();
          },
          onError: (_) => setState(() => error = '退出账号失败'),
        ),
        accountActions: [
          CatalogAccountLink(
            title: giri ? '个人资料与安全' : '个人资料',
            icon: Icons.person_outline,
            onTap: busy ? null : (giri ? () => _giriSettings() : _editXifan),
          ),
          if (id.isNotEmpty)
            SiteAvatarPicker(
              choose: () => avatars.chooseSource(giri ? 'giri' : 'xifan', id),
              reset: () => avatars.clearSource(giri ? 'giri' : 'xifan', id),
              child: const ListTile(
                leading: Icon(Icons.image_outlined),
                title: Text('本机头像'),
                trailing: Icon(Icons.chevron_right),
              ),
            ),
          if (!giri)
            CatalogAccountLink(
              title: '更换邮箱',
              icon: Icons.email_outlined,
              onTap: busy ? null : _changeXifanEmail,
            ),
          if (!giri)
            CatalogAccountLink(
              title: '修改密码',
              icon: Icons.lock_outline,
              onTap: busy ? null : _changeXifanPassword,
            ),
        ],
        libraryActions: [
          for (final (kind, label, icon) in [
            (4, '我的追番', Icons.favorite_border),
            (5, '观看历史', Icons.history),
          ])
            CatalogAccountLink(
              title: label,
              icon: icon,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SourceAccountsPage(
                    initialGiri: giri,
                    library: kind,
                    accountApi: api,
                  ),
                ),
              ),
            ),
          if (giri)
            CatalogAccountLink(
              title: '收藏夹',
              icon: Icons.folder_outlined,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GiriCollectionsPage(accountApi: api),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialGiri == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('来源账号')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final (label, source) in [
              ('次元城', null),
              ('稀饭', false),
              ('GiriGiri', true),
            ])
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(
                        builder: (_) => source == null
                            ? CycaniSourceAccount(api: widget.cycaniApi)
                            : SourceAccountsPage(
                                initialGiri: source,
                                accountApi: api,
                              ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    }
    if (widget.library != null && logged == true) return _libraryPageView();
    if (logged == true) return _accountDashboard();
    final body = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        if (logged == null && error == null)
          const Center(child: CircularProgressIndicator())
        else if (logged == false) ...[
          CatalogAccountField(
            controller: user,
            label: giri ? '原视频账号' : '邮箱',
            enabled: !busy,
            keyboardType: giri
                ? TextInputType.text
                : TextInputType.emailAddress,
          ),
          CatalogAccountField(
            controller: password,
            label: '密码',
            secret: true,
            enabled: !busy,
          ),
          if (giri) ...[
            TextButton(
              onPressed: busy ? null : _captcha,
              child: Text(image == null ? '获取验证码' : '刷新验证码'),
            ),
            if (image != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Image.memory(
                  image!,
                  width: 150,
                  height: 50,
                  fit: BoxFit.contain,
                ),
              ),
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: '验证码'),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : _login,
            child: Text(giri ? '使用原视频账号登录' : '登录'),
          ),
        ],
        if (_libraryLoading || _refreshing && logged == true)
          const LinearProgressIndicator(),
        if (_loadMoreError != null)
          TextButton(onPressed: _appendLibrary, child: Text(_loadMoreError!)),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: Text(switch (widget.library) {
          4 => '我的追番',
          5 => '观看历史',
          _ => giri ? 'GiriGiri' : '稀饭',
        }),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 &&
                notification.metrics.extentAfter < 320 &&
                _loadMoreError == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _appendLibrary();
              });
            }
            return false;
          },
          child: body,
        ),
      ),
    );
  }
}

class CycaniSourceAccount extends StatelessWidget {
  const CycaniSourceAccount({super.key, this.api});
  final CycaniApi? api;
  Future<void> _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeContext) => SettingsPaneScope(
            embedded: true,
            showBackButton: true,
            onBack: () => Navigator.of(routeContext).pop(),
            child: page,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final current = api ?? CycaniApi.instance;
    return ListenableBuilder(
      listenable: current,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('次元城')),
        body: current.loggedIn
            ? CatalogAccountDashboard(
                header: ListenableBuilder(
                  listenable: CatalogAvatarStore.instance,
                  builder: (context, _) => CatalogProfileHeader(
                    avatar: CycaniAvatar(
                      api: current,
                      store: CatalogAvatarStore.instance,
                    ),
                    name: catalogAccountName(current.user),
                    id: '${current.user['id'] ?? current.user['user_id'] ?? ''}',
                  ),
                ),
                logout: () async {
                  try {
                    await current.logout();
                  } catch (_) {
                    if (context.mounted)
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('退出账号失败')));
                  }
                },
                accountActions: [
                  CatalogAccountLink(
                    title: '个人资料',
                    icon: Icons.person_outline,
                    onTap: () => _open(
                      context,
                      CycaniProfileSettingsPage(
                        api: current,
                        localNavigation: true,
                      ),
                    ),
                  ),
                  CatalogAccountLink(
                    title: '账户与安全',
                    icon: Icons.lock_outline,
                    onTap: () => _open(
                      context,
                      CycaniSecuritySettingsPage(
                        api: current,
                        localNavigation: true,
                      ),
                    ),
                  ),
                ],
                libraryActions: [
                  for (final (kind, label, icon) in [
                    (4, '我的追番', Icons.favorite_border),
                    (5, '观看历史', Icons.history),
                  ])
                    CatalogAccountLink(
                      title: label,
                      icon: icon,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => QingyueHomePage(
                            initialSection: kind,
                            standalone: true,
                            api: current,
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : CycaniAccountPage(embedded: true, api: current),
      ),
    );
  }
}

class _XifanProfileDialog extends StatefulWidget {
  const _XifanProfileDialog({
    required this.profile,
    this.giri = false,
    this.emailVerified = false,
    this.editable = true,
    this.onVerify,
  });
  final bool giri, emailVerified, editable;
  final Future<void> Function()? onVerify;
  final CatalogJson profile;

  @override
  State<_XifanProfileDialog> createState() => _XifanProfileDialogState();
}

class _XifanProfileDialogState extends State<_XifanProfileDialog> {
  late final name = TextEditingController(
    text: widget.profile['nickname']?.toString() ?? '',
  );
  late final avatar = TextEditingController(
    text:
        widget.profile[widget.giri ? 'username' : 'avatar_url']?.toString() ??
        '',
  );
  final form = GlobalKey<FormState>();
  bool verifying = false;
  String? verificationError;

  @override
  void dispose() {
    name.dispose();
    avatar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.giri ? '个人资料与安全' : '编辑个人资料'),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.giri) Text(widget.emailVerified ? '邮箱已验证' : '邮箱未验证'),
          if (widget.giri && !widget.editable) const Text('需在官网完成身份验证'),
          TextFormField(
            enabled: widget.editable,
            controller: name,
            decoration: const InputDecoration(labelText: '昵称'),
          ),
          TextFormField(
            enabled: widget.editable,
            controller: avatar,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: widget.giri ? '账号' : '头像链接'),
            validator: (value) {
              if (widget.giri)
                return value == null || value.trim().isEmpty ? '请输入账号' : null;
              if (value == null || value.trim().isEmpty) return null;
              final uri = Uri.tryParse(value.trim());
              return uri?.scheme == 'https' && uri!.host.isNotEmpty
                  ? null
                  : '请输入 HTTPS 链接';
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      // 需要官网身份验证时提供入口（此前 onVerify 从未被渲染，重验证流程不可达）。
      if (!widget.editable && widget.onVerify != null)
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              await widget.onVerify!();
            } catch (e) {
              CyanmoonLogger().w('SourceAccounts: open verification failed',
                  error: e);
              CyanmoonDialog.showToast(
                  message: e is StateError ? e.message : '打开身份验证失败');
            }
          },
          child: const Text('去官网验证'),
        ),
      FilledButton(
        onPressed: !widget.editable
            ? null
            : () {
                if (form.currentState?.validate() == true) {
                  Navigator.pop(context, (
                    name.text.trim(),
                    avatar.text.trim(),
                  ));
                }
              },
        child: const Text('保存'),
      ),
    ],
  );
}

class _XifanPasswordDialog extends StatefulWidget {
  const _XifanPasswordDialog();

  @override
  State<_XifanPasswordDialog> createState() => _XifanPasswordDialogState();
}

class _XifanPasswordDialogState extends State<_XifanPasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController(),
      _next = TextEditingController(),
      _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改密码'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: '当前密码'),
              validator: (v) => v == null || v.isEmpty ? '请输入当前密码' : null,
            ),
            TextFormField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码'),
              validator: (v) => v == null || v.length < 6
                  ? '至少 6 个字符'
                  : v == _current.text
                  ? '新密码与当前密码相同'
                  : null,
            ),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认新密码'),
              validator: (v) => v == _next.text ? null : '两次输入不一致',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState?.validate() == true) {
            Navigator.pop(context, (_current.text, _next.text));
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _XifanEmailPage extends StatefulWidget {
  const _XifanEmailPage({required this.api});
  final SourceAccounts api;
  @override
  State<_XifanEmailPage> createState() => _XifanEmailPageState();
}

class _XifanEmailPageState extends State<_XifanEmailPage> {
  final _email = TextEditingController(), _code = TextEditingController();
  bool _busy = false;
  String? _masked, _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) => runCatalogAction(
    busy: _busy,
    active: () => mounted,
    setBusy: (value) => setState(() {
      _busy = value;
      if (value) _error = null;
    }),
    action: action,
    onError: (error) => setState(
      () => _error = error is StateError ? error.message : '请求失败，请检查验证码或稍后重试',
    ),
  );

  Future<void> _send() => _run(() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email))
      throw StateError('请输入有效邮箱');
    final proof = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(builder: (_) => const XifanChallengePage()),
    );
    if (!mounted || proof == null) return;
    final masked = await widget.api.requestXifanEmailChange(email, proof);
    if (mounted) setState(() => _masked = masked);
  });

  Future<void> _confirm() => _run(() async {
    final email = await widget.api.confirmXifanEmailChange(_code.text);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('邮箱已换绑为 $email')));
    Navigator.of(context).pop();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('更换邮箱')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: _email,
          enabled: !_busy && _masked == null,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: '新邮箱'),
        ),
        if (_masked != null) ...[
          Text('验证码已发送至 $_masked'),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: '邮箱验证码'),
          ),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            child: const Text('确认换绑'),
          ),
        ],
        TextButton(
          onPressed: _busy ? null : _send,
          child: Text(_masked == null ? '验证并发送' : '重新发送'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
      ],
    ),
  );
}
