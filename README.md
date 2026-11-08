# 青月次元（Cyanmoon ACG）

<div align=center>

<img src="assets/images/logo/logo_rounded.png" width=200></img>

<img src="https://img.shields.io/badge/Flutter-03A9F4?style=for-the-badge&logo=flutter&logoColor=white"></img>
<img src="https://img.shields.io/badge/Dart-00B4AB?style=for-the-badge&logo=Dart&logoColor=white"></img>

</div>

基于开源项目 Kazumi（Predidit）二次开发的番剧播放客户端：以三站聚合
（次元城 / 稀饭 / GiriGiri）为核心，并融合 Bangumi 资料库与账号同步。

## 功能

- 主导航：主页、分类、排行榜、周表、我的。排行榜与周表均可在三站与
  Bangumi 之间切换；聚合搜索覆盖三站与 Bangumi 全库。
- 追番库三站与 Bangumi 收藏并列展示与管理；Bangumi 收藏支持云端同步
  （设置 → Bangumi 账号 授权后可用）。
- 弹幕三路来源并行合并，按 Bangumi ID 与集数精确匹配；评论与回复触底自动加载。
- 播放器保留下载、超分、截图、SyncPlay 共播与外投能力。

## 构建

Flutter 3.47.9，Android 需要 JDK 21、Android SDK 和 NDK 28.2.13676358。

```powershell
./build-cycani.ps1 -FlutterSdk 'D:/path/to/flutter' -Target android
./build-cycani.ps1 -FlutterSdk 'D:/path/to/flutter' -Target windows
```

```bash
flutter test --no-pub
flutter analyze --no-pub --no-fatal-infos
```

联网测试默认跳过；`CATALOG_PUBLIC_LIVE=1` 可启用三站公开接口只读探测。

## 许可

本项目延续上游 GPL 协议。原始版权与源码归属
[Kazumi (Predidit)](https://github.com/Predidit/Kazumi)，在此致谢。
