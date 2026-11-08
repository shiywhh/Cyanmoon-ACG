import 'package:kazumi/services/network/acceleration_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

enum ImageAcceleration implements AccelerationMode {
  direct,
  ech,
  mirror,
  baidu;

  static ImageAcceleration get current =>
      values.asNameMap()[GStorage.getSetting(SettingsKeys.imageAcceleration)] ??
      baidu;

  @override
  String get label => switch (this) {
    direct => '直连',
    ech => 'ECH',
    mirror => '镜像',
    baidu => '百度',
  };

  @override
  String get description => switch (this) {
    direct => '加载原始图片',
    ech => '加密握手（推荐）',
    mirror => '使用图片镜像',
    baidu => '公共封面与横幅加速',
  };
}
