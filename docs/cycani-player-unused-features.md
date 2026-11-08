# 次元城播放器功能审计：不再使用 / 不可达的功能

> 审计日期：2026-11-04。范围：`lib/pages/player/`（含 controller，约 7,500 行）、`lib/pages/video/`（video_controller / video_page / 选集面板）、`lib/services/player/`、`lib/services/video_source/`、`lib/webview/`，以及播放器设置键的消费链。
> 方法：逐文件通读 + 每个功能反向 grep 调用方 / 路由可达性 / 运行时取值验证。所有"不可达"结论都附证据行号。
> 已与实际运行的移动端播放器截图逐项核对：菜单六项（弹幕切换 / 视频详情 / 远程投屏 / 外部播放 / 定时关闭 / 一起看）与底栏（播放、下一集、弹幕开关、弹幕设置、弹幕输入框、超分辨率、倍速）、顶栏（返回、快进 80s 长按改秒数、画中画、收藏、更多）均与代码一一对应。

---

## 一、确认存活的功能（不需要动）

| 功能 | 入口 | 备注 |
|---|---|---|
| 超分辨率 | 面板菜单 + 播放设置 | 含 Android MediaCodec 兼容拦截、质量档性能警告 |
| 画中画 | 顶栏按钮 / Android 自动进入 | `pip_utils` + 源矩形同步 + PiP 内弹幕开关动作 |
| 一起看 SyncPlay | 面板菜单"一起看" | 房间、进度同步、聊天弹幕（含弹幕输入框 chatRoom 分支） |
| 截图 | 顶栏/右侧按钮、快捷键 | 桌面候选集 sheet；移动端直接存相册；文件名已 `Cycani_` 品牌化 |
| 定时关闭 | 菜单子项 15/30/60/自定义 | `TimedShutdownService`，与截图恢复播放有互斥保护 |
| 音频服务 | `AudioController` | 媒体通知、耳机按钮、上下集队列 |
| 键盘快捷键 / 系统媒体菜单 | `PlayerKeyboardShortcuts` + `PlayerMenuService` | 托盘/开始菜单跳转表 |
| WebDAV 历史同步 | 全屏切换时自动 | `webDavEnable/History` 设置键有消费 |
| 手势 | `PlayerGestureDetector` | 亮度/音量分半屏、横滑快进、长按倍速、滚轮音量 |
| 弹幕五路合并 + 手动检索 | `danmaku_source_sheet` | dandanplay 凭据为编译期常量（`dandan_credentials.dart`），无 UI 依赖 |
| 自动连播 / 续播 / 背景播放 | 播放计时器 | 设置键均有消费 |
| 下载 / 离线播放 | 选集面板"下载" | 与在线共用原生解析短路 |
| 外部播放、视频详情、面板锁定、adBlocker | 菜单/配置 | adBlocker 经 media_kit `PlayerConfiguration` 透传 |

---

## 二、不可达 / 失效的功能（按严重度排序）

### 1. 远程投屏 —— 永久不可用（每次点击都弹"暂不支持该规则"）
- 入口：面板"更多选项 → 远程投屏"（[player_item_panel.dart:947-973](../lib/pages/player/player_item_panel.dart)）
- 死因：守卫 `if (playerController.referer.isNotEmpty) → toast`。而 `referer` 来自插件定义（[video_controller.dart:787-792](../lib/pages/video/video_controller.dart) 必然传入）——**三个站插件全部设置了 referer**（次元城 `cycani_home_page.dart:30-39`、稀饭/Giri `cycani_catalog_detail_page.dart:512-521` 均带 `referer: origin` 防盗链）
- 结论：对当前所有在线源**无条件死**；离线另有 `isLocalPlayback` 拦截。这是 Kazumi 网络规则时代的兼容保护，次元城三站都是防盗链源，渲染器无法带 referer，功能在产品层面已不存在。`services/player/remote.dart`（RemotePlay）随之不可达

