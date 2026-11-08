import 'package:flutter/material.dart';
import 'package:cyanmoon_acg/bean/settings/settings_list.dart';
import 'package:cyanmoon_acg/services/storage/storage.dart';

class CatalogDanmakuSourceSettings extends StatefulWidget {
  const CatalogDanmakuSourceSettings({super.key, this.onChanged});
  final VoidCallback? onChanged;
  @override
  State<CatalogDanmakuSourceSettings> createState() =>
      _CatalogDanmakuSourceSettingsState();
}

class _CatalogDanmakuSourceSettingsState
    extends State<CatalogDanmakuSourceSettings> {
  static const entries = [
    (SettingsKeys.danmakuSourceExternal, '外部聚合', Icons.forum_outlined),
    (SettingsKeys.danmakuSourceXifan, '稀饭站内', Icons.chat_bubble_outline),
    (SettingsKeys.danmakuSourceCycani, '次元城站内', Icons.subtitles_outlined),
    (SettingsKeys.danmakuSourceGiri, 'GiriGiri 站内', Icons.chat_bubble_outline),
    (SettingsKeys.danmakuSourceGiriExternal, 'GiriGiri 外部', Icons.forum_outlined),
  ];
  late final Stream<void> changes = GStorage.watchSettings(
    entries.map((e) => e.$1),
  );
  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
    stream: changes,
    builder: (context, _) => SettingsSection(
      title: const Text('弹幕来源'),
      tiles: [
        for (final entry in entries)
          SettingsTile.switchTile(
            key: ValueKey(entry.$1.name),
            leading: entry.$3,
            title: Text(entry.$2),
            initialValue: GStorage.getSetting<bool>(entry.$1),
            onToggle: (value) async {
              try {
                await GStorage.putSetting<bool>(
                  entry.$1,
                  value ?? !GStorage.getSetting<bool>(entry.$1),
                );
                if (mounted) widget.onChanged?.call();
              } catch (_) {
                if (context.mounted)
                  ScaffoldMessenger.maybeOf(
                    context,
                  )?.showSnackBar(const SnackBar(content: Text('弹幕设置保存失败')));
              }
            },
          ),
      ],
    ),
  );
}
