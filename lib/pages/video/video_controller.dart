import 'package:cyanmoon_acg/features/cycani/catalog_playback_discussion.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_playback_danmaku.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_aggregator.dart';
import 'package:cyanmoon_acg/features/cycani/site_accounts.dart';
import 'package:cyanmoon_acg/modules/danmaku/danmaku_ch_convert.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_danmaku_options.dart';
import 'package:cyanmoon_acg/features/cycani/cycani_api.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_models.dart';
import 'package:cyanmoon_acg/pages/player/controller/player_danmaku_controller.dart';
import 'dart:async';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cyanmoon_acg/modules/roads/road_module.dart';
import 'package:cyanmoon_acg/pages/video/video_playback_args.dart';
import 'package:cyanmoon_acg/plugins/plugins.dart';
import 'package:cyanmoon_acg/pages/history/history_controller.dart';
import 'package:cyanmoon_acg/pages/player/player_controller.dart';
import 'package:cyanmoon_acg/modules/bangumi/bangumi_item.dart';
import 'package:cyanmoon_acg/modules/download/download_module.dart';
import 'package:cyanmoon_acg/modules/history/history_module.dart';
import 'package:cyanmoon_acg/repositories/download_repository.dart';
import 'package:cyanmoon_acg/services/download/download_manager.dart';
import 'package:cyanmoon_acg/services/video_source/services.dart';
import 'package:cyanmoon_acg/bean/dialog/dialog_helper.dart';
import 'package:mobx/mobx.dart';
import 'package:cyanmoon_acg/services/logging/logger.dart';
import 'package:cyanmoon_acg/modules/bangumi/episode_item.dart';
import 'package:cyanmoon_acg/modules/comments/comment_item.dart';
import 'package:cyanmoon_acg/modules/comments/comment_response.dart';
import 'package:cyanmoon_acg/request/apis/bangumi_api.dart';
import 'package:cyanmoon_acg/services/storage/storage.dart';
import 'package:cyanmoon_acg/utils/episode_url.dart';
import 'package:cyanmoon_acg/utils/http_headers.dart';
import 'package:cyanmoon_acg/utils/media.dart';
import 'package:cyanmoon_acg/utils/async_session.dart';
import 'package:cyanmoon_acg/services/platform/display_mode_service.dart';
import 'package:cyanmoon_acg/pages/video/video_fullscreen_controller.dart';

part 'video_controller.g.dart';

class VideoPageController = _VideoPageController with _$VideoPageController;

class VideoEpisodeSelection {
  const VideoEpisodeSelection({required this.episode, required this.road});

  final int episode;
  final int road;

  @override
  bool operator ==(Object other) {
    return other is VideoEpisodeSelection &&
        other.episode == episode &&
        other.road == road;
  }

  @override
  int get hashCode => Object.hash(episode, road);

  @override
  String toString() {
    return 'VideoEpisodeSelection(episode: $episode, road: $road)';
  }
}

abstract class _VideoPageController with Store implements Disposable {
  _VideoPageController(
    this.historyController,
    this.downloadRepository,
    this.downloadManager,
  );

  late BangumiItem bangumiItem;
  EpisodeInfo episodeInfo = EpisodeInfo.fromTemplate();

  @observable
  var episodeCommentsList = ObservableList<EpisodeCommentItem>();

  // Resolution state machine: [_beginEpisodeSwitch] enters the loading state;
  // [_finishLoading] and [_failLoading] are the only terminal transitions.
  // [_errorMessage] is non-null only in the failed state.
  @readonly
  bool _loading = true;

  @readonly
  String? _errorMessage;

  @observable
  VideoEpisodeSelection selectedEpisode = const VideoEpisodeSelection(
    episode: 1,
    road: 0,
  );

  @observable
  VideoEpisodeSelection? playingEpisode;

  @observable
  int commentsEpisode = 1;

  @action
  void resetEpisodeState({int episode = 1, int road = 0}) {
    final selection = VideoEpisodeSelection(episode: episode, road: road);
    selectedEpisode = selection;
    playingEpisode = null;
    commentsEpisode = commentEpisodeForSelection(selection);
  }

  VideoEpisodeSelection get playbackEpisode =>
      playingEpisode ?? selectedEpisode;

  final fullscreen = VideoFullscreenController(
    applyFullscreen: DisplayModeService.applyVideoFullscreen,
  );

  bool get isFullscreen => fullscreen.isFullscreen;

  @observable
  bool isCommentsAscending = false;

