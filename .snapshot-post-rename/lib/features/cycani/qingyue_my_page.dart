import 'catalog_account_layout.dart';
import 'site_avatar.dart';
import 'dart:async';
import 'catalog_aggregator.dart';
import 'site_accounts.dart';
import 'cycani_account_stats.dart';
import 'qingyue_space_view.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/modules/my/watch_stats.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'cycani_api.dart';
import 'catalog_models.dart';
import 'catalog_avatar_store.dart';

class CycaniAvatar extends StatelessWidget {
  const CycaniAvatar({
    super.key,
    required this.api,
    required this.store,
    this.size = 76,
  });
  final CycaniApi api;
  final CatalogAvatarStore store;
  final double size;
  @override
  Widget build(BuildContext context) {
    final id = catalogInt(api.user['id'] ?? api.user['user_id']);
    final path = store.pathFor(id);
    final remote = '${api.user['avatar_url'] ?? ''}';
    return SiteAvatar(path: path, url: remote, size: size);
  }
}

class QingyueMyPage extends StatefulWidget {
  const QingyueMyPage({
    super.key,
    required this.api,
    this.source = CatalogSource.cycani,
    required this.openLibrary,
    required this.openDownloads,
  });
  final CycaniApi api;
  final CatalogSource source;
  final ValueChanged<int> openLibrary;
  final VoidCallback openDownloads;
  @override
  State<QingyueMyPage> createState() => _QingyueMyPageState();
}

class _QingyueMyPageState extends State<QingyueMyPage> {
  final avatars = CatalogAvatarStore.instance;
  MyController? stats;
  Future<CycaniAccountStats>? totals;
  late int sessionEpoch;
  static final _statistics = Expando<Map<Object, CycaniAccountStats>>();
  bool _profileResolved = false;
  int _loads = 0;
  Object get _statsKey =>
      external ? (widget.source, _owner(externalProfile)) : api.sessionEpoch;
  String _owner(CatalogJson? profile) =>
      (profile?['id'] ?? profile?['user_id'] ?? '').toString();

  CycaniAccountStats? _decode(CatalogJson? value) {
    if (value == null ||
        !value.containsKey('watched') ||
        !value.containsKey('favorites'))
      return null;
    return CycaniAccountStats(
      watchedVideos: catalogInt(value['watched']),
      favorites: catalogInt(value['favorites']),
    );
  }

  Future<void> _restoreStats() async {
    if (!external) {
      final saved = _decode(api.cachedWatchStats);
      if (saved != null) _last.putIfAbsent(_statsKey, () => saved);
      return;
    }
    final accounts = SourceAccounts.instance;
    final source = widget.source;
    final profile = await accounts.cachedProfile(giri);
    if (!mounted || source != widget.source || profile == null) return;
    final owner = _owner(profile);
    if (_profileResolved && owner != _owner(externalProfile)) return;
    final saved = _decode(await accounts.cachedWatchStats(giri, owner));
    if (!mounted ||
        source != widget.source ||
        _profileResolved && owner != _owner(externalProfile))
      return;
    setState(() {
      if (!_profileResolved) externalProfile = profile;
      if (saved != null) _last.putIfAbsent((source, owner), () => saved);
    });
  }

  Map<Object, CycaniAccountStats> get _last => _statistics[api] ??= {};
  CatalogJson? externalProfile;
  bool get external => widget.source != CatalogSource.cycani;
  bool get giri => widget.source == CatalogSource.giri;
  bool get signedIn => external ? externalProfile != null : api.loggedIn;

  Future<CycaniAccountStats> _externalStats(int load) async {
    final accounts = SourceAccounts.instance, selected = giri;
    final source = widget.source;
    final session = accounts.librarySession(selected);
    final profile = await accounts.profile(selected);
    if (mounted && load == _loads) {
      _profileResolved = true;
      setState(() => externalProfile = profile);
    }
    if (profile == null)
      return const CycaniAccountStats(watchedVideos: 0, favorites: 0);
    final owner = _owner(profile);
    final rows = await Future.wait([
      accounts.allLibraryRows(selected, history: true),
      accounts.allLibraryRows(selected, history: false),
    ]);
    if (session != accounts.librarySession(selected)) {
      throw StateError('账户已切换');
    }
    final value = CycaniAccountStats(
      watchedVideos: rows[0]
          .map((row) => catalogInt(row[selected ? 'vod_id' : 'anime_id']))
          .where((id) => id > 0)
          .toSet()
          .length,
      favorites: rows[1].length,
    );
    if (mounted && load == _loads && owner == _owner(externalProfile)) {
      _last[(source, owner)] = value;
      unawaited(
        accounts.saveWatchStats(
          selected,
          owner,
          value.watchedVideos,
          value.favorites,
          expectedSession: session,
        ),
      );
    }
    return value;
  }

