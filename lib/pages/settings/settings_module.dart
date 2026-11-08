import 'package:cyanmoon_acg/features/cycani/site_accounts.dart';
import 'package:cyanmoon_acg/features/cycani/cycani_profile_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cyanmoon_acg/pages/download/download_page_module.dart';
import 'package:cyanmoon_acg/pages/history/history_module.dart';
import 'package:cyanmoon_acg/pages/logs/logs_page.dart';
import 'package:cyanmoon_acg/pages/settings/danmaku/danmaku_module.dart';
import 'package:cyanmoon_acg/pages/settings/decoder_settings.dart';
import 'package:cyanmoon_acg/pages/settings/displaymode_settings.dart';
import 'package:cyanmoon_acg/pages/settings/download_settings.dart';
import 'package:cyanmoon_acg/pages/settings/keyboard_settings.dart';
import 'package:cyanmoon_acg/pages/settings/player_settings.dart';
import 'package:cyanmoon_acg/pages/settings/renderer_settings.dart';
import 'package:cyanmoon_acg/pages/settings/settings_page.dart';
import 'package:cyanmoon_acg/pages/settings/sync/bangumi_sync_page.dart';
import 'package:cyanmoon_acg/pages/settings/storage_settings.dart';
import 'package:cyanmoon_acg/pages/settings/super_resolution_settings.dart';
import 'package:cyanmoon_acg/pages/settings/theme_settings_page.dart';
import 'package:cyanmoon_acg/request/config/api_endpoints.dart';

final settingsModule = createModule(
  path: '/settings',
  register: (c) {
    c.route(
      '/',
      child: (context, state) => SettingsPage(location: state.uri.path),
      children: (sub) {
        sub
          ..route('/', child: (context, state) => const SettingsIndexPage())
          ..route(
            '/source-accounts',
            child: (context, state) => const SourceAccountsPage(),
          )
          ..route(
            '/bangumi',
            child: (context, state) => const BangumiSyncPage(),
          )
          ..route(
            '/account',
            child: (context, state) => const CycaniProfileSettingsPage(),
          )
          ..route(
            '/security',
            child: (context, state) => const CycaniSecuritySettingsPage(),
          )
          ..route('/about', child: (context, state) => const QingyueAboutPage())
          ..route(
            '/storage',
            child: (context, state) => const StorageSettingsPage(),
          )
          ..route('/storage/logs', child: (context, state) => const LogsPage())
          ..route(
            '/theme',
            child: (context, state) => const ThemeSettingsPage(),
          )
          ..route(
            '/theme/display',
            child: (context, state) => const SetDisplayMode(),
          )
          ..route(
            '/keyboard',
            child: (context, state) => const KeyboardSettingsPage(),
          )
          ..route(
            '/player',
            child: (context, state) => const PlayerSettingsPage(),
          )
          ..route(
            '/player/decoder',
            child: (context, state) => const DecoderSettings(),
          )
          ..route(
            '/player/renderer',
            child: (context, state) => const RendererSettings(),
          )
          ..route(
            '/player/super',
            child: (context, state) => const SuperResolutionSettings(),
          )
          ..module(danmakuModule)
          ..route(
            '/download-settings',
            child: (context, state) => const DownloadSettingsPage(),
          );
      },
    );
    c
      // Root route: the license browser must cover the settings shell.
      ..route(
        '/about/license',
        child: (context, state) => const LicensePage(
          applicationName: '青月次元',
          applicationVersion: ApiEndpoints.version,
          applicationLegalese: 'GNU General Public License v3.0',
        ),
      )
      ..module(historyModule)
      ..module(downloadModule);
  },
);