  // Playback, automatic danmaku loading, and comment loading have separate
  // owners. Manual danmaku selection can cancel auto danmaku without touching
  // playback; comment refreshes never cancel playback.
  final AsyncSessionOwner _playbackSessions = AsyncSessionOwner();
  final AsyncSessionOwner _danmakuSessions = AsyncSessionOwner();
  final AsyncSessionOwner _commentSessions = AsyncSessionOwner();

  @observable
  bool isPip = false;

  @observable
  int historyOffset = 0;

  @observable
  bool isOfflineMode = false;

  PlaybackHistoryIdentity? _playbackHistoryIdentity;
  final Map<int, DownloadEpisode> _offlineEpisodesByNumber = {};
  final Map<int, int> _offlineDisplayRoadToOriginalRoad = {};
  final Map<int, int> _offlineOriginalRoadToDisplayRoad = {};

  /// Title reported by the video source; may differ from [bangumiItem]'s.
  String title = '';

  String src = '';

  @observable
  var roadList = ObservableList<Road>();

  late Plugin currentPlugin;

  String _offlinePluginName = '';

  final HistoryController historyController;
  final IDownloadRepository downloadRepository;
  final IDownloadManager downloadManager;

  WebViewVideoSourceService? _videoSourceService;
  Timer? _cycaniHistoryTimer;
  PlayerController? _cycaniPlayer;
  int? _cycaniSection;
  Map<String, int> _catalogVideoIds = const {};
  int _catalogBangumiId = 0;
  bool _xifanProgress = false;
  int? _giriProgressVideo;
  int _giriProgressEpisode = 1;
  CatalogDiscussionTarget? get discussionTarget {
    if (isOfflineMode) return null;
    final ref = resolveEpisode(playbackEpisode);
    return ref == null
        ? null
        : CatalogDiscussionTarget.fromPlayback(
            pluginName: currentPlugin.name,
            itemId: bangumiItem.id,
            pageUrl: ref.pageUrl,
          );
  }

  bool _cycaniReporting = false;
  PlaybackInitParams? _activeDanmakuParams;
  AsyncSession? _activeDanmakuPlaybackSession;

  Future<void> _reportCycaniHistory() async {
    final player = _cycaniPlayer;
    final section = _cycaniSection;
    if (_cycaniReporting ||
        player == null ||
        section == null ||
        (!_xifanProgress &&
            _giriProgressVideo == null &&
            !CycaniApi.instance.loggedIn))
      return;
    final duration = player.playback.duration.inMilliseconds / 1000;
    final progress = player.playback.currentPosition.inMilliseconds / 1000;
    if (duration <= 0 || progress <= 0) return;
    _cycaniReporting = true;
    try {
      if (_giriProgressVideo != null) {
        await SourceAccounts.instance.recordGiriProgress(
          _giriProgressVideo!,
          _giriProgressEpisode,
          progress,
        );
      } else if (_xifanProgress) {
        await SourceAccounts.instance.recordXifanProgress(
          section,
          (progress * 1000).round(),
          (duration * 1000).round(),
        );
      } else {
        await CycaniApi.instance.reportHistory(section, progress, duration);
      }
    } catch (_) {
      /* Best-effort sync; original local history still persists. */
    } finally {
      _cycaniReporting = false;
    }
  }

  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();

  Stream<String> get logStream => _logStreamController.stream;

  StreamSubscription<String>? _logSubscription;

  /// Applies the route arguments exactly once, from [VideoPage.initState].
  @action
  void applyPlaybackArgs(VideoPlaybackArgs args) {
    switch (args) {
      case OnlineVideoPlaybackArgs():
        bangumiItem = args.bangumiItem;
        _catalogVideoIds = Map.unmodifiable(args.catalogVideoIds);
        _catalogBangumiId = args.catalogBangumiId;
        currentPlugin = args.plugin;
        title = args.title;
        src = args.src;
        roadList.clear();
        roadList.addAll(args.roads);
      case OfflineVideoPlaybackArgs():
        _initForOfflinePlayback(
          bangumiItem: args.bangumiItem,
          pluginName: args.pluginName,
          episodeNumber: args.episodeNumber,
          road: args.road,
          downloadedEpisodes: args.downloadedEpisodes,
        );
    }
  }

