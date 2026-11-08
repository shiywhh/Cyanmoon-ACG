import 'package:flutter/material.dart';
import 'package:cyanmoon_acg/bean/widget/error_widget.dart';
import 'package:cyanmoon_acg/services/network/bangumi_acceleration.dart';

class BangumiMirrorErrorWidget extends StatelessWidget {
  const BangumiMirrorErrorWidget({
    super.key,
    required this.onRetry,
    this.onSettingsReturned,
  });

  final VoidCallback onRetry;
  final VoidCallback? onSettingsReturned;

  @override
  Widget build(BuildContext context) {
    final acceleration = BangumiAcceleration.current;

    // 原有的「加速设置」按钮指向已移除的代理设置页（死路由），仅保留重试入口。
    return GeneralErrorWidget(
      title: '暂时无法加载番剧',
      errMsg: '请检查网络连接，或调整加速设置后重试。\n番剧条目加速：${acceleration.label}',
      icon: Icons.cloud_off_rounded,
      onRetry: onRetry,
    );
  }
}
