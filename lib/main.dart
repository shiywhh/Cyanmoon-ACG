import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cyanmoon_acg/app_module.dart';
import 'package:cyanmoon_acg/app_widget.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cyanmoon_acg/bean/settings/theme_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cyanmoon_acg/services/deep_links/app_deep_links.dart';
import 'package:cyanmoon_acg/services/storage/storage.dart';
import 'package:cyanmoon_acg/services/download/download_directory_service.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:cyanmoon_acg/services/network/metered_network_service.dart';
import 'package:cyanmoon_acg/services/network/ech_http_licenses.dart';
import 'package:cyanmoon_acg/services/network/proxy_manager.dart';
import 'package:cyanmoon_acg/services/network/system_proxy_service.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:cyanmoon_acg/pages/error/storage_error_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cyanmoon_acg/utils/device.dart';
import 'package:cyanmoon_acg/services/platform/desktop_window_config.dart';
import 'package:cyanmoon_acg/services/platform/webview_feature_service.dart';
import 'package:cyanmoon_acg/bean/dialog/dialog_helper.dart';
import 'package:cyanmoon_acg/navigation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppDeepLinks().start();
  registerEchHttpLicenses();
  MediaKit.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
      ),
    );
  }

  if (Platform.isAndroid) {
    await WebViewFeatureService.initialize();
  }

  try {
    final hivePath = '${(await getApplicationSupportDirectory()).path}/hive';
    await Hive.initFlutter(hivePath);
    await GStorage.init();
  } catch (e) {
    debugPrint('Storage initialization failed: $e');

    if (isDesktop()) {
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(null, () async {
        // window_manager controls desktop visibility to avoid startup flicker.
        await windowManager.show();
        await windowManager.focus();
      });
    }
    runApp(
      MaterialApp(
        title: '初始化失败',
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [
          Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: "CN",
          ),
        ],
        locale: const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: "CN",
        ),
        builder: (context, child) {
          return const StorageErrorPage();
        },
      ),
    );
    return;
  }
  await DownloadDirectoryService().restoreAccess();
  final showWindowButton = DesktopWindowConfig.showWindowButton;
  if (isDesktop()) {
    await windowManager.ensureInitialized();
    final lowResolution = await isLowResolution();
    final windowOptions = WindowOptions(
      size: lowResolution ? const Size(840, 600) : const Size(1280, 860),
      center: true,
      skipTaskbar: false,
      // macOS embeds native buttons in the Flutter view.
      titleBarStyle: (Platform.isMacOS || !showWindowButton)
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: showWindowButton,
      title: '青月次元',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // window_manager controls desktop visibility to avoid startup flicker.
      await windowManager.show();
      await windowManager.focus();
    });
  }
  if (Platform.isWindows) {
    SystemProxyService.init();
  }
  await MeteredNetworkService.refresh();
  ProxyManager.applyProxy();
  runApp(
    ModularApp(
      module: appModule,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [CyanmoonDialog.observer, rootRouteObserver],
      defaultTransition: TransitionType.material,
      provide: (scoped) {
        scoped.addChangeNotifier<ThemeProvider>(ThemeProvider.new);
      },
      child: const AppWidget(),
    ),
  );
}
