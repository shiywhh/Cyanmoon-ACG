import 'package:flutter/material.dart';
import 'cycani_api.dart';
import 'cycani_catalog_sources.dart';
import 'cycani_comments.dart';
import 'cycani_danmaku_dialog.dart';
import 'cycani_models.dart';
import 'cycani_native_catalog.dart';
import 'cycani_source_accounts.dart';
import 'cycani_source_comments.dart';

class CatalogDiscussionTarget {
  const CatalogDiscussionTarget({
    required this.source,
    required this.videoId,
    this.sectionId,
    this.episodeId,
    this.playUrl,
  });
  final CatalogSource source;
  final int videoId;
  final int? sectionId, episodeId;
  final String? playUrl;

  static CatalogDiscussionTarget? fromPlayback({
    required String pluginName,
    required int itemId,
    required String pageUrl,
  }) {
    final entry = SiteEntry.fromLegacy(itemId);
    if (entry == null || entry.source.label != pluginName) return null;
    switch (entry.source) {
      case CatalogSource.cycani:
        final section = cycaniSectionId(pageUrl);
        return section == null
            ? null
            : CatalogDiscussionTarget(
                source: entry.source,
                videoId: entry.rawId,
                sectionId: section,
              );
      case CatalogSource.xifan:
        final episode = NativeCatalogApi.xifanEpisode(pageUrl);
        return episode == null || episode.$1 != entry.rawId
            ? null
            : CatalogDiscussionTarget(
                source: entry.source,
                videoId: entry.rawId,
                episodeId: episode.$2,
              );
      case CatalogSource.giri:
        return NativeCatalogApi.giriMedia(pageUrl) == null
            ? null
            : CatalogDiscussionTarget(
                source: entry.source,
                videoId: entry.rawId,
                playUrl: pageUrl,
              );
    }
  }

  Future<void> send(
    String content,
    double time, {
    required String mode,
    required int color,
  }) => switch (source) {
    CatalogSource.cycani => CycaniApi.instance.postDanmaku(
      sectionId!,
      content,
      time,
      mode: mode,
      color: color,
    ),
    CatalogSource.xifan => SourceAccounts.instance.postXifanDanmaku(
      episodeId!,
      content,
      time,
      mode: mode,
      color: color,
    ),
    CatalogSource.giri => SourceAccounts.instance.postGiriDanmaku(
      playUrl!,
      content,
      time,
      mode: mode,
      color: color,
    ),
  };
}

class CatalogPlaybackDiscussion extends StatelessWidget {
  const CatalogPlaybackDiscussion({
    super.key,
    required this.target,
    required this.position,
    required this.onSent,
  });
  final CatalogDiscussionTarget target;
  final double Function() position;
  final VoidCallback onSent;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        FilledButton.tonalIcon(
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text('发送${target.source.label}弹幕'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => CycaniDanmakuDialog(
              sourceName: target.source.label,
              position: position,
              send: target.send,
              onSent: onSent,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (target.source == CatalogSource.cycani)
          CycaniComments(key: ValueKey(target.videoId), videoId: target.videoId)
        else
          SourceComments(
            key: ValueKey((target.source, target.videoId)),
            giri: target.source == CatalogSource.giri,
            videoId: target.videoId,
          ),
      ],
    ),
  );
}
