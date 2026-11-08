# 青月次元 功能说明

- 主导航：主页、分类、排行榜、周表、我的。三站聚合与 Bangumi 融合布局、海报卡片、周表横卡和个人中心布局。
- 分类、搜索、追番、云端观看历史、评论和回复触底自动追加，无上一页/下一页按钮。
- 排行榜仅 TV 番组和剧场番组。
- 搜索为独立页面；追番、下载、云端观看历史集中在“我的”。
- 个人资料、账户安全、本机头像及播放/弹幕设置位于“设置”。本机头像按账户单独保存，不上传服务器。
- 登录会自动处理接口返回的 Bearer 前缀；会话使用系统安全存储。
- 个人中心显示云端观看番剧和追番数量；不把本机统计冒充账号统计。
- 播放返回只更新观看记录，不重载简介和选集；登录后账户入口进入资料设置。
- 保留播放器、下载和超分；弹幕按 Bangumi ID 与集数精确匹配，默认合并外部聚合、稀饭站内、次元城站内三路来源。

## 编译

Flutter 3.47.9，Android 需要 JDK 21、Android SDK 和 NDK 28.2.13676358。

```powershell
./build-cycani.ps1 -FlutterSdk 'D:/path/to/flutter' -Target android
./build-cycani.ps1 -FlutterSdk 'D:/path/to/flutter' -Target windows
```

APK：`build/app/outputs/flutter-apk/app-release.apk`。当前 Android release 使用调试签名，为安装测试版。Windows 需分发整个 Release 目录。

```powershell
flutter test --no-pub
flutter analyze --no-pub --no-fatal-infos
```

联网测试默认跳过；CYCANI_LIVE_SESSION 可指定仓库外的私有会话文件。完整保留原始 GPL 许可证及版权信息。


## 弹幕

“设置 → 弹幕设置”统一管理三路来源、字体、颜色、透明度、区域、速度和屏蔽。
三路默认开启并行合并，单路失败不影响另外两路；播放器内可切换来源并重新加载。
外部源使用弹弹play兼容 JSON 接口，无需在构建时注入 AppId/Key；稀饭只使用公开匿名客户端 API，次元城账号信息不向其他来源发送。
按 Bangumi ID 与正片集数精确匹配，不用相似标题猜测季度或把其他集数拼接为当前分集。
离线缓存保留来源标记；手动更换外部弹幕时保留两路站内弹幕。

只读三路联网测试：`CYCANI_MERGE_LIVE=1 flutter test test/cycani_danmaku_merge_test.dart`。
当前 Android release 使用测试签名；Android 真机测试未执行。

## 三站目录测试版

主页可切换次元城、稀饭、GiriGiri 的推荐。搜索并行请求三站，使用 Bangumi ID 或唯一的同名同年份匹配合并结果，保留每站独立编号。
选源位于原生简介页，稀饭、GiriGiri 已接入简介、选集和原生播放解析。源站媒体实播需单独验证。
GiriGiri 的账户流程应使用“使用原视频账号登录”。不同站点会话独立，登录密码不保存在项目中。

只读三站目录联网测试（PowerShell）：`$env:CYCANI_CATALOG_LIVE='1'; flutter test test/cycani_catalog_sources_test.dart`。

“设置 → 来源账号”支持稀饭邮箱登录、读取观看历史，以及 GiriGiri 原视频账号登录和手动输入图片验证码。跨站追番、历史写回尚未实现。Windows 关闭窗口使用原确认框；移动端隐藏关闭按钮。
