import 'package:flutter/material.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/bean/widget/content_section.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/modules/my/watch_stats.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

enum CycaniDestination {
  theme,
  player,
  danmaku,
  favorites,
  history,
  downloads,
  account,
  storage,
  about,
}

const _tileRadius = BorderRadius.all(Radius.circular(28));

class CycaniSpaceView extends StatelessWidget {
  const CycaniSpaceView({
    super.key,
    required this.stats,
    required this.onOpen,
    required this.profileHeader,
    this.cloudWatched,
    this.cloudFavorites,
  });

  final int? cloudWatched, cloudFavorites;
  final Widget profileHeader;
  final WatchStats stats;
  final ValueChanged<CycaniDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth < 600 ? 16.0 : 32.0;
        final width = constraints.maxWidth - inset * 2;
        final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
        final wide = width >= 840 && !largeText;
        return SingleChildScrollView(
          key: const PageStorageKey('my-space'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(inset, 12, inset, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: wide
                  ? _WideSpaceLayout(
                      stats: stats,
                      onOpen: onOpen,
                      profileHeader: profileHeader,
                      cloudWatched: cloudWatched,
                      cloudFavorites: cloudFavorites,
                    )
                  : _CompactSpaceLayout(
                      profileHeader: profileHeader,
                      cloudWatched: cloudWatched,
                      cloudFavorites: cloudFavorites,
                      stats: stats,
                      onOpen: onOpen,
                      stackTools: width < 280 || largeText,
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _WideSpaceLayout extends StatelessWidget {
  const _WideSpaceLayout({
    required this.stats,
    required this.onOpen,
    required this.profileHeader,
    this.cloudWatched,
    this.cloudFavorites,
  });

  final int? cloudWatched, cloudFavorites;
  final Widget profileHeader;
  final WatchStats stats;
  final ValueChanged<CycaniDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AdaptivePair(
          gap: 20,
          first: profileHeader,
          second: _WatchStatsPanel(
            bangumiCount: cloudWatched,
            episodeCount: cloudFavorites,
          ),
        ),
        const SizedBox(height: 28),
        _AdaptivePair(
          first: _RulesTile(onTap: () => onOpen(CycaniDestination.favorites)),
          second: _AdaptivePair(
            first: _ToolTile(
              icon: Icons.history_rounded,
              title: '观看历史',
              caption: '查看观看记录',
              color: colors.secondaryContainer,
              foreground: colors.onSecondaryContainer,
              onTap: () => onOpen(CycaniDestination.history),
            ),
            second: _ToolTile(
              icon: Icons.download_rounded,
              title: '下载记录',
              caption: stats.downloadTaskCount == 0
                  ? '管理离线内容'
                  : '${stats.downloadTaskCount} 集下载任务',
              color: colors.tertiaryContainer,
              foreground: colors.onTertiaryContainer,
              onTap: () => onOpen(CycaniDestination.downloads),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _AdaptivePair(
          first: _PreferencesPanel(onOpen: onOpen),
          second: _AdaptivePair(
            first: _ToolTile(
              icon: Icons.cloud_sync_rounded,
              title: '账户设置',
              caption: '',
              color: colors.surfaceContainer,
              foreground: colors.onSurface,
              onTap: () => onOpen(CycaniDestination.account),
            ),
            second: _ToolTile(
              icon: Icons.cleaning_services_rounded,
              title: '存储管理',
              caption: '缓存与日志',
              color: colors.surfaceContainer,
              foreground: colors.onSurface,
              onTap: () => onOpen(CycaniDestination.storage),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.center,
          child: _ExpressiveAction(
            color: colors.surfaceContainerLow,
            foreground: colors.onSurfaceVariant,
            onTap: () => onOpen(CycaniDestination.about),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline_rounded, size: 20),
                  SizedBox(width: 8),
                  Flexible(child: Text('关于青月次元')),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactSpaceLayout extends StatelessWidget {
  const _CompactSpaceLayout({
    required this.stats,
    required this.onOpen,
    required this.stackTools,
    required this.profileHeader,
    this.cloudWatched,
    this.cloudFavorites,
  });

  final int? cloudWatched, cloudFavorites;
  final Widget profileHeader;
  final WatchStats stats;
  final ValueChanged<CycaniDestination> onOpen;
  final bool stackTools;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        profileHeader,
        const SizedBox(height: 20),
        _WatchStatsPanel(
          bangumiCount: cloudWatched,
          episodeCount: cloudFavorites,
          compact: true,
        ),
        const SizedBox(height: 12),
        _AdaptivePair(
          stack: stackTools,
          first: _ToolTile(
            icon: Icons.history_rounded,
            title: '观看历史',
            caption: '查看观看记录',
            color: colors.secondaryContainer,
            foreground: colors.onSecondaryContainer,
            compact: true,
            onTap: () => onOpen(CycaniDestination.history),
          ),
          second: _ToolTile(
            icon: Icons.download_rounded,
            title: '下载记录',
            caption: stats.downloadTaskCount == 0
                ? '管理离线内容'
                : '${stats.downloadTaskCount} 集下载任务',
            color: colors.secondaryContainer,
            foreground: colors.onSecondaryContainer,
            compact: true,
            onTap: () => onOpen(CycaniDestination.downloads),
          ),
        ),
        const SizedBox(height: 24),
        ContentSection.group(
          title: '内容与偏好',
          children: [
            _entry('我的追番', Icons.favorite_rounded, CycaniDestination.favorites),
            _entry('外观设置', Icons.palette_rounded, CycaniDestination.theme),
            _entry('播放设置', Icons.play_circle_rounded, CycaniDestination.player),
            _entry('弹幕设置', Icons.subtitles_rounded, CycaniDestination.danmaku),
          ],
        ),
        const SizedBox(height: 24),
        ContentSection.group(
          title: '数据与应用',
          children: [
            _entry('账户设置', Icons.cloud_sync_rounded, CycaniDestination.account),
            _entry(
              '存储管理',
              Icons.cleaning_services_rounded,
              CycaniDestination.storage,
            ),
            _entry(
              '关于青月次元',
              Icons.info_outline_rounded,
              CycaniDestination.about,
            ),
          ],
        ),
      ],
    );
  }

  Widget _entry(String title, IconData icon, CycaniDestination destination) =>
      SettingsTile(
        title: Text(title),
        leading: icon,
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onPressed: (_) => onOpen(destination),
      );
}

class _WatchStatsPanel extends StatelessWidget {
  const _WatchStatsPanel({
    required this.bangumiCount,
    required this.episodeCount,
    this.compact = false,
  });

  final int? bangumiCount;
  final int? episodeCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: compact ? colors.primaryContainer : colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(compact ? 28 : 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (compact)
              Row(
                children: [
                  _ShapeIcon(
                    shape: _SpaceShape.sun,
                    icon: Icons.sentiment_satisfied_alt_rounded,
                    size: 32,
                    color: colors.primary,
                    foreground: colors.onPrimary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        '观看足迹',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                '观看统计',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatCount(
                    value: bangumiCount,
                    label: '观看番剧',
                    foreground: compact ? colors.onPrimaryContainer : null,
                  ),
                ),
                if (compact)
                  SizedBox(
                    height: 32,
                    child: VerticalDivider(
                      width: 24,
                      color: colors.onPrimaryContainer.withValues(alpha: .16),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: colors.primary,
                      size: 20,
                    ),
                  ),
                Expanded(
                  child: _StatCount(
                    value: episodeCount,
                    label: '追番数量',
                    foreground: compact ? colors.onPrimaryContainer : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCount extends StatelessWidget {
  const _StatCount({required this.value, required this.label, this.foreground});

  final int? value;
  final String label;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Scale large totals without shrinking their labels.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value?.toString() ?? '—',
            style: theme.textTheme.displaySmall?.copyWith(
              color: foreground ?? theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: foreground ?? theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _RulesTile extends StatelessWidget {
  const _RulesTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return _ExpressiveAction(
      color: colors.primary,
      foreground: colors.onPrimary,
      radius: const BorderRadius.only(
        topLeft: Radius.circular(28),
        topRight: Radius.circular(64),
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '我的追番',
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '',
                    style: text.bodyMedium?.copyWith(color: colors.onPrimary),
                  ),
                  const SizedBox(height: 20),
                  _ArrowCue(
                    color: colors.onPrimary,
                    foreground: colors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _ShapeIcon(
              shape: _SpaceShape.clover,
              icon: Icons.favorite_rounded,
              size: 80,
              color: colors.primaryContainer,
              foreground: colors.onPrimaryContainer,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.caption,
    required this.color,
    required this.foreground,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String caption;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _ExpressiveAction(
      color: color,
      foreground: foreground,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: compact ? 24 : 30),
                const Spacer(),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
            SizedBox(height: compact ? 12 : 26),
            Text(
              title,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            Text(
              caption,
              style: text.bodySmall?.copyWith(color: foreground, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferencesPanel extends StatelessWidget {
  const _PreferencesPanel({required this.onOpen});

  final ValueChanged<CycaniDestination> onOpen;

  static const _entries = [
    ('外观', Icons.palette_rounded, CycaniDestination.theme),
    ('播放', Icons.play_circle_rounded, CycaniDestination.player),
    ('弹幕', Icons.subtitles_rounded, CycaniDestination.danmaku),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: _tileRadius,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                '偏好设置',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _entries.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(child: _button(i)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(int index) {
    final (label, icon, destination) = _entries[index];
    return _PreferenceAction(
      icon: icon,
      label: label,
      first: index == 0,
      last: index == _entries.length - 1,
      onTap: () => onOpen(destination),
    );
  }
}

class _PreferenceAction extends StatelessWidget {
  const _PreferenceAction({
    required this.icon,
    required this.label,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _ExpressiveAction(
      color: colors.secondaryContainer,
      foreground: colors.onSecondaryContainer,
      radius: BorderRadius.horizontal(
        left: Radius.circular(first ? 24 : 8),
        right: Radius.circular(last ? 24 : 8),
      ),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CycaniSettingsButton extends StatelessWidget {
  const CycaniSettingsButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: '全部设置',
      child: FilledButton.tonalIcon(
        style: StateActionButton.styleOf(context).copyWith(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
          foregroundColor: WidgetStatePropertyAll(colors.onSurface),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
        onPressed: onTap,
        icon: const Icon(Icons.tune_rounded, size: 20),
        label: const Text('设置'),
      ),
    );
  }
}

class _ArrowCue extends StatelessWidget {
  const _ArrowCue({required this.color, required this.foreground});

  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 52,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(Icons.arrow_forward_rounded, color: foreground, size: 20),
    ),
  );
}

enum _SpaceShape { sun, clover }

class _ShapeIcon extends StatelessWidget {
  const _ShapeIcon({
    required this.shape,
    required this.icon,
    required this.size,
    required this.color,
    required this.foreground,
  });

  final _SpaceShape shape;
  final IconData icon;
  final double size;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipPath(
      clipper: _SpaceShapeClipper(shape),
      child: ColoredBox(
        color: color,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, color: foreground, size: size * .44),
        ),
      ),
    ),
  );
}

class _SpaceShapeClipper extends CustomClipper<Path> {
  const _SpaceShapeClipper(this.shape);

  final _SpaceShape shape;
  static final _paths = {
    _SpaceShape.sun: MaterialShapes.sunny.toPath(),
    _SpaceShape.clover: MaterialShapes.clover4Leaf.toPath(),
  };

  @override
  Path getClip(Size size) => _paths[shape]!.transform(
    Matrix4.diagonal3Values(size.width, size.height, 1).storage,
  );

  @override
  bool shouldReclip(_SpaceShapeClipper oldClipper) => oldClipper.shape != shape;
}

class _ExpressiveAction extends StatefulWidget {
  const _ExpressiveAction({
    required this.color,
    required this.foreground,
    required this.onTap,
    required this.child,
    this.radius = _tileRadius,
  });

  final Color color;
  final Color foreground;
  final VoidCallback onTap;
  final Widget child;
  final BorderRadius radius;

  @override
  State<_ExpressiveAction> createState() => _ExpressiveActionState();
}

class _ExpressiveActionState extends State<_ExpressiveAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : Duration(milliseconds: _pressed ? 150 : 300);
    return Semantics(
      button: true,
      child: AnimatedScale(
        scale: _pressed && !reducedMotion ? .97 : 1,
        duration: duration,
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: _pressed ? BorderRadius.circular(16) : widget.radius,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (value) => setState(() => _pressed = value),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return widget.foreground.withValues(alpha: .10);
                }
                if (states.contains(WidgetState.focused)) {
                  return widget.foreground.withValues(alpha: .12);
                }
                if (states.contains(WidgetState.hovered)) {
                  return widget.foreground.withValues(alpha: .08);
                }
                return null;
              }),
              child: IconTheme.merge(
                data: IconThemeData(color: widget.foreground),
                child: DefaultTextStyle.merge(
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: widget.foreground),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdaptivePair extends StatelessWidget {
  const _AdaptivePair({
    required this.first,
    required this.second,
    this.stack = false,
    this.gap = 12,
  });

  final Widget first;
  final Widget second;
  final bool stack;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          SizedBox(height: gap),
          second,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          SizedBox(width: gap),
          Expanded(child: second),
        ],
      ),
    );
  }
}