  @action
  void _initForOfflinePlayback({
    required BangumiItem bangumiItem,
    required String pluginName,
    required int episodeNumber,
    required int road,
    required List<DownloadEpisode> downloadedEpisodes,
  }) {
    this.bangumiItem = bangumiItem;
    _offlinePluginName = pluginName;
    title = bangumiItem.nameCn.isNotEmpty
        ? bangumiItem.nameCn
        : bangumiItem.name;
    isOfflineMode = true;
    _loading = false;

    _buildOfflineRoadList(downloadedEpisodes);

    final target = _findOfflineEpisodeByNumber(
      episodeNumber,
      preferredOriginalRoad: road,
    );
    final selected = VideoEpisodeSelection(
      episode: target?.listIndex ?? 1,
      road: target?.roadIndex ?? 0,
    );
    selectedEpisode = selected;
    playingEpisode = null;
    commentsEpisode = commentEpisodeForSelection(selected);
    final resolvedEpisode = _resolveOfflineEpisode(
      selected.episode,
      road: selected.road,
    );
    if (resolvedEpisode != null) {
      _setOfflineHistoryIdentity(resolvedEpisode);
    } else {
      _playbackHistoryIdentity = null;
    }
    CyanmoonLogger().i(
      'VideoPageController: initialized for offline playback, episode $episodeNumber (position: ${selected.episode})',
    );
  }

  void _buildOfflineRoadList(List<DownloadEpisode> episodes) {
    final snapshot = buildOfflineRoadListSnapshot(episodes);
    roadList.clear();
    roadList.addAll(snapshot.roads);
    _offlineEpisodesByNumber.clear();
    _offlineEpisodesByNumber.addAll(snapshot.episodesByNumber);
    _offlineDisplayRoadToOriginalRoad.clear();
    _offlineDisplayRoadToOriginalRoad.addAll(
      snapshot.displayRoadToOriginalRoad,
    );
    _offlineOriginalRoadToDisplayRoad.clear();
    _offlineOriginalRoadToDisplayRoad.addAll(
      snapshot.originalRoadToDisplayRoad,
    );
  }

  String get offlinePluginName => _offlinePluginName;

  PlaybackHistoryIdentity? get currentHistoryIdentity =>
      _playbackHistoryIdentity;

  ({int listIndex, int roadIndex})? _findOfflineEpisodeByNumber(
    int episodeNumber, {
    required int preferredOriginalRoad,
  }) {
    if (episodeNumber <= 0 || roadList.isEmpty) {
      return null;
    }
    final preferredDisplayRoad =
        _offlineOriginalRoadToDisplayRoad[preferredOriginalRoad];
    final roadIndices = <int>[
      if (preferredDisplayRoad != null) preferredDisplayRoad,
      for (var i = 0; i < roadList.length; i++)
        if (i != preferredDisplayRoad) i,
    ];
    for (final roadIndex in roadIndices) {
      final match = _findOfflineEpisodeInDisplayRoad(episodeNumber, roadIndex);
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  ({int listIndex, int roadIndex})? _findOfflineEpisodeInDisplayRoad(
    int episodeNumber,
    int roadIndex,
  ) {
    if (roadIndex < 0 || roadIndex >= roadList.length) {
      return null;
    }
    final index = roadList[roadIndex].data.indexOf(episodeNumber.toString());
    if (index < 0) {
      return null;
    }
    return (listIndex: index + 1, roadIndex: roadIndex);
  }

  int getHistoryOffsetFor(PlaybackHistoryIdentity identity) {
    final playResume = GStorage.getSetting(SettingsKeys.playResume);
    if (playResume != true) {
      return 0;
    }
    return historyController
            .findProgress(
              identity.bangumiItem,
              identity.pluginName,
              identity.episodeNumber,
              entryKind: identity.entryKind,
            )
            ?.progress
            .inSeconds ??
        0;
  }

  void _setOnlineHistoryIdentity(EpisodeRef episode) {
    _playbackHistoryIdentity = PlaybackHistoryIdentity.online(
      bangumiItem: bangumiItem,
      pluginName: currentPlugin.name,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      onlineBangumiSrc: src,
      episodePageUrl: episode.pageUrl,
    );
  }

  void _setOfflineHistoryIdentity(EpisodeRef episode) {
    _playbackHistoryIdentity = PlaybackHistoryIdentity.offline(
      bangumiItem: bangumiItem,
      pluginName: _offlinePluginName,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      episodePageUrl: episode.pageUrl,
    );
  }

  EpisodeRef? _resolveOnlineEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 ||
        index >= roadData.data.length ||
        index >= roadData.identifier.length) {
      return null;
    }
    final displayTitle = roadData.identifier[index];
    return EpisodeRef.online(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: displayTitle,
      pageUrl: roadData.data[index],
    );
  }

