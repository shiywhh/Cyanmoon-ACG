import 'package:kazumi/features/cycani/site_accounts.dart';
import 'package:kazumi/features/cycani/cycani_profile_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/download/download_page_module.dart';
import 'package:kazumi/pages/history/history_module.dart';
import 'package:kazumi/pages/logs/logs_page.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/settings/decoder_settings.dart';
import 'package:kazumi/pages/settings/displaymode_settings.dart';
import 'package:kazumi/pages/settings/download_settings.dart';
import 'package:kazumi/pages/settings/keyboard_settings.dart';
import 'package:kazumi/pages/settings/player_settings.dart';
import 'package:kazumi/pages/settings/renderer_settings.dart';
import 'package:kazumi/pages/settings/settings_page.dart';
import 'package:kazumi/pages/settings/storage_settings.dart';
import 'package:kazumi/pages/settings/super_resolution_settings.dart';
import 'package:kazumi/pages/settings/theme_settings_page.dart';
import 'package:kazumi/request/config/api_endpoints.dart';

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
