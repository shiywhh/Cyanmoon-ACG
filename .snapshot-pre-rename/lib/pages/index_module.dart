import 'package:flutter/material.dart';
import 'package:kazumi/pages/info/info_module.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/widget/image_preview.dart';
import 'package:kazumi/features/cycani/cycani_home_page.dart';
import 'package:kazumi/features/cycani/cycani_catalog_detail_page.dart';
import 'package:kazumi/pages/route_error_page.dart';
import 'package:kazumi/pages/settings/settings_module.dart';
import 'package:kazumi/pages/video/video_module.dart';

final _imagePreviewTransition = CustomTransition(
  duration: const Duration(milliseconds: 220),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return FadeTransition(opacity: animation, child: child);
  },
);

final indexModule = createModule(
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => const CycaniBootstrap(),
        transition: TransitionType.none,
      )
      ..route(
        '/error',
        child: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('青月次元')),
          body: const GeneralErrorWidget(title: '初始化失败', errMsg: '请重新启动应用后再试。'),
        ),
      )
      ..route('/home', child: (context, state) => const CycaniHomePage())
      ..route('/cycani', child: (context, state) => const CycaniHomePage())
      ..route(
        '/cycani/detail',
        child: (context, state) {
          final id = state.arguments;
          return id is int && id > 0
              ? CatalogDetailPage(
                  row: {'video_id': id, 'catalog_source': 'cycani'},
                )
              : const RouteErrorPage(message: '无效的次元城番剧 ID');
        },
      )
      ..module(infoModule)
      ..module(videoModule)
      ..route(
        ImageViewer.routePath,
        child: (context, state) {
          final args = state.arguments;
          if (args is! ImageViewerRouteArgs) {
            return const RouteErrorPage(message: '图片预览参数无效，请返回后重试。');
          }
          return ImageViewer(
            imageUrls: args.imageUrls,
            initialIndex: args.initialIndex,
            heroTag: args.heroTag,
          );
        },
        transition: _imagePreviewTransition,
      )
      ..module(settingsModule);
  },
);
