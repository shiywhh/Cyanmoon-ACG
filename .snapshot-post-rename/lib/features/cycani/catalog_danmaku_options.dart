import 'package:kazumi/services/storage/storage.dart';

class CatalogDanmakuOptions {
  const CatalogDanmakuOptions({
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

  factory CatalogDanmakuOptions.read() => CatalogDanmakuOptions(
    external: GStorage.getSetting(SettingsKeys.danmakuSourceExternal),
    xifan: GStorage.getSetting(SettingsKeys.danmakuSourceXifan),
    cycani: GStorage.getSetting(SettingsKeys.danmakuSourceCycani),
    giri: GStorage.getSetting(SettingsKeys.danmakuSourceGiri),
    giriExternal: GStorage.getSetting(SettingsKeys.danmakuSourceGiriExternal),
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