  EpisodeRef? _resolveOfflineEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 ||
        index >= roadData.data.length ||
        index >= roadData.identifier.length) {
      return null;
    }
    final episodeNumber = int.tryParse(roadData.data[index]);
    if (episodeNumber == null) {
      return null;
    }
    final downloadEpisode = _offlineEpisodesByNumber[episodeNumber];
    final titleFromRoad = roadData.identifier[index];
    final episodeTitle = downloadEpisode?.episodeName.isNotEmpty == true
        ? downloadEpisode!.episodeName
        : (titleFromRoad.isNotEmpty ? titleFromRoad : '第$episodeNumber集');
    return EpisodeRef.offline(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: episodeTitle,
      pageUrl: downloadEpisode?.episodePageUrl ?? '',
      episodeNumber: episodeNumber,
      originalRoadIndex:
          downloadEpisode?.road ??
          _offlineDisplayRoadToOriginalRoad[targetRoad] ??
          targetRoad,
    );
  }

  EpisodeRef? resolveEpisode(VideoEpisodeSelection selection) {
    return isOfflineMode
        ? _resolveOfflineEpisode(selection.episode, road: selection.road)
        : _resolveOnlineEpisode(selection.episode, road: selection.road);
  }

  int commentEpisodeForSelection(VideoEpisodeSelection selection) {
    final resolvedEpisode = resolveEpisode(selection);
    return resolvedEpisode?.danmakuEpisodeNumber ?? selection.episode;
  }

  /// Resets pre-switch state as a single transaction so observers see one
  /// notification instead of one per field.
  @action
  void _beginEpisodeSwitch(VideoEpisodeSelection selection) {
    final targetCommentsEpisode = commentEpisodeForSelection(selection);
    selectedEpisode = selection;
    playingEpisode = null;
    // The comments sheet only re-queries when [commentsEpisode] changes, so
    // resetting comment state here without changing it would blank the sheet
    // permanently.
    if (targetCommentsEpisode != commentsEpisode) {
      commentsEpisode = targetCommentsEpisode;
      _resetEpisodeComments();
    }
    _loading = true;
    _errorMessage = null;
  }

  @action
  void _applyResolvedSelection(EpisodeRef resolvedEpisode) {
    selectedEpisode = VideoEpisodeSelection(
      episode: resolvedEpisode.listIndex,
      road: resolvedEpisode.roadIndex,
    );
    commentsEpisode = commentEpisodeForSelection(selectedEpisode);
  }

  @action
  void _finishLoading() {
    _loading = false;
  }

  @action
  void _failLoading(String message) {
    _loading = false;
    _errorMessage = message;
  }

  Future<void> changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
    required PlayerController playerController,
  }) async {
    unawaited(_reportCycaniHistory());
    _cycaniHistoryTimer?.cancel();
    _cycaniHistoryTimer = null;
    _cycaniSection = null;
    _giriProgressVideo = null;
    final session = _playbackSessions.begin();
    final selection = VideoEpisodeSelection(
      episode: episode,
      road: currentRoad,
    );
    _beginEpisodeSwitch(selection);
    _danmakuSessions.cancel();
    playerController.danmaku.finishDanmakuLoad();
    _videoSourceService?.cancel();

    await playerController.stop();
    if (session.isStale) {
      return;
    }

    if (isOfflineMode) {
      await _changeOfflineEpisode(
        selection,
        offset,
        session: session,
        playerController: playerController,
      );
      return;
    }

    final resolvedEpisode = _resolveOnlineEpisode(episode, road: currentRoad);
    if (resolvedEpisode == null) {
      CyanmoonLogger().e(
        'VideoPageController: failed to resolve online episode. road=$currentRoad, episode=$episode',
      );
      _failLoading('集数解析失败');
      return;
    }

    _applyResolvedSelection(resolvedEpisode);
    _setOnlineHistoryIdentity(resolvedEpisode);

    CyanmoonLogger().i(
      'VideoPageController: changed to ${resolvedEpisode.displayTitle}',
    );
    final urlItem = normalizeEpisodeUrl(
      currentPlugin.baseUrl,
      resolvedEpisode.pageUrl,
    );

    await _resolveWithVideoSourceService(
      urlItem,
      offset,
      resolvedEpisode: resolvedEpisode,
      session: session,
      playerController: playerController,
    );
  }

  Future<void> _changeOfflineEpisode(
    VideoEpisodeSelection selection,
    int offset, {
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    final resolvedEpisode = _resolveOfflineEpisode(
      selection.episode,
      road: selection.road,
    );
    if (resolvedEpisode == null) {
      CyanmoonLogger().e(
        'VideoPageController: failed to resolve offline episode. road=${selection.road}, episode=${selection.episode}',
      );
      _failLoading('集数解析失败');
      return;
    }

    final localPath = _getLocalVideoPath(
      bangumiItem.id,
      _offlinePluginName,
      resolvedEpisode.historyEpisodeNumber,
    );
    if (localPath == null) {
      _failLoading('该集数未下载');
      return;
    }
    _applyResolvedSelection(resolvedEpisode);
    _setOfflineHistoryIdentity(resolvedEpisode);
    if (session.isStale) {
      return;
    }
    _finishLoading();
    final resolvedOffset = offset > 0
        ? offset
        : getHistoryOffsetFor(_playbackHistoryIdentity!);

    CyanmoonLogger().i(
      'VideoPageController: offline episode changed to ${resolvedEpisode.historyEpisodeNumber} (index: ${selection.episode}), path: $localPath',
    );

    final params = PlaybackInitParams(
      videoUrl: localPath,
      offset: resolvedOffset,
      isLocalPlayback: true,
      bangumiId: bangumiItem.id,
      pluginName: _offlinePluginName,
      episode: resolvedEpisode.listIndex,
      danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
      pageUrl: resolvedEpisode.pageUrl,
      sortNumber: resolvedEpisode.sortNumber,
      httpHeaders: {},
      adBlockerEnabled: false,
      episodeTitle: resolvedEpisode.displayTitle,
      referer: '',
      currentRoad: resolvedEpisode.roadIndex,
      coverUrl: bangumiItem.images['large'],
      bangumiName: bangumiItem.nameCn.isNotEmpty
          ? bangumiItem.nameCn
          : bangumiItem.name,
    );

    final initialized = await playerController.init(params);
    if (session.isActive && initialized) {
      playingEpisode = selection;
      unawaited(_loadPlaybackDanmaku(playerController, params, session));
    } else if (session.isActive) {
      _playbackSessions.cancel();
    }
  }

  Future<DanmakuLoadResult> _fetchPlaybackDanmaku(
    PlayerController player,
    PlaybackInitParams params, {
    bool refresh = false,
  }) async {
    final source = CatalogSource.values
        .where((s) => s.label == params.pluginName)
        .firstOrNull;
    if (source == null) {
      return player.danmaku.fetchDanmaku(
        params.bangumiId,
        params.pluginName,
        params.danmakuEpisodeNumber,
      );
    }
    final options = CatalogDanmakuOptions.read();
    final ids = <String, int>{..._catalogVideoIds};
    final identity = SiteEntry.fromLegacy(params.bangumiId);
    if (identity?.source == source)
      ids.putIfAbsent(source.name, () => identity!.rawId);
    final result =
        await CatalogPlaybackDanmaku(
          source: source,
          pageUrl: params.pageUrl,
          episodeTitle: params.episodeTitle,
          videoIds: ids,
          bangumiId: _catalogBangumiId,
        ).load(
          options: options,
          cache: !params.isLocalPlayback,
          refresh: refresh,
          chConvert: DanmakuChConvert.fromValue(
            GStorage.getSetting(SettingsKeys.danmakuChConvert),
          ).value,
          loadCached: params.isLocalPlayback
              ? () => player.danmaku.downloadController.getCachedDanmakus(
                  params.bangumiId,
                  params.pluginName,
                  params.episode,
                )
              : null,
        );
    if (result.hasDanmakus &&
        result.allSourcesLoaded &&
        options.external &&
        options.xifan &&
        options.cycani &&
        options.giri &&
        options.giriExternal) {
      unawaited(
        player.danmaku.downloadController.updateCachedDanmakus(
          params.bangumiId,
          params.pluginName,
          params.episode,
          result.danmakus,
          result.bangumiID,
        ),
      );
    }
    return result;
  }

  void reloadDanmakuSources(PlayerController player) {
    final params = _activeDanmakuParams;
    final session = _activeDanmakuPlaybackSession;
    if (params == null || session == null || session.isStale) return;
    player.danmaku.clearAndInvalidateScheduledDanmakus();
    unawaited(_loadPlaybackDanmaku(player, params, session, refresh: true));
  }

  Future<void> _loadPlaybackDanmaku(
    PlayerController playerController,
    PlaybackInitParams params,
    AsyncSession session, {
    bool refresh = false,
  }) async {
    _activeDanmakuParams = params;
    _activeDanmakuPlaybackSession = session;
    final danmakuSession = _danmakuSessions.begin();
    playerController.danmaku.beginDanmakuLoad();
    try {
      final result = await _fetchPlaybackDanmaku(
        playerController,
        params,
        refresh: refresh,
      );
      if (session.isActive && danmakuSession.isActive) {
        if (result.hasDanmakus) {
          final bool enableDanmaku = GStorage.getSetting(
            SettingsKeys.danmakuEnabledByDefault,
          );
          playerController.danmaku.applyDanmakuLoad(
            result,
            enableDanmaku: enableDanmaku,
          );
        } else {
          playerController.danmaku.applyUnavailableDanmakuLoad(result);
          if (result.isFailed) {
            CyanmoonDialog.showToast(message: '弹幕加载失败，可手动检索');
          }
        }
      }
    } catch (e) {
      if (session.isActive && danmakuSession.isActive) {
        playerController.danmaku.finishDanmakuLoad(disableDanmaku: true);
        CyanmoonDialog.showToast(message: '弹幕加载失败，可手动检索');
      }
      CyanmoonLogger().w('VideoPageController: failed to load danmaku', error: e);
    }
  }

  void cancelAutomaticDanmakuLoad() {
    _danmakuSessions.cancel();
  }

  String? _getLocalVideoPath(
    int bangumiId,
    String pluginName,
    int episodeNumber,
  ) {
    final episode = downloadRepository.getEpisode(
      bangumiId,
      pluginName,
      episodeNumber,
    );
    return downloadManager.getLocalVideoPath(episode);
  }

  Future<void> _resolveWithVideoSourceService(
    String url,
    int offset, {
    required EpisodeRef resolvedEpisode,
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    _videoSourceService ??= WebViewVideoSourceService();

    await _logSubscription?.cancel();
    _logSubscription = _videoSourceService!.onLog.listen((log) {
      if (!_logStreamController.isClosed) {
        _logStreamController.add(log);
      }
    });

    try {
      final source = await _videoSourceService!.resolve(
        url,
        useLegacyParser: currentPlugin.useLegacyParser,
        offset: offset,
      );

      if (session.isStale) {
        return;
      }
      _finishLoading();
      CyanmoonLogger().i(
        currentPlugin.name == CycaniApi.pluginName
            ? '次元城播放地址已取得'
            : 'VideoPageController: video URL resolved',
      );

      final bool forceAdBlocker = GStorage.getSetting(
        SettingsKeys.forceAdBlocker,
      );

      var resumeOffset = source.offset;
      final identity = SiteEntry.fromLegacy(bangumiItem.id);
      if (identity?.source == CatalogSource.giri &&
          GStorage.getSetting<bool>(SettingsKeys.playResume)) {
        try {
          final seconds = await SourceAccounts.instance
              .giriProgress(identity!.rawId, resolvedEpisode.listIndex)
              .timeout(const Duration(seconds: 5));
          if (seconds > 0 && resumeOffset <= 0) resumeOffset = seconds.floor();
        } catch (_) {
          /* Keep local resume on network failure. */
        }
        if (session.isStale) return;
      }
      final params = PlaybackInitParams(
        videoUrl: source.url,
        offset: resumeOffset,
        isLocalPlayback: false,
        videoSourceFormat: source.format,
        bangumiId: bangumiItem.id,
        pluginName: currentPlugin.name,
        episode: resolvedEpisode.listIndex,
        danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
        pageUrl: resolvedEpisode.pageUrl,
        sortNumber: resolvedEpisode.sortNumber,
        httpHeaders: {
          'user-agent': currentPlugin.userAgent.isEmpty
              ? getRandomUA()
              : currentPlugin.userAgent,
          if (currentPlugin.referer.isNotEmpty)
            'referer': currentPlugin.referer,
        },
        adBlockerEnabled: forceAdBlocker || currentPlugin.adBlocker,
        episodeTitle: resolvedEpisode.displayTitle,
        referer: currentPlugin.referer,
        currentRoad: resolvedEpisode.roadIndex,
        coverUrl: bangumiItem.images['large'],
        bangumiName: bangumiItem.nameCn.isNotEmpty
            ? bangumiItem.nameCn
            : bangumiItem.name,
      );

      final initialized = await playerController.init(params);
      if (session.isActive && initialized) {
        playingEpisode = VideoEpisodeSelection(
          episode: resolvedEpisode.listIndex,
          road: resolvedEpisode.roadIndex,
        );
        final url = Uri.tryParse(resolvedEpisode.pageUrl);
        final segments = url?.pathSegments ?? const <String>[];
        _xifanProgress =
            url?.host == 'next.xifanacg.com' &&
            segments.length == 4 &&
            segments[0] == 'anime' &&
            segments[2] == 'play';
        _giriProgressVideo = identity?.source == CatalogSource.giri
            ? identity!.rawId
            : null;
        _giriProgressEpisode = resolvedEpisode.listIndex;
        if (currentPlugin.name == CycaniApi.pluginName ||
            _xifanProgress ||
            _giriProgressVideo != null) {
          _cycaniSection = _xifanProgress
              ? int.tryParse(segments.last)
              : _giriProgressVideo ?? cycaniSectionId(resolvedEpisode.pageUrl);
          _cycaniPlayer = playerController;
          _cycaniHistoryTimer?.cancel();
          _cycaniHistoryTimer = Timer.periodic(
            const Duration(seconds: 15),
            (_) => unawaited(_reportCycaniHistory()),
          );
        }
        unawaited(_loadPlaybackDanmaku(playerController, params, session));
      } else if (session.isActive) {
        _playbackSessions.cancel();
      }
    } on VideoSourceTimeoutException {
      if (session.isStale) {
        return;
      }
      _failLoading('视频解析超时，请重试');
    } on VideoSourceCancelledException {
      CyanmoonLogger().i('VideoPageController: video URL resolution cancelled');
    } catch (e) {
      if (session.isStale) {
        return;
      }
      _failLoading('视频解析失败：${e.toString()}');
    }
  }

  void _resetEpisodeComments() {
    _commentSessions.cancel();
    episodeInfo.reset();
    episodeCommentsList.clear();
  }

  Future<bool> queryBangumiEpisodeCommentsByID(int id, int episode) async {
    final session = _commentSessions.begin();
    final EpisodeInfo latestEpisodeInfo;
    try {
      latestEpisodeInfo = await BangumiApi.getBangumiEpisodeByID(id, episode);
    } catch (_) {
      if (session.isStale) {
        return false;
      }
      rethrow;
    }
    if (session.isStale) {
      return false;
    }
    final EpisodeCommentResponse value;
    try {
      value = await BangumiApi.getBangumiCommentsByEpisodeID(
        latestEpisodeInfo.id,
      );
    } catch (_) {
      if (session.isStale) {
        return false;
      }
      rethrow;
    }
    if (session.isStale) {
      return false;
    }
    final commentsList = value.commentList;
    if (!isCommentsAscending) {
      commentsList.sort(
        (a, b) => b.comment.createdAt.compareTo(a.comment.createdAt),
      );
    } else {
      commentsList.sort(
        (a, b) => a.comment.createdAt.compareTo(b.comment.createdAt),
      );
    }
    _applyEpisodeComments(episode, latestEpisodeInfo, commentsList);
    CyanmoonLogger().i(
      'VideoPageController: loaded comments list length ${episodeCommentsList.length}',
    );
    return true;
  }

  @action
  void _applyEpisodeComments(
    int episode,
    EpisodeInfo info,
    List<EpisodeCommentItem> comments,
  ) {
    commentsEpisode = episode;
    episodeInfo = info;
    episodeCommentsList = ObservableList.of(comments);
  }

  @action
  void toggleSortOrder() {
    isCommentsAscending = !isCommentsAscending;
    episodeCommentsList.sort(
      (a, b) => isCommentsAscending
          ? a.comment.createdAt.compareTo(b.comment.createdAt)
          : b.comment.createdAt.compareTo(a.comment.createdAt),
    );
  }

  /// Called by Modular when the '/video' route scope is disposed.
  @override
  void dispose() {
    _cycaniHistoryTimer?.cancel();
    unawaited(_reportCycaniHistory());
    _cycaniHistoryTimer = null;
    unawaited(fullscreen.close());
    _playbackSessions.cancel();
    _danmakuSessions.cancel();
    _commentSessions.cancel();
    _logSubscription?.cancel();
    _logSubscription = null;
    if (!_logStreamController.isClosed) {
      _logStreamController.close();
    }
    final videoSourceService = _videoSourceService;
    _videoSourceService = null;
    if (videoSourceService != null) {
      unawaited(videoSourceService.dispose());
    }
  }
}

class OfflineRoadListSnapshot {
  const OfflineRoadListSnapshot({
    required this.roads,
    required this.episodesByNumber,
    required this.displayRoadToOriginalRoad,
    required this.originalRoadToDisplayRoad,
  });

  final List<Road> roads;
  final Map<int, DownloadEpisode> episodesByNumber;
  final Map<int, int> displayRoadToOriginalRoad;
  final Map<int, int> originalRoadToDisplayRoad;
}

OfflineRoadListSnapshot buildOfflineRoadListSnapshot(
  List<DownloadEpisode> episodes,
) {
  final groupedEpisodes = <int, List<DownloadEpisode>>{};
  final episodesByNumber = <int, DownloadEpisode>{};

  for (final episode in episodes) {
    episodesByNumber[episode.episodeNumber] = episode;
    groupedEpisodes.putIfAbsent(episode.road, () => []).add(episode);
  }

  final originalRoads = groupedEpisodes.keys.toList()..sort();
  final roads = <Road>[];
  final displayRoadToOriginalRoad = <int, int>{};
  final originalRoadToDisplayRoad = <int, int>{};

  for (final originalRoad in originalRoads) {
    final roadEpisodes = groupedEpisodes[originalRoad]!
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    final displayRoad = roads.length;
    displayRoadToOriginalRoad[displayRoad] = originalRoad;
    originalRoadToDisplayRoad[originalRoad] = displayRoad;
    roads.add(
      Road(
        name: originalRoad >= 0
            ? '播放列表${originalRoad + 1}'
            : '播放列表${displayRoad + 1}',
        data: roadEpisodes.map((e) => e.episodeNumber.toString()).toList(),
        identifier: roadEpisodes
            .map(
              (e) => e.episodeName.isNotEmpty
                  ? e.episodeName
                  : '第${e.episodeNumber}集',
            )
            .toList(),
      ),
    );
  }

  return OfflineRoadListSnapshot(
    roads: roads,
    episodesByNumber: episodesByNumber,
    displayRoadToOriginalRoad: displayRoadToOriginalRoad,
    originalRoadToDisplayRoad: originalRoadToDisplayRoad,
  );
}

class EpisodeRef {
  const EpisodeRef({
    required this.listIndex,
    required this.roadIndex,
    required this.displayTitle,
    required this.pageUrl,
    required this.sortNumber,
    required this.historyEpisodeNumber,
    required this.danmakuEpisodeNumber,
    required this.originalRoadIndex,
  });

  final int listIndex;
  final int roadIndex;
  final String displayTitle;
  final String pageUrl;

  /// Episode sort number.
  /// - Online: parsed from [displayTitle] via [extractEpisodeNumber];
  ///   null when unparsable.
  /// - Offline: always the download record's episodeNumber.
  final int? sortNumber;
  final int historyEpisodeNumber;
  final int danmakuEpisodeNumber;
  final int originalRoadIndex;

  factory EpisodeRef.online({
    required int listIndex,
    required int roadIndex,
    required String displayTitle,
    required String pageUrl,
  }) {
    final parsedEpisodeNumber = extractEpisodeNumber(displayTitle);
    return EpisodeRef(
      listIndex: listIndex,
      roadIndex: roadIndex,
      displayTitle: displayTitle,
      pageUrl: pageUrl,
      sortNumber: parsedEpisodeNumber > 0 ? parsedEpisodeNumber : null,
      historyEpisodeNumber: listIndex,
      danmakuEpisodeNumber: parsedEpisodeNumber > 0
          ? parsedEpisodeNumber
          : listIndex,
      originalRoadIndex: roadIndex,
    );
  }

  const factory EpisodeRef.offline({
    required int listIndex,
    required int roadIndex,
    required String displayTitle,
    required String pageUrl,
    required int episodeNumber,
    required int originalRoadIndex,
  }) = _OfflineEpisodeRef;
}

class _OfflineEpisodeRef extends EpisodeRef {
  const _OfflineEpisodeRef({
    required super.listIndex,
    required super.roadIndex,
    required super.displayTitle,
    required super.pageUrl,
    required int episodeNumber,
    required super.originalRoadIndex,
  }) : super(
         sortNumber: episodeNumber,
         historyEpisodeNumber: episodeNumber,
         danmakuEpisodeNumber: episodeNumber,
       );
}
