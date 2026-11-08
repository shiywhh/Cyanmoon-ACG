import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:kazumi/services/network/proxy_aware_image_cache_manager.dart';

class SiteAvatar extends StatelessWidget {
  const SiteAvatar({super.key, this.path, this.url = '', this.size = 72});
  final String? path;
  final String url;
  final double size;
  @override
  Widget build(BuildContext context) {
    Widget placeholder() => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.person_outline_rounded, size: size / 2),
    );
    Widget remote() => Uri.tryParse(url)?.scheme == 'https'
        ? CachedNetworkImage(
            imageUrl: url,
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
        child: path == null
            ? remote()
            : Image.file(
                File(path!),
                fit: BoxFit.cover,
                key: ValueKey(
                  '$path-${File(path!).existsSync() ? File(path!).lastModifiedSync() : ''}',
                ),
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
