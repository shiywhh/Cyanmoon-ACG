import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

class TrayService {
  TrayService._();

  static bool _iconSet = false;

  static Future<void> initialize() async {
    if (Platform.isWindows) {
      await trayManager.setIcon('assets/images/logo/cycani.ico');
    } else if (Platform.environment.containsKey('FLATPAK_ID') ||
        Platform.environment.containsKey('SNAP')) {
      await trayManager.setIcon('io.github.Predidit.Kazumi');
    } else {
      await trayManager.setIcon('assets/images/logo/cycani.png');
    }
    _iconSet = true;

    if (!Platform.isLinux) {
      await trayManager.setToolTip('青月次元');
    }

    Menu trayMenu = Menu(
      items: [
        MenuItem(key: 'show_window', label: '显示窗口'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出青月次元'),
      ],
    );
    await trayManager.setContextMenu(trayMenu);
  }

  /// Must run before exit(): the plugin only drops the Windows icon on
  /// WM_DESTROY, and its destroy assumes an icon was set.
  static Future<void> dispose() async {
    if (!_iconSet) return;
    _iconSet = false;
    await trayManager.destroy();
  }
}