### 2. WebView 视频解析分支 —— 三站全部短路，webview 解析器不可达
- [webview_video_source_service.dart:66-109](../lib/services/video_source/webview_video_source_service.dart)：次元城 section → 原生 `playUrl`；稀饭页面 URL → 原生 `xifanPlayback`；Giri → 直接 m3u8/mp4。**webview 回退分支（:110-162）在当前插件集合下不可能进入**
- 下载链走同一服务（[download_controller.dart:584-598](../lib/pages/download/download_controller.dart) `lease.resolve`），同样短路
- `lib/webview/video/`（controller + impl 374 行）整体成为不可达代码

### 3. 规则引擎播放栈 —— 无调用方
- `traceSearch` / `traceChapters` / `captureSearch`：grep 全仓库，调用方只有 `plugins.dart` 自身和测试
- `plugin_search_service.dart`：`CaptchaRequiredException` 唯一捕获处，但该服务本身无调用方（搜索页已死，见《复用审计》第五章）
- `useLegacyParser` 管道：三个站插件恒为 `false`（[plugins.dart:92](../lib/plugins/plugins.dart) 默认值），唯一能改为 true 的编辑器页面无路由 → 解析永走 webview/原生分支
- `api_rule_engine.dart` / `rule_engine_models.dart`：仅测试引用

### 4. 反爬验证码 WebView —— 不可达
- `lib/webview/captcha/`（三平台实现）只被 `plugins.dart` 的 `anti_crawler_config` 用于规则播放触发验证码时 → 随规则栈一起死

### 5. 插件管理 / 编辑 UI —— 无路由
- `plugin_editor_page`、`plugin_view_page`、`plugin_update_actions`、`rule_dialogs`：无任何路由注册（路由表见《复用审计》）
- 且 `PluginsController.init()`（[plugins_controller.dart:98-115](../lib/plugins/plugins_controller.dart)）**不再种子任何默认规则**——全新安装 `plugins.json` 只有次元城一个插件，用户也无入口新增

### 6. 播放器弹幕输入框的"发送至远程弹幕库" —— UI 存在，行为是假的
- `danmaku_destination_sheet.dart:37-39` 提供"发送至远程弹幕库"选项
- 但处理端（[player_item_panel.dart:177-182](../lib/pages/player/player_item_panel.dart)）对一切非 `chatRoom` 的选择执行**本地回显**，注释原话："This provider has no send API; display a local echo."
- 即：播放器弹幕输入框**从不真正发送**。三站的真实发送入口只在讨论 Tab（`CatalogDanmakuDialog → CatalogDiscussionTarget.send`）。"当前剧集不支持弹幕发送的说"的守卫（danDanmakus 为空）对五路合并源也基本不会触发（站内弹幕被保留进 danDanmakus）

### 7. Bangumi 剧集评论 fallback —— 唯一入口语义失效
- 在线播放全部走 `CatalogPlaybackDiscussion`（[video_page.dart:583-626](../lib/pages/video/video_page.dart) `_catalogDiscussion ?? EpisodeCommentsSheet(...)`）
- fallback 唯一触发条件是**离线播放**（`isOfflineMode → null`）；但本应用可下载的内容全部来自次元城（`toBangumi()` 负 ID），`queryBangumiEpisodeCommentsByID` 拿负 subject_id 查 Bangumi API **必然抛错** → `_hasError` 错误页
- 涉及死链：`episode_comments_sheet`、`episode_comments_view`（322 行）、`video_controller.queryBangumiEpisodeCommentsByID/episodeCommentsList/toggleSortOrder`、`BangumiApi.getBangumiEpisodeByID / getBangumiCommentsByEpisodeID`、`modules/comments/` 模块

