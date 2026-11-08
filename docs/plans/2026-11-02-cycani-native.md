# 次元城专用原生客户端实施计划

**目标：** 保留 Kazumi 原生播放器、弹幕、下载、设置与本地记录，使用次元城 API 提供网站目录和账号功能，不采用网页套壳。

**架构：** lib/features/cycani 下集中维护 API、模型及原生页面。既有播放器与下载通过稳定 section ID 在每次播放/下载时换取新签名地址；Bearer 仅发送到固定 API 域名，登录状态使用系统安全存储，不嵌入测试凭据。默认沿用 Kazumi 弹幕，通过站点提供的 bangumi_id 匹配，站内弹幕可选补充。

**技术栈：** Flutter 3.47.9、Dio、flutter_secure_storage、既有 Modular/MediaKit/MobX。

## 1. API 与会话
新增 lib/features/cycani/cycani_api.dart、cycani_models.dart；实现推荐/分类/搜索/详情/分页选集/榜单/排期/登录注册重置/资料/追番/历史/评论回复/弹幕，统一错误与单次刷新，测试使用内存 vault 和伪 HTTP adapter。

## 2. 原生页面
新增 cycani_home_page.dart、cycani_detail_page.dart、cycani_account_page.dart、cycani_comments.dart；复用 BangumiCardV、网络图片、现有主题、Player 页面与设置入口。查询按页面代次取消过时响应；账户切换清空私有页面状态。

## 3. 播放与下载集成
修改 video_source/webview_video_source_service.dart 使次元城的稳定选集地址走 API 而非 WebView；修改 video_controller.dart 对接原弹幕的真实 Bangumi ID，并可附加站内弹幕；原播放器页面增加站点评论、发送弹幕与定时云历史上报。原有集数标识不保存过期媒体 URL。

## 4. 启动与品牌
修改 main.dart、index_module.dart、app_widget.dart；启动内置次元城目录，跳过多源规则引导与原版更新。保留原文件与代码，不清理无关目录。Windows 资源名称区分旧 Kazumi。

## 5. 验证与交付
先独立安装匹配 SDK；flutter analyze 与自动测试；真实只读 API 验证；Windows release 构建和应用启动验证。注册、评论、修改资料等实际写入由用户在界面触发，自动验证不向账号提交测试内容。打包程序和源码变更，明确未验证项。
