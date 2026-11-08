import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

import 'package:cyanmoon_acg/bean/settings/settings_list.dart';
import 'package:cyanmoon_acg/bean/settings/settings_detail_scaffold.dart';
import 'package:cyanmoon_acg/bean/widget/loading_indicator.dart';
import 'package:cyanmoon_acg/services/storage/storage.dart';

class SetDisplayMode extends StatefulWidget {
  const SetDisplayMode({super.key});

  @override
  State<SetDisplayMode> createState() => _SetDisplayModeState();
}

class _SetDisplayModeState extends State<SetDisplayMode> {
  List<DisplayMode> modes = <DisplayMode>[];
  DisplayMode? active;
  DisplayMode? preferred;

  @override
  void initState() {
    super.initState();
    init();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      fetchAll();
    });
  }

  Future<void> fetchAll({bool save = false}) async {
    preferred = await FlutterDisplayMode.preferred;
    active = await FlutterDisplayMode.active;
    // 仅在用户显式选择时写回存储：打开页面不应把系统当前值覆写成"偏好"，
    // 否则 init 的恢复逻辑被自己上一次的覆写架空。
    if (save) {
      await GStorage.putSetting(SettingsKeys.displayMode, preferred.toString());
    }
    if (mounted) setState(() {});
  }

  Future<void> init() async {
    try {
      modes = await FlutterDisplayMode.supported;
    } on PlatformException catch (_) {}
    if (modes.isEmpty) return;
    var res = await getDisplayModeType(modes);

    preferred = modes.toList().firstWhere(
      (el) => el == res,
      // 存储值与支持列表失配（换机/分辨率变化）或未保存过偏好时回退系统当前值，
      // 不再 firstWhere 抛 StateError 使恢复静默失效。
      orElse: () => modes.first,
    );
    FlutterDisplayMode.setPreferredMode(preferred!);
  }

  Future<DisplayMode> getDisplayModeType(List<DisplayMode> modes) async {
    var value = GStorage.getSetting(SettingsKeys.displayMode);
    DisplayMode f = DisplayMode.auto;
    if (value != null) {
      f = modes.firstWhere(
        (e) => e.toString() == value,
        orElse: () => DisplayMode.auto,
      );
    }
    return f;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('屏幕帧率设置'),
      body: (modes.isEmpty)
          ? const LoadingIndicator()
          : SettingsList(
              sections: [
                SettingsRadioSection<DisplayMode>(
                  title: Text('没有生效? 重启app试试'),
                  groupValue: preferred,
                  onChanged: (DisplayMode? newMode) async {
                    await FlutterDisplayMode.setPreferredMode(newMode!);
                    await Future<dynamic>.delayed(
                      const Duration(milliseconds: 100),
                    );
                    await fetchAll(save: true);
                  },
                  tiles: modes
                      .map((e) => SettingsTile<DisplayMode>.radioTile(
                            radioValue: e,
                            title: e == DisplayMode.auto
                                ? Text('自动')
                                : Text('$e${e == active ? "  [系统]" : ""}'),
                          ))
                      .toList(),
                ),
              ],
            ),
    );
  }
}
