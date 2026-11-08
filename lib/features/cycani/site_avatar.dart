import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cyanmoon_acg/services/network/proxy_aware_image_cache_manager.dart';

class SiteAvatar extends StatefulWidget {
  const SiteAvatar({super.key, this.path, this.url = '', this.size = 72});
  final String? path;
  final String url;
  final double size;
  @override
  State<SiteAvatar> createState() => _SiteAvatarState();
}

class _SiteAvatarState extends State<SiteAvatar> {
  // 文件修改时间异步探测（不在 build 里做同步磁盘 IO）；
  // 作为 Image key 用于同路径内容变化时刷新图片缓存。
  String _fileKey = '';

  @override
  void initState() {
    super.initState();
    _refreshFileKey();
  }

  @override
  void didUpdateWidget(covariant SiteAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _refreshFileKey();
  }

  Future<void> _refreshFileKey() async {
    final path = widget.path;
    if (path == null) return;
    String key = '';
    try {
      final file = File(path);
      if (await file.exists()) {
        key = (await file.lastModified()).toIso8601String();
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _fileKey = key);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    Widget placeholder() => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.person_outline_rounded, size: size / 2),
    );
    Widget remote() => Uri.tryParse(widget.url)?.scheme == 'https'
        ? CachedNetworkImage(
            imageUrl: widget.url,
            cacheManager: ProxyAwareImageCacheManager.privateImages,
            fit: BoxFit.cover,
            memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                .ceil(),
            placeholder: (_, _) => placeholder(),
            errorWidget: (_, _, _) => placeholder(),
          )
        : placeholder();
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: widget.path == null
            ? remote()
            : Image.file(
                File(widget.path!),
                fit: BoxFit.cover,
                cacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
                key: ValueKey('${widget.path}-$_fileKey'),
                errorBuilder: (_, _, _) => remote(),
              ),
      ),
    );
  }
}

class SiteAvatarPicker extends StatefulWidget {
  const SiteAvatarPicker({
    super.key,
    required this.child,
    required this.choose,
    required this.reset,
    this.enabled = true,
  });
  final Widget child;
  final Future<void> Function() choose, reset;
  final bool enabled;
  @override
  State<SiteAvatarPicker> createState() => _SiteAvatarPickerState();
}

class _SiteAvatarPickerState extends State<SiteAvatarPicker> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => PopupMenuButton<bool>(
    enabled: widget.enabled && !_busy,
    itemBuilder: (_) => const [
      PopupMenuItem(value: true, child: Text('从本机选择')),
      PopupMenuItem(value: false, child: Text('恢复账号头像')),
    ],
    onSelected: (pick) async {
      if (_busy) return;
      setState(() => _busy = true);
      try {
        await (pick ? widget.choose() : widget.reset());
      } catch (_) {
        if (context.mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('头像保存失败')));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    },
    child: widget.child,
  );
}
