import 'package:kazumi/services/storage/storage.dart';

class CycaniDanmakuOptions {
  const CycaniDanmakuOptions({
    this.external = true,
    this.xifan = true,
    this.cycani = true,
    this.giri = true,
    this.giriExternal = true,
  });
  final bool external;
  final bool xifan;
  final bool cycani;
  final bool giri, giriExternal;
  static const giriSource = '[GiriGiri]';
  static const giriExternalSource = '[GiriGiri外部]';
  static const externalSource = '[外部聚合]';
  static const xifanSource = '[稀饭]';
  static const cycaniSource = '[次元城]';

  factory CycaniDanmakuOptions.read() => CycaniDanmakuOptions(
    external: GStorage.getSetting(SettingsKeys.cycaniExternalDanmaku),
    xifan: GStorage.getSetting(SettingsKeys.cycaniXifanDanmaku),
    cycani: GStorage.getSetting(SettingsKeys.cycaniSiteDanmaku),
    giri: GStorage.getSetting(SettingsKeys.giriSiteDanmaku),
    giriExternal: GStorage.getSetting(SettingsKeys.giriExternalDanmaku),
  );

  static bool managed(String source) =>
      source == externalSource ||
      source == xifanSource ||
      source == cycaniSource ||
      source == giriSource ||
      source == giriExternalSource;

  bool includes(String source) => switch (source) {
    externalSource => external,
    xifanSource => xifan,
    cycaniSource => cycani,
    giriSource => giri,
    giriExternalSource => giriExternal,
    _ => external, // Legacy cached external comments retain their provider tag.
  };
}