  Future<CycaniAccountStats>? _loadTotals() {
    final load = ++_loads;
    if (external) return _externalStats(load);
    if (!api.loggedIn) return null;
    final epoch = api.sessionEpoch;
    final saved = _decode(api.cachedWatchStats);
    if (saved != null) _last.putIfAbsent(epoch, () => saved);
    return loadCycaniAccountStats(api).then((value) {
      if (epoch == api.sessionEpoch && api.loggedIn) {
        _last[epoch] = value;
        unawaited(
          api.saveWatchStats(
            value.watchedVideos,
            value.favorites,
            epoch: epoch,
          ),
        );
      }
      return value;
    });
  }

  CycaniApi get api => widget.api;
  @override
  void initState() {
    super.initState();
    sessionEpoch = api.sessionEpoch;
    if (external) {
      final accounts = SourceAccounts.instance;
      externalProfile = accounts.profileSnapshot(giri);
      final saved = _decode(
        accounts.watchStatsSnapshot(giri, _owner(externalProfile)),
      );
      if (saved != null) _last[_statsKey] = saved;
    }
    unawaited(_restoreStats());
    totals = _loadTotals();
    api.addListener(_changed);
    avatars.addListener(_changed);
    _prepare();
    try {
      stats = inject<MyController>();
      stats!.attach();
    } catch (_) {}
  }

  Future<void> _prepare() async {
    try {
      await avatars.initialize();
    } catch (_) {}
    if (!external && api.loggedIn) {
      try {
        await api.profile();
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    setState(() {
      totals = _loadTotals();
    });
    await _prepare();
    try {
      await totals;
    } catch (_) {}
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (!external && sessionEpoch != api.sessionEpoch) {
        sessionEpoch = api.sessionEpoch;
        totals = _loadTotals();
      }
    });
  }

  @override
  void dispose() {
    api.removeListener(_changed);
    avatars.removeListener(_changed);
    stats?.detach();
    super.dispose();
  }

  Future<void> _externalPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SourceAccountsPage(initialGiri: giri),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _account() async {
    if (external) {
      await _externalPage();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CycaniSourceAccount(api: api)),
    );
    if (mounted) await _prepare();
  }

  void _open(QingyueDestination d) {
    switch (d) {
      case QingyueDestination.favorites:
        widget.openLibrary(4);
      case QingyueDestination.history:
        widget.openLibrary(5);
      case QingyueDestination.downloads:
        widget.openDownloads();
      case QingyueDestination.account:
        _account();
      default:
        context.pushNamed(switch (d) {
          QingyueDestination.theme => '/settings/theme',
          QingyueDestination.player => '/settings/player',
          QingyueDestination.danmaku => '/settings/danmaku/',
          QingyueDestination.storage => '/settings/storage',
          _ => '/settings/about',
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = external
        ? externalProfile ?? const <String, dynamic>{}
        : api.user;
    final id = '${user['id'] ?? user['user_id'] ?? ''}';
    final localAvatar = external && signedIn
        ? avatars.sourcePath(widget.source.name, id)
        : null;
    final header = CatalogProfileHeader(
      name: signedIn ? catalogAccountName(user) : '登录',
      id: signedIn ? id : '',
      onTap: _account,
      avatar: external
          ? SiteAvatar(path: localAvatar, url: '${user['avatar_url'] ?? ''}')
          : CycaniAvatar(api: api, store: avatars, size: 72),
    );
    Widget pane(WatchStats local) => FutureBuilder<CycaniAccountStats>(
      key: ValueKey(api.sessionEpoch),
      future: totals,
      builder: (context, snapshot) => RefreshIndicator(
        onRefresh: _refresh,
        child: QingyueSpaceView(
          stats: external ? const WatchStats() : local,
          profileHeader: header,
          onOpen: _open,
          cloudWatched: (snapshot.data ?? _last[_statsKey])?.watchedVideos,
          cloudFavorites: (snapshot.data ?? _last[_statsKey])?.favorites,
        ),
      ),
    );
    if (stats == null) return pane(const WatchStats());
    return Observer(builder: (_) => pane(stats!.watchStats));
  }
}
