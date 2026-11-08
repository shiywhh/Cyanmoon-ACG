import 'package:cyanmoon_acg/services/network/acceleration_mode.dart';
import 'package:cyanmoon_acg/services/storage/storage.dart';

enum BangumiAcceleration implements AccelerationMode {
  direct,
  ech;

  static BangumiAcceleration get current =>
      values.asNameMap()[GStorage.getSetting(
        SettingsKeys.bangumiAcceleration,
      )] ??
      (GStorage.getSetting(SettingsKeys.enableBangumiProxy) ? ech : direct);

  @override
  String get label => switch (this) {
    direct => '直连',
    ech => 'ECH',
  };

  @override
  String get description => switch (this) {
    direct => '访问官方接口',
    ech => '启用加密握手',
  };
}