### 8. 播放器收藏（心形）与三站追番数据不通 —— 半失效
- 播放器心形（`PlayerPanelHoldCollectButton` → `CollectButton` → `CollectController`）接的是 Kazumi 原版"本地 Hive 收藏库 + Bangumi 同步"通路；播放页/视频页目录中**没有任何对次元城追番 API（`CycaniApi.favorite`）或稀饭/Giri 追番（`setXifanFollow/setGiriFollow`）的引用**——心形与详情页追番菜单是两套互不可见的状态
- 三重断裂：
  1. **数据不通**：详情页追番（写各站云端，主页"我的追番"可见）与播放器心形（写本地库）互不同步，两边状态互不可见
  2. **无处查看**：本地收藏库唯一查看页 `/collect`（`collect_module.dart`）未被任何 module 挂载（`grep collectModule` 全仓库零引用）；且 `collect_page.dart:147` 点击条目 push 未注册的 `/info/`，即使可达也是断链
  3. **开启 Bangumi 同步时静默失败**：次元城条目是 `toBangumi()` 生成的负 ID 假条目（[cycani_models.dart:42](../lib/features/cycani/cycani_models.dart)），链路 `addCollect → _syncBangumiCollectIfEnabled(负ID) → syncCollectibleWhenIdle → BangumiApi.updateBangumiByType(-id)`（[bangumi_sync_service.dart:135-141](../lib/services/sync/bangumi_sync_service.dart) 无负 ID 守卫）必败 → `collect_controller.dart:54` `if (!syncSucceeded) return;` 提前返回——**本地库也不写、无任何提示**，心形永远"未追"；未开同步时能写入本地库，但如 2 所述无处可看
- 现状小结：按钮 UI 可用，但对次元城番剧是无效收藏：同步关 → 收进一个不可见的库；同步开 → 静默失败

---

## 三、功能间的依赖关系（现状说明）

| 不可达功能 | 与存活功能的耦合点 | 说明 |
|---|---|---|
| WebView 视频解析 / 规则引擎 / 反爬验证码 / 插件编辑 UI | `Plugin` 类字段被 plugins.json 序列化共享；`WebViewVideoSourceService` 是在线播放与下载共用的唯一解析入口 | 三站的原生短路分支与 webview 回退分支共存于同一服务，规则栈的代码仍挂在活路径的下方 |
| 播放器弹幕输入框的"发送至远程弹幕库" | 与 SyncPlay 聊天共用同一个 destination sheet；三站真实发送入口在讨论 Tab（`CatalogDiscussionTarget.send`） | 输入框与讨论 Tab 是两套独立发送路径，前者远程分支为本地回显，后者已接通三站 API |
| Bangumi 剧集评论 fallback | 由 `_catalogDiscussion` 为 null（即离线模式）触发；依赖 `modules/comments/` 与 `BangumiApi` 剧集评论接口 | 离线内容来自次元城负 ID，Bangumi 剧集接口不接受该 ID，fallback 呈现为错误页 |
| 播放器收藏（心形） | 与详情页追番菜单分属两套体系：心形 → 本地收藏库 + Bangumi 同步；详情页 → 各站云端追番（次元城 `CycaniApi.favorite` / 稀饭、Giri `setXifanFollow/setGiriFollow`） | 本地收藏库查看页 `/collect` 未挂载路由；Bangumi 同步遇次元城负 ID 静默失败（见第二节第 8 项） |
| 远程投屏 | 与"外部播放"同属"交给外部渲染器"一类，均从菜单进入 | 外部播放不经过 referer 守卫、可达；投屏因 referer 守卫不可达 |

## 四、顺带发现

- `PluginsController.init()` 首次安装会把 `plugins.json` 置空（仅迁移旧版散文件），次元城插件靠 `CycaniBootstrap` 每次启动 `updatePlugin` 写回——规则插件体系实际只剩"次元城"一个活体，其余全是尸体代码
- 播放器表面（`PlayerItemSurface`）是纯 media_kit/mpv，不存在 webview 播放器变体——上游 Kazumi 的"内嵌 webview 播放"形态在次元城中没有对应物
- 手动检索弹幕（dandanplay）链路完整存活，且 `dandanAPIDomain` 已指向 `ext-danmaku.moedot.net` 中继——与外部聚合弹幕共用中继（该主机在本网络有抖动，见《API 链路实测报告》§1.2，弹幕检索同样受影响）
