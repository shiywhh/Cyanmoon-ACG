import 'package:flutter/material.dart';
import 'catalog_identity.dart';
import 'cycani_api.dart';
import 'cycani_source_accounts.dart';

/// Normalized public states; each site's wire representation stays in its adapter.
enum SiteFollowState { none, watching, planned, watched }

class CatalogFollow {
  static Future<SiteFollowState> read(SiteEntry entry) async {
    if (entry.source == CatalogSource.cycani) {
      final value = await CycaniApi.instance.favoriteStatus(entry.rawId);
      if (value['favorited'] != true) return SiteFollowState.none;
      return switch (value['category']) {
        'want' => SiteFollowState.planned,
        'watched' => SiteFollowState.watched,
        _ => SiteFollowState.watching,
      };
    }
    final value = await SourceAccounts.instance.followStatus(
      entry.source == CatalogSource.giri,
      entry.rawId,
    );
    if (value == null) return SiteFollowState.none;
    return entry.source == CatalogSource.giri
        ? switch (value) {
            2 => SiteFollowState.planned,
            3 => SiteFollowState.watched,
            0 => SiteFollowState.none,
            _ => SiteFollowState.watching,
          }
        : switch (value) {
            0 => SiteFollowState.planned,
            2 => SiteFollowState.watched,
            _ => SiteFollowState.watching,
          };
  }

  static Future<void> write(SiteEntry entry, SiteFollowState state) async {
    switch (entry.source) {
      case CatalogSource.cycani:
        if (state == SiteFollowState.none) {
          await CycaniApi.instance.removeFavorites([entry.rawId]);
        } else {
          await CycaniApi.instance.favorite(entry.rawId, switch (state) {
            SiteFollowState.planned => 'want',
            SiteFollowState.watched => 'watched',
            _ => 'watching',
          });
        }
      case CatalogSource.xifan:
        await SourceAccounts.instance.setXifanFollow(
          entry.rawId,
          switch (state) {
            SiteFollowState.none => null,
            SiteFollowState.planned => 0,
            SiteFollowState.watched => 2,
            _ => 1,
          },
        );
      case CatalogSource.giri:
        await SourceAccounts.instance.setGiriFollow(entry.rawId, state.index);
    }
  }
}

class SiteFollowButton extends StatefulWidget {
  const SiteFollowButton({
    super.key,
    required this.entry,
    this.color,
    this.extended = false,
    this.onOpen,
    this.onClose,
  });
  final SiteEntry entry;
  final Color? color;
  final bool extended;
  final VoidCallback? onOpen, onClose;
  @override
  State<SiteFollowButton> createState() => _SiteFollowButtonState();
}

class _SiteFollowButtonState extends State<SiteFollowButton> {
  SiteFollowState state = SiteFollowState.none;
  bool busy = false;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SiteFollowButton old) {
    super.didUpdateWidget(old);
    if (old.entry != widget.entry) {
      state = SiteFollowState.none;
      _load();
    }
  }

  Future<void> _load() async {
    final ticket = ++revision;
    try {
      final value = await CatalogFollow.read(widget.entry);
      if (mounted && ticket == revision) setState(() => state = value);
    } catch (_) {}
  }

  String label(SiteFollowState value) => switch (value) {
    SiteFollowState.none => '取消追番',
    SiteFollowState.watching => '在看',
    SiteFollowState.planned => '想看',
    SiteFollowState.watched => '看过',
  };
  Future<void> _change(SiteFollowState value) async {
    if (busy) return;
    final entry = widget.entry;
    setState(() => busy = true);
    revision++;
    try {
      await CatalogFollow.write(entry, value);
      if (mounted && widget.entry == entry) setState(() => state = value);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError ? error.message.toString() : '追番更新失败',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<SiteFollowState>(
    enabled: !busy,
    tooltip: '追番',
    onOpened: () {
      widget.onOpen?.call();
      _load();
    },
    onCanceled: widget.onClose,
    onSelected: (value) {
      widget.onClose?.call();
      _change(value);
    },
    itemBuilder: (_) => [
      for (final value in SiteFollowState.values)
        CheckedPopupMenuItem(
          value: value,
          checked: value == state,
          child: Text(label(value)),
        ),
    ],
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            state == SiteFollowState.none
                ? Icons.favorite_border
                : Icons.favorite,
            color: widget.color,
          ),
          if (widget.extended) ...[
            const SizedBox(width: 8),
            Text(state == SiteFollowState.none ? '加入追番' : label(state)),
          ],
        ],
      ),
    ),
  );
}
