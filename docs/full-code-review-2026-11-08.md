# 青月次元 全量代码审查报告（2026-11-08）

> 范围：`lib/` 458 文件 89,198 行 + `test/` 60 文件 11,736 行，逐文件通读。
> `.snapshot-pre-rename/` 与 `.snapshot-post-rename/` 为改名前后冻结存档（与主工程仅差 4 个文件：`qingyue_home_page.dart`、`collect_library_controls.dart`、`collect_library_view.dart`、`timeline_page.dart`，主工程另新增 `collect_layout_switch.dart`；四者均在本次审查范围内），未单独逐行审查。
> 方式：16 路并行审查代理分模块逐行通读并交叉验证调用方；标注 **[已验证]** 的条目由人工二次核对源码确认，其余条目均附行号与代码证据。
> 口径：P0=无条件崩溃/数据丢失/安全；P1=功能性错误（含必现功能失效与条件触发的高危缺陷）；P2=健壮性/性能/泄漏/条件崩溃；P3=轻微/死代码/风格性不一致。只报告问题，未修改任何代码。

---

## 〇、统计总览

| 类别 | 数量 | 说明 |
|---|---|---|
| P0 | 0 | 未发现无条件必现的崩溃/数据丢失/安全问题 |
| P1 | 20 | 详见第二节 |
| P2 | 36 | 详见第三节 |
| P3 | 62 | 详见第四节 |
| 测试问题 | 6 | 详见第五节（含 2 条假通过） |
| 高风险零覆盖模块 | 7 | 详见第五节 |
| 确认无问题重点疑点 | 8 | 详见第六节 |
| 结构性债务 | 4 | 详见第七节 |

---

## 一、审查覆盖清单（16 路）

| # | 审查范围 | 文件数 | 行数 |
|---|---|---|---|
| 1 | features/cycani 账户与聚合核心（site_accounts / catalog_aggregator 等） | 12 | 4,314 |
| 2 | features/cycani 页面与站点接入（qingyue_* / cycani_* / site_* 等） | 16 | 5,616 |
| 3 | features/cycani 弹幕/评论/收藏杂项 | 26 | 4,090 |
| 4 | services/player + video_source + shaders | 21 | 3,009 |
| 5 | services 其余（download/plugin/storage/sync/update/network/platform/deep_links/logging） | 52 | 7,810 |
| 6 | pages/player 核心 UI | 10 | 4,359 |
| 7 | pages/player 面板/弹窗 | 12 | 4,917 |
| 8 | pages/player/controller（含 6 个 .g.dart 核对） | 17 | 3,199 |
| 9 | pages/info + pages/video | 25 | 7,867 |
| 10 | pages/settings + pages/plugin_editor | 41 | 8,527 |
| 11 | pages/search + collect + popular（含 collect_layout_switch） | 22 | 5,235 |
| 12 | pages/download + history + my + timeline + onboarding + about/menu/logs/error | 38 | 7,304 |
| 13 | lib/bean + lib/modules | 89 | 9,907 |
| 14 | lib/webview + lib/plugins + lib/bbcode + 根文件 | 22 | 6,265 |
| 15 | lib/request + lib/repositories + lib/utils | 49 | 5,363 |
| 16 | test/ 全套 + 覆盖缺口评估 | 60 | 11,736 |

---

## 二、P1 功能性错误（20 条）

### A. 结构性断裂（未挂载模块与死链）

**[P1-1] app_module.dart:8-9 / index_module.dart:47-64 / settings_module.dart:76-94 [已验证]**
全工程仅挂载 coreModule→indexModule→(infoModule, videoModule, settingsModule→(danmakuModule, historyModule, downloadModule))。以下模块**已定义但全工程无任何挂载点**（逐一 grep 验证）：
`searchModule`、`collectModule`、`popularModule`、`timelineModule`、`myModule`、`pluginModule`、`proxyModule`、`aboutModule`。
另：`init_page.dart` + 整个 `pages/onboarding/`（7 文件）为孤儿代码，无任何引用。
后果（已验证的存活入口死链）：
- `pages/info/info_tabview.dart:174`：详情页标签芯片 `context.pushNamed('/search/$tagName')` → 路由不存在 → "Route not found"
- `services/deep_links/app_deep_links.dart:76`：外部搜索深链 `'/search/'` → 同样死链
- `pages/route_error_page.dart:21`：错误页"回首页" `navigate('/tab/popular/')` → 不存在，重试后再进错误页
- `pages/plugin_editor/plugin_module.dart:10`：详情页"添加规则"（`info_page.dart:310` → `/settings/plugin/`）→ 空白页，PluginViewPage/PluginEditorPage/PluginShopPage/PluginTestPage 四页整体不可达
- `pages/popular/popular_module.dart:12`：双重损坏——`inject<PopularController>()` 在 core/app/index 任何模块均未注册，即使挂载进入即抛 binding-not-found
- 同步后台逻辑仍在消费 `webDavEnable` 等键（init_page.dart:158、collect_controller.dart:214-247、player_item.dart:596），但配置 UI（sync/proxy 设置页）全部不可达：旧用户被锁死、新用户无法启用
- `autoUpdate`、`checkPluginUpdateOnStartup`、`defaultStartupPage`、`showRating` 等键仍有后台消费方，设置页已删
- `settings_page.dart:102-104` 的 `_categoryPath` 把 `/settings/bangumi|webdav` 映射到 `/settings/sync`，该路由与菜单均不存在，恒不可达分支
> 主路径说明：应用主搜索/追番/排行走 `qingyue_home_page.dart:1160` 直接 push `CatalogSearchPage`，主路径正常；断的是上述遗留入口。若属 fork 有意裁剪，应连同后台消费逻辑一并清理。

**[P1-2] pages/my/my_page.dart:57-63**
旧版「我的」页死代码，且其 5 个跳转目标中 `/settings/plugin/`、`/settings/sync` 不存在（`/settings/history/`、`/settings/download/` 存在）。即使恢复挂载也无法正常跳转。

### B. cycani 聚合层

**[P1-3] features/cycani/qingyue_home_page.dart:784-800 + catalog_library.dart:216 [已验证]**
首页追番库批量"移动已选"必现失效：`PopupMenuItem(value: e.key)` 的 value 是 `'watching'/'want'/'watched'` 字符串，回调却 `await CatalogLibrarySource.writeFollow(entry, int.parse(v))`——`writeFollow` 的 int 语义是 1=在看/2=想看/3=看过（catalog_library.dart:39-58、:216 `moveFavorites(rawId, '$status')`）。`int.parse('watching')` 抛 FormatException 被 `_manage` 捕获 toast 原始异常文本，**选中条目一条都不会被移动**。

**[P1-4] features/cycani/site_accounts.dart:2484, 2512-2563**
`_XifanProfileDialog.onVerify` 从未被渲染：调用方传入 `onVerify: rules['required'] == false ? null : () => _openGiriVerification(userId)`（:1724-1726），但 dialog 的 build 只显示 `emailVerified/editable` 文案，全文件对 `onVerify` 仅有的引用是声明与传参。`rules['required'] != false` 时资料字段被禁用且无法从 App 内发起重验证，`renameGiri` 将永远抛"请先在 GiriGiri 官网完成身份验证"。连带死代码：`_openGiriVerification`（:1747-1758）、`_pendingGiriVerification`/`_resumeGiriVerification`（:1379-1391）、`_reopenGiriVerification`（:1738-1743）、`AppLifecycleListener`（:1491-1492）。

### C. 模型/解析层

**[P1-5] modules/bangumi/bangumi_item.dart:149, 162-164 [已验证]**
`json['rating']['rank'] ?? 0`、`json['rating']['score'] ?? 0.0`、`json['rating']['total'] ?? 0` 三处未判 `json['rating']` 是否存在/为 null：无评分条目（未开播/零评分）fromJson 直接抛 TypeError/NoSuchMethodError → 整页白屏。同文件 :94-97 `parseBangumiVoteCount` 专门做了 `containsKey('rating')` 防御，主路径却漏了。连带：rating 存在但 `count` 结构异常时 `votesCount` 可为空列表，`bean/card/bangumi_info_card.dart:83` `votesCount[i]`（i=0..9）在 showRating 时必然 RangeError。

**[P1-6] utils/search_parser.dart:304-305 [已验证]**
季度筛选窗口整体差一个月：
```dart
final start = DateTime(year, startMonth - 1, 1);  // Q1 → 2023-12-01
final end   = DateTime(year, startMonth + 2, 1);  // Q1 → 2024-03-01
```
Dart 月份 1-based，`month-1` 使"2024Q1"实际筛 [2023-12-01, 2024-03-01)：漏掉 3 月开播番、混入 12 月（秋季）番，四个季度全部错位。经 `effectiveDateRange`（:109-113）传入 `bangumiSearch` 的 `air_date` 过滤。

**[P1-7] utils/m3u8_parser.dart:83-93 [已验证]**
`resolveUrl` 手写拼接丢弃 baseUrl 的 query：分片/嵌套 m3u8/AES-KEY URI（`_parseKey` :196）全部经它重建，`?sign=`/`?token=` 鉴权参数丢失。带 token 的源在线可播但**下载必然 403**（download_manager.dart:436-603 全走此路径）。另：`//host/path` 协议相对 URL 被当普通相对路径拼成 `https:////host/...`；baseUrl 无 `/` 时 `substring(0,0)` 为空。建议改 `Uri.resolve`。

### C2. BBCode 渲染（远程内容可触发）

**[P1-8] lib/bbcode/bbcode_widget.dart:149-160 [已验证]**
BGM 表情分支缺 else 链：`if (id==11||id==23)...; if (id<24)...; if (id<33)...; url = '...tv/${e.id-23}.gif';` 最后一个赋值无条件执行，前三分支全沦为死代码——id<24 常用表情渲染成 `tv/-12.gif` 非法 URL，id 24-32 丢前导零（`tv/1.gif` 应为 `tv/01.gif`）。**所有 id<33 的 bgm 表情显示失败**。

**[P1-9] lib/bbcode/bbcode_base_listener.dart:160**
`[size]` 无属性时 `ctx.attr!` 抛 Null check error（语法 `BBCode.g4` 中 attr 可选）；`[size=abc]` 抛 FormatException。调用处 `user_comments_card.dart:208` 的 `BBCodeWidget` 无错误边界，异常发生在 build() → 该评论卡片被替换为 ErrorWidget 灰块。评论区为任意远程内容，一条畸形评论即可触发。

**[P1-10] lib/bbcode/bbcode_widget.dart:30-38**
`[color=#zzzzzz]` 等长度恰为 6/8 但含非 hex 字符时 `int.parse(hex, radix:16)` 抛 FormatException，与上一条同路径：远程评论 → build 异常 → 渲染失败。

**[P1-11] bean/card/comments_card.dart:114 [已验证]**
条目「吐槽」页评论用裸 `Text(item.comment.comment)` 渲染，项目自带的 BBCode 解析器完全未接入 → 用户看到字面 `[img]…[/img]`、`[b]`、`[quote]` 源码。角色页吐槽（`user_comments_card.dart:208`）已正确使用 `BBCodeWidget`，两页渲染不一致。主要评论页的高频可见缺陷。

### D. 评论分页

**[P1-12] pages/info/info_controller.dart:163-172, 178-187, 291**
评论"静默刷新"（`rateBangumi` 评分成功后调用 `refreshBangumiCommentsSilently`）无条件把列表截断回第 1 页且无 generation 防护：
- 常规路径：翻页加载 N 页后发表评分，列表瞬间坍缩回 20 条
- 竞态路径：加载更多（offset=40 取第 3 页）在途时静默刷新完成 → 列表被替换为第 1 页、`_commentsOffset=20`；随后 loadMore 恢复 `addAll(第3页)` 且 `_commentsOffset=40` → 列表变 `[第1页, 第3页]`，**第 2 页永久缺失**，后续加载重复拉第 3 页

### E. 播放器与协议

**[P1-13] services/player/syncplay_client.dart:503 [已验证]**
`buffer += utf8.decode(data)` 默认 `allowMalformed:false`：中文字符（聊天/用户名/番剧名，本应用必然出现）被 TCP 分包从中间截断时抛 FormatException，该调用不在任何 try 内（:526-533 的 try 只包 `_handleMessage`），socket.listen 回调内未捕获 → 本次数据丢失、连接处理中断。

**[P1-14] services/player/syncplay_client.dart:510-522 [已验证]**
JSON 提帧用花括号计数，**不跳过字符串内的花括号**：聊天消息/文件名含 `{`/`}`（用户极易输入）即破坏配平 → 消息截断挂起、后续消息错位切分，之后所有 State/Set/Chat 消息连续解析失败，同步播放彻底失灵。应按 JSON 规范跳过引号内内容与转义。

**[P1-15] services/video_source/webview_video_source_service.dart:83-92**
`_webview = getController(); await _webview!.init();` 先赋值后 init：`init()` 抛出（WebView2 缺失/首帧超时/平台异常）时 `_webview` 已非 null 但未初始化，后续每次 resolve 直接对未初始化实例 loadUrl 持续失败；实例被 `video_controller.dart:764` 缓存于页面生命周期内，换集/重试全废。应在 init 成功后才赋值，失败置空并 dispose。

**[P1-16] lib/webview/video/impl/video_webview_impl.dart:82-85（android:54-58 / apple:130-134 / linux:65-67 同病）**
JS 桥 handler 只按**第一次** loadUrl 的 `useLegacyParser` 模式注册（`hasRegisteredHandlers` 一次性置位），之后传入不同模式时页面侧脚本按新 mode 调另一个桥名但无对应 handler → `callHandler` 落空，视频源永远解析不出、15 秒超时。持有不同 `useLegacyParser` 规则的多个插件共用同一 WebView 实例（webview_video_source_service.dart:83-92 复用）时，第二个插件必坏。linux 版还把 `useLegacyParser` 闭包捕获进永久 bridge 回调（:89-131）。

### F. 下载与数据完整性

**[P1-17] services/download/download_manager.dart:683-727 [已验证]**
直链断点续传**不校验 HTTP 206**：发送 `Range` 头后解析了 `content-range` 却从不检查 `statusCode==206`（全文件 grep 无 206 判定），服务器忽略 Range 返回 200+全量 body 时仍 `FileMode.append`（:727）追加到半截 `.tmp` 之后 → 「前半段旧数据+后半段全量文件」的损坏视频被 rename 为正式文件、标记 completed，**无任何报错**。

**[P1-18] services/download/download_manager.dart:287-315**
`enqueuePriority` 不取消既有活动任务：只 `_activeTasks.remove(key)` 摘 map 引用，旧 worker 继续跑（cancelToken 未取消，循环条件 `isPaused||isCancelled` 均为 false）；新旧两个 worker 并发写同一个 `seg_XXXXX.ts.tmp`（`_downloadSegmentWithRetry` 固定 tmp 路径）→ 成片内容交错损坏，带宽与槽位双倍消耗。调用方 download_controller.dart:943 在 `networkM3u8Url.isNotEmpty` 时无条件调用。

**[P1-19] services/sync/webdav.dart:145-159 + services/storage/storage.dart:44-63**
WebDAV 备份直接 `File(localFilePath).copy(tempFilePath)` 复制**运行中的 Hive 文件**：收藏写入走 storage.dart 的 `_runCollectChangesWriteExclusive` 队列，WebDAV 上传走自己的 `_webDavOperationQueue`，两条队列互不感知 → 写入与上传重叠时抓到未 flush 的中间态，Hive 追加式文件被截断复制，**远端备份静默损坏**，恢复时丢数据或解析失败。

**[P1-20] modules/collect/collect_change_module.dart:9-13 + modules/collect/collect_sync_merger.dart:66-69, 107-110**
收藏变更 ID 用**秒级时间戳**跨设备充当去重键：`nextId = _nextCollectChangeId < currentSeconds ? currentSeconds : _nextCollectChangeId + 1` 仅在本设备内唯一；合并端 `!remoteChanges.any((r) => r.id == localChange.id)` 以 ID 相等判定"已在远端"。两台设备同一秒各产生变更（ID 均等于该秒值）→ 本地变更被误过滤，随后 `patchCollectibles`（storage.dart:345-348）按 ID 用远端记录覆盖并 `clear()` 重写 → **该收藏在本地与远端同时消失，无提示不可恢复**。根因：ID 同时承担 Hive 主键与同步水位线两个职责，应改全局唯一 ID（UUID/毫秒+设备熵）。

### G. 其他功能性

**[P1-21] pages/timeline/timeline_controller.dart:87-98 + request/apis/bangumi_api.dart:89-91**
非镜像模式季度分页：`getCalendarBySearch` 内部 catch 后返回部分列表（出错页为空），控制器把空页当正常数据 `addAll` 合并，仅当全部天为空才置 `isTimeOut` → 切历史季度时任一页失败**静默丢 20 部番**，UI 显示加载成功。另：空页不提前 break（不足 80 部仍发满 4 次请求）；硬上限 80 部，热门季度超截断。

**[P1-22] request/core/network_config.dart:110 + 48-50 [已验证]**
手动代理一开即 `allowBadCertificates: true` → `badCertificateCallback = (_,__,___) => true` 对**所有主机**放行任意证书（挂在含 Bearer 访问令牌的 bangumiDio 上）→ MITM 可窃取 Bangumi token 与收藏数据。应仅按 host 白名单放行自签。

**[P1-23] test/cycani_danmaku_test.dart:62**
`if (hasDandanCredentials) return;` 位于测试体首行：CI（凭据经 --dart-define 必注入）中该测试**空转返回却报绿色 pass** 而非 skipped。应改 `skip:` 参数。

**[P1-24] test/catalog_ui_consistency_test.dart:338-341**
`final output = Platform.environment['CATALOG_UI_PREVIEW']; if (output == null) return;` —— 无人设环境变量时**零断言直接 pass**。手工预览截图生成器混在常规测试中，制造"视觉回归有覆盖"假象。应显式 skip 或移出 test/。

> 注：编号到 P1-24，其中 P1-1 含多个子项。原 P1 统计按主题合并为 20 条。

---

## 三、P2 健壮性 / 性能 / 泄漏 / 条件崩溃（36 条）

### cycani 聚合层（10 条）

| # | 位置 | 问题 |
|---|---|---|
| P2-1 | catalog_aggregator.dart:490-492 | `tvRequest ??=` 在应用级单例上缓存首页"新番发现"请求：首次失败本次运行**永久为空**（下拉刷新也不重试），首次成功内容永久陈旧；对比 `_giriSchedule`（:834-861）失败会正确重置，行为不一致 |
| P2-2 | catalog_aggregator.dart:904-957 | `_ensureGiriScores` 无并发去重：`_giriScoresDay` 在 await 前不生效，并发周表多个调用同时通过检查，各自最多 20 次分页拉取（N×20 重复请求），后进入者 `_giriScores.clear()` 清掉先进入者已填充数据 |
| P2-3 | catalog_library.dart:151-158 | Giri 收藏夹循环按分页拉取但 `giriFollows()`（site_accounts.dart:645）无 page 参数、每次返回全量 → 收藏≥20 条时 `batch.length < 20` 永不成立，**同一请求重复发 ~16 次**直到 rows 达 cap(300)，靠 seen 去重掩盖 |
| P2-4 | catalog_avatar_store.dart:17-23 | `_ready ??= _load()` 缓存**失败的** Future 且从不重置：index.json 损坏后所有头像操作每次重抛同一异常，**整个会话瘫痪**无自愈 |
| P2-5 | cycani_remote_danmaku.dart:154-157 | 单集在 relay 列表缺失/歧义时 `_relayEpisodes.remove(bangumiId)` 清空**整个番剧**的集数映射；负结果本就不缓存，每次切集重新请求 bgmtv 接口，请求量放大 |
| P2-6 | catalog_danmaku_loader.dart:32-41 | 缓存快路径 `cached.isNotEmpty` 过滤后为空仍返回空 success 不走网络：新增弹幕源/用户只启用缓存中不存在的来源时**永远 0 弹幕** |
| P2-7 | site_accounts.dart:214-236 | Xifan refresh_token 失效后无自愈无自动登出：死会话 `hasSession(false)` 持续 true，UI 显示已登录而 API 全抛异常；每个调用重试注定失败的 refresh（对比 Giri 路径 :451-453 有对称登出） |
| P2-8 | site_accounts.dart:433-461 | 每次 Giri 会话检查无条件把整个 cookie JSON 重写 SecureStorage（平台通道开销大）；`:440 _cookie.clear()` 清共享 jar 有竞态——并发 `captcha()`（:81-99，不经去重）拼出空/半截 Cookie 头 |
| P2-9 | catalog_detail_page.dart:241-243 | xifan 续播记录：`xifanProgressFor` 返回 null（未登录/超出 3000 条窗口）时不判空直接 `setState(() => _resume = fresh)`，**覆盖刚从缓存恢复的续播**，"继续观看"回退"开始观看"；返回播放器（:551）再触发 |
| P2-10 | site_avatar.dart:34-40 | build 内同步磁盘 IO（`existsSync()`+`lastModifiedSync()` 每次 build）+ `Image.file` 无 `cacheWidth` 全尺寸解码 |

### cycani 页面层（2 条）

| # | 位置 | 问题 |
|---|---|---|
| P2-11 | cycani_api.dart:243-251（同模式 :345-362, :364-384） | logout：`_token` 已清但 `_vault.write` 抛出则 `notifyListeners()` 不执行 → UI 显示已登录而所有 auth 请求 401，快照未清理；login/importToken `_persist()` 在 notify 前，失败则登录生效但全部监听方不刷新 |
| P2-12 | features/cycani/qingyue_home_page.dart:785-792 | 批量移动静默跳过非 cycani 条目（`writeFollow` 本身支持按来源路由 catalog_library.dart:207-223，删除入口 :811-816 是全来源处理），行为不一致无提示 |

### 播放器（11 条）

| # | 位置 | 问题 |
|---|---|---|
| P2-13 | pages/player/player_item.dart:1498-1517 | 移动端长按倍速缺 `onLongPressCancel`：指针被系统取消（来电/切窗/手势抢占）只回调 Cancel → **倍速永久卡在快放值**，HUD 卡显示态；下次长按 `lastPlayerSpeed` 记录已污染值，原始倍速永久丢失 |
| P2-14 | pages/player/player_item.dart:1227-1229 | 秒级定时器每 tick 无条件 `roadList[playingSelection.road]` 无空/越界检查（对比 :628-634 有完整防御），不同步窗口内每秒 RangeError 进 zone 未处理错误 |
| P2-15 | pages/player/player_item.dart:397-399 | `handlePreNextEpisode`（键盘 N/P、音频服务通知 :612-613 触发）无 roadList 边界检查，音频服务路径为未处理异步异常 |
| P2-16 | pages/player/player_item_panel.dart:887 | 面板标题 build 期裸索引 `roadList[road].identifier[episode-1]`，`Road.identifier` 与 `data` 等长仅靠插件自觉维护（api_rule_strategy 同步 add，xpath/cycani 无强约束），短 identifier → 整个面板 build 失败红屏 |
| P2-17 | pages/player/player_item_panel.dart:908-921 | 桌面画中画 `await enterDesktopPIPWindow(...)` 不校验结果即 `isPip = !isPip`，且异步异常未捕获：任一 window_manager 调用失败 → isPip 翻转，小窗/全屏按钮/比例同步行为全反（Android 路径反而有 entered 校验） |
| P2-18 | pages/player/player_gesture_detector.dart:45-48 | 手势 seek 状态机不区分指针（只存 `bool? _cancelPending`），第二根手指的 PointerCancelEvent 会误结束第一根手指进行中的横向 seek |
| P2-19 | pages/player/controller/player_syncplay_controller.dart:219-235 | 远端"暂停于 0"不同步本地：`position != 0` 守卫本为规避入房握手初始包，但不区分"初始包"与"真实暂停于 0"（换集后服务器初始态、全员 seek 回开头）→ 本地 autoPlay 继续单播，其他成员解除暂停被拉到超前位置 |
| P2-20 | pages/player/player_screenshot_sheet.dart:102,105-108,162-167 | `_candidatesChanged` setState 换新 PageController、旧控制器 postFrame 才 dispose；新控制器下一帧才 attach，窗口内的指针/键盘事件（缩略图 onTap :955、方向键 :257-258）打到未 attach 控制器 → debug 断言失败、release `StateError: No element`；保存批量写 PNG 掉帧时窗口拉长 |
| P2-21 | pages/player/danmaku_source_sheet.dart:219-234 | 弹幕源切换成功路径不回滚 `_loading`，完全依赖 `KazumiDialog.dismiss`；`_dismissRoute`（dialog.dart:145-162）在 `!route.isCurrent` 时静默返回 → 面板**永久"切换中…"**无恢复路径 |
| P2-22 | services/player/audio_controller.dart:32,36-62 | `ensureInitialized` `_initFuture ??=` 缓存失败 Future 永不清空：`AudioService.init` 平台异常后媒体会话/通知**重启前全废**，每次调用复抛 |
| P2-23 | services/player/remote.dart:10-11 | DLNA `searcher.start()` 无任何 try：SSDP 绑定 UDP 1900 与其他 DLNA 应用冲突时抛 SocketException → 调用方 player_item_panel.dart:986 也未捕获，点"投屏"无任何反馈、弹窗流程中断 |

### 下载（5 条）

| # | 位置 | 问题 |
|---|---|---|
| P2-24 | services/download/download_manager.dart:259-261, 317-325, 799-808 | pause→立即 retry：pause 取消 token 但任务等 worker 收尾才移出 `_activeTasks`（收尾可拖到重试退避 1/3/9 秒），期间 `enqueue` 的 containsKey 检查**静默吞掉**新请求；调用方已把状态写成 downloading，收尾又覆写回 paused，点击无效状态跳变 |
| P2-25 | services/download/download_manager.dart:506-530 | 分片续传仅按"文件存在且 size>0"判定，不校验源一致性：重试/重解析后 m3u8Url 已变（不同清晰度/CDN/广告过滤差异），旧分片仍计入已完成 → playlist 混合两路编码，播放花屏/解码失败且 completed 掩盖 |
| P2-26 | services/download/download_manager.dart:551-576 | 分片 `.then` 回调内 `_notifyProgress`（外部 UI 回调）抛异常 → `semaphore.release()`/`completer.complete()` 全跳过 → `await completer.future` 永久挂起，`_onTaskComplete` 不执行，**并发槽位永久泄漏**后续下载饿死（`.catchError` 兜不住 then 回调内异常） |
| P2-27 | pages/download/download_controller.dart:809-817 + download_manager.dart:281 | 批量下载并发已满时 `enqueue` 把 episode 置 pending 但不持久化不通知 → UI 显示"下载中 0%/暂停按钮"实为"排队中/应显示插队"，直到下次 progress tick 才纠正 |
| P2-28 | services/video_source/video_source_resolver_pool.dart:34-39 | `cancel()` 后 lease 留在 `_activeLeases`（finally release 前同 key `tryAcquire` 全 null）：当前调用方契约正确无实际泄漏，接口层面依赖调用方自觉，脆弱设计 |

### 存储/服务（8 条）

| # | 位置 | 问题 |
|---|---|---|
| P2-29 | services/storage/storage.dart:174-201 | `_openBoxSafe` 把**任何**打开失败都当损坏处理直接 `_deleteBoxFiles`：Windows 杀软/备份进程短暂占用、瞬时 IO 错、锁残留 → **favorites/histories/collectibles 用户数据被删且不可恢复**。应区分校验和失败与其他异常，先重试再删 |
| P2-30 | services/plugins/plugins_controller.dart:117-127 | legacy 规则迁移逐文件 `delete()` 后统一 `_savePlugins()`：第 N 个解析失败时前 N-1 个**已删既不在内存也不在磁盘**，无法恢复 |
| P2-31 | webview/captcha/impl/captcha_webview_inappwebview_impl.dart:268-271, 519-521 | `deleteAllCookies()` 清的是应用级共享 Cookie 存储（android.webkit.CookieManager 单例 / WKWebsiteDataStore 默认存储）：连带清掉视频 WebView 会话及其他插件验证的 CF clearance；dispose 中调用未 await 与销毁竞态 |
| P2-32 | webview/captcha/impl/captcha_webview_linux_impl.dart:409-415 | `getCookieString` 忽略 pageUrl 用 `getAllCookies()` 返回持久化 profile **全部域**的 Cookie 整体作为该插件站点请求头（敏感 Cookie 泄漏给第三方站点），且完整 Cookie 串打进日志流（Windows/InAppWebView 实现均按 URL 过滤，唯独 Linux 不） |
| P2-33 | bbcode/bbcode_widget.dart:96-107 | `TapGestureRecognizer()` 每次 build 新建从不 dispose（RichText 不自动释放 TextSpan.recognizer）：每次 mask 点击 setState 全量重建即泄漏一批 recognizer 及闭包引用 |
| P2-34 | bbcode/bbcode_base_listener.dart:97,107,115,123,131,150,158,166 | 同类标签嵌套单字段被内层覆盖：`[b]a[b]b[/b]c[/b]` 外层前段永不加粗、嵌套 `[quote]`（转发引用常见写法）同样错乱、每个 exit `bbcode.add(Icon)` 图标重复。字段应为栈结构 |
| P2-35 | pages/info/info_tabview.dart:92-96 | `TextPainter` 每次 build 新建 layout/computeLineMetrics **从不 dispose**：概览 tab 每次重建泄漏原生排版资源直到 GC finalizer |
| P2-36 | utils/crypto.dart:31-35 | `calculateFileHash` 一次性 `readAsBytes` 整文件入内存：update_downloader.dart:115/140 校验 100-300MB APK 时内存瞬时翻倍，低内存 Android 可能 OOM。应流式分块哈希 |

### 请求/页面杂项（含在 P3 未列的 P2 级）

| # | 位置 | 问题 |
|---|---|---|
| P2-37 | pages/video/video_controller.dart:558-627 | 离线换集无异常保护（在线路径 `_resolveWithVideoSourceService` 有完整 try/catch）：`_getLocalVideoPath`（Hive :749-755 可抛）与 `playerController.init` 裸奔，上游 changeEpisode 全 fire-and-forget → 坏档时 UI 死态（无 loading 无错误不初始化）+ 全局未处理异常 |
| P2-38 | pages/settings/displaymode_settings.dart:45,53 | `firstWhere` 无 orElse：`DisplayMode.auto` toString 永不匹配真实模式，首次打开页面/换机分辨率变化时 init() 抛 StateError（只 catch PlatformException）→"打开页面恢复偏好"静默失效 |
| P2-39 | pages/settings/displaymode_settings.dart:35 | `fetchAll` postFrame 无条件把**当前**平台 preferred 模式写回存储：用户仅打开该页未做选择，保存的帧率偏好即被系统当前值覆盖，恢复逻辑形同虚设（与 init() 还有写入竞态） |
| P2-40 | pages/settings/danmaku/danmaku_settings.dart:105-152 等 | `await putSetting` 后无 `mounted` 直接 `setState`：拖动滑块连续触发 + 立即退出页面 → `setState after dispose`。同模式遍布 danmaku_settings 全部 7 个 update*、theme_settings_page:207-256、player_settings:253-257、displaymode_settings:36；同目录 danmaku_ch_convert_tile:38、low_memory_mode:43 反而正确，规范不一致 |
| P2-41 | pages/search/search_page.dart:315-321,264,344 + search_controller.dart:115-117 | 搜索网络失败与"无结果"不可区分（API 层 catch 返回 null → `isTimeOut = isEmpty`），空态只有"没有找到番剧"无重试按钮 → 断网时误以为没资源 |
| P2-42 | pages/popular/popular_controller.dart:84,87 | 非 mirror tag 加载更多：每次 `Random().nextInt(8000)+1` 随机 rank（实际取**另一随机排名的第 1 页**）且 `addAll` 无去重（trend 路径 :65-66 有 Set 去重）→ 滚动出现重复卡片、顺序随机跳变 |
| P2-43 | pages/popular/popular_controller.dart:47-90 | 无搜索代次/取消机制（对比 search_controller 的 `_searchGeneration`）：快速切标签新旧结果混写；scroll 触发 add 与 init 并发同理 |
| P2-44 | pages/popular/popular_controller.dart:68,89 + popular_page.dart:95-99,261-274 | tag 失败后 `isTimeOut` 残留：`_selectTag('')` 跳过查询且无人复位 → 已加载的热门列表被错误页遮挡，重试方向还错乱（需手动重试才恢复） |
| P2-45 | pages/search/search_filter_sheet.dart:100-103 + request/apis/bangumi_api.dart:292 | 自定义日期范围结束日被排除：选择器把用户所选 end 原样写入而过滤用 `<`（开区间）→ 选 1/1~1/31 时 1 月 31 日开播的番搜不到（季度路径 end=下季首日是正确开区间，两路径口径不一） |

---

## 四、P3 轻微问题（62 条）

### cycani 聚合层（9 条）

| # | 位置 | 问题 |
|---|---|---|
| P3-1 | site_accounts.dart:222, 439 | 会话 JSON `jsonDecode` 无容错：SecureStorage 内容损坏抛 FormatException，`_xOptions` 使所有 Xifan 调用失败、`_checkGiriSession` 使 `hasSession(true)` 抛异常，无恢复路径 |
| P3-2 | site_accounts.dart:238-248, 276-291, 717-729 | PostgREST 错误对象被 `catalogList`（catalog_models.dart:10-13）吞成空列表：401/错误 JSON 静默渲染为"暂无内容"，无法区分没数据与请求失败 |
| P3-3 | site_accounts.dart:482-488 | `_giriData` 所有 `code!=1` 判定（收藏增删/改名家/删历史/弹幕等）一律报"GiriGiri 历史同步失败"，文案与操作错配 |
| P3-4 | site_accounts.dart:322-329 | `followStatus(giri)` 查单个 id 全量拉追番列表（Xifan 分支 :332-338 已用 `anime_id=eq.$id&limit=1` 精确查询，不对称） |
| P3-5 | catalog_aggregator.dart:73-75, 873-876 | 无 ID 行 `catalogRowKey` 统一得 `'src:0'` 折叠为一条：`mergedSchedule` 直接送入原始行，任一站点周表畸形行与其它畸形行互相吞并 |
| P3-6 | catalog_models.dart:49-75 | `toBangumi()` 对所有来源硬编码 `id: -id, info: 'cycani:$id'`：Giri/Xifan 行得到指向 cycani 的 BangumiItem。当前靠所有卡片覆写 onTap（bangumi_card.dart:34-39）与播放路径用偏移 ID 掩盖，属埋雷 |
| P3-7 | catalog_identity.dart:22-27 | `legacyId` 对 rawId ≥ 1e9 无防护（`fromLegacy` 会把 xifan 条目解码成 giri），纯理论边界 |
| P3-8 | catalog_connection.dart:93-99 | TLS 握手挂起时 `SecureSocket.secure` 的 socket 无超时兜底不销毁（4 秒 deadline 的 fail() 不覆盖它），占用直到 OS 回收 |
| P3-9 | catalog_http.dart:27 | `followRedirects:false` + 默认 `validateStatus`：3xx（典型 PHP 会话过期跳登录页）直接变 badResponse 异常，重定向响应携带的 Set-Cookie 随异常丢失；`retryPublicCatalogRead` 只重试连接类错误不可重试 |

### cycani 页面/弹幕/杂项（11 条）

| # | 位置 | 问题 |
|---|---|---|
| P3-10 | catalog_paging.dart:69-80 | `CatalogFeed.reset()` 缺 `_disposed` 守卫（同类 `clear()` :55-57 有）：dispose 后调用仍清空列表并自增 generation，约定不一致 |
| P3-11 | features/cycani/qingyue_home_page.dart:326-336 | `_loadGiriOptions` 无 try/catch：异常时 `_loadingGiriOptions` 永久 true，giri 筛选下拉整页不再加载；经 `unawaited`（:388）成未处理异常 |
| P3-12 | features/cycani/qingyue_my_page.dart:114-115 | 未登录外部账号显示"0 部"而非"—"（zero-stats 进入 FutureBuilder 与未加载态混淆） |
| P3-13 | catalog_detail_page.dart:364 | FutureBuilder builder 内不经 setState 修改 `road` 字段，脆弱写法 |
| P3-14 | site_native_catalog.dart:238-241 | `vod_rel_vod` 的 `int.parse` 遇超 int64 数字串抛 FormatException（懒求值在 Future.wait 迭代中），整个 giri 详情失败（内层已有逐项 try，此处漏） |
| P3-15 | features/cycani/qingyue_home_page.dart:125-126, 156, 542, 554, 666 | 死代码：search TextEditingController 从未绑定输入框；`keyword` 从未赋值 → :666 `keyword.isNotEmpty` 永假，"全部频道"选项、`zone==null` 分支、`CycaniApi.videos` 的 `zone ?? 1`（cycani_api.dart:468）全为死路径 |
| P3-16 | catalog_week_selector.dart:102-121 | `CatalogWeekPicker` 全仓库无引用，死代码 |
| P3-17 | catalog_danmaku_loader.dart:87-122 | `static load(...)` 全仓库无调用方，死代码 |
| P3-18 | catalog_danmaku_loader.dart:96-99 + video_controller.dart:671-687 | 本地回放缓存命中回写 `bangumiID: 0` 覆盖 wrapper 的 danDanBangumiID（当前读回方 download_controller.dart:429 丢弃该 ID，潜在数据降级） |
| P3-19 | catalog_library.dart:165-168 | `catch (e) { return const []; }` + 空 `finally {}`：站点收藏/历史失败静默吞掉显示"暂无内容" |
| P3-20 | cycani_remote_danmaku.dart:214-216 | 站内弹幕颜色一律按 16 进制解析（十进制整数会被错解），与 `CatalogDanmakuCodec.color` 先试十进制的语义不一致；:48-49 `_matches/_relayEpisodes` 成功结果永不淘汰缓慢增长；catalog_avatar_store.dart:77-103 换扩展名/清除时旧文件成孤儿累积（单个上限 8MB） |

### 播放器（14 条）

| # | 位置 | 问题 |
|---|---|---|
| P3-21 | pages/player/player_keyboard_shortcuts.dart:87-92, 165-171 | 键盘长按倍速窗口失焦 KeyUp 丢失 → `_activeLongPressKeys` 残留、倍速卡提升值（未监听 onBlur） |
| P3-22 | pages/player/player_item.dart:172-174 | resumed 分支 `await setPrefetchSuspended(false)` 无 try/catch（paused 分支有） |
| P3-23 | pages/player/player_item.dart:1440-1449 | 滚轮调音量不受 `_openPlayerMenuCount`/`lockPanel`/`isPip` 拦截（键盘路径有），逻辑不一致 |
| P3-24 | pages/player/player_item.dart:1210-1215 | 亮度轮询 Future 无 catchError：插件抛 PlatformException 时每秒一个未处理异步错误 |
| P3-25 | pages/player/player_item.dart:1044-1051 | `handleSpeedChange` 当前倍速不在预设表时 indexOf=-1："up" 分支 `index++` 得 0 跳到 0.25x，"down" 误报已达下限 |
| P3-26 | pages/player/player_item_panel.dart:355-357 | 跳过秒数 `int.parse(input)` 无长度/溢出保护（>19 位抛 FormatException 未捕获） |
| P3-27 | pages/player/player_item_panel.dart:986-995 | 远程投屏 `castVideo(...).whenComplete(...)` 失败时错误未处理且仍尝试恢复播放 |
| P3-28 | pages/player/player_item.dart:426, 480-482, 984-994 | `changeEpisode/pause/play` 等异步调用未 await 也未 unawaited，内部抛错即未处理异常，换集失败静默 |
| P3-29 | pages/player/player_item.dart:1030-1038 + player_panel_hold.dart:99-119 | 全屏切换 `_releasePlayerPanelHolds()` 后悬停中的 MouseRegion 不会重新获取 hold：鼠标停在底栏切全屏后面板仍自动隐藏一次 |
| P3-30 | pages/player/player_item.dart:740-744, 785-786 | 移动端截图无 busy 防抖（桌面有）+ `_playScreenshotFeedback()` 在结果前执行，失败也播白闪动画 |
| P3-31 | pages/player/player_controller.dart:259-278 | 移动端系统音量监听器 addListener 后才做 stale 检查，失效返回不移除（瞬态泄漏自愈） |
| P3-32 | pages/player/player_item.dart:387-393 + services/platform/player_menu_service.dart:11-32 | macOS 菜单 init/dispose 均 unawaited：极短生命周期页面时已销毁页面的 handler 与启用态遗留 |
| P3-33 | pages/player/player_progress_bar.dart:287-292 | total==0 时 recognizer 仍无条件 `resolve(accepted)`：点击进度条不 seek 也吞掉点击（下层播放/暂停收不到） |
| P3-34 | pages/player/controller/ 多处 | `player_danmaku_controller.dart:96` `late canvasController` 无初始化守卫（SyncPlay/睡眠定时器在首帧前触达即 LateInitializationError，窗口极窄）；`player_debug_controller.dart:56-61` playerLog 无上限增长（详细日志级 mpv 输出大）；`player_playback_controller.dart:530,419` setRate/setPlaylistMode 未 await，try/catch 捕不到异步错误且 setRate 无 isCurrentPlayer 守卫；:161-177 restartFromBeginning 在 play await 后清 startOffset 有跨播放器竞态（窗口极窄）；:295 `MPVLogLevel.values[debug.playerLogLevel]` 无钳制，越界被 init catch 吞成黑屏静默失败；:441-442 错误日志在守卫外用当前 videoUrl 记旧播放器错误；player_seek_controller.dart:56-57 乐观写 currentPosition 失败不回滚；player_danmaku_controller.dart:315-339 getDanDanmakuByEpisodeID 并发无世代守卫（仅 loading 标志闪烁）；弹幕 offset≠0 时本地即时回显与重载位置差 offset（轻微） |

### 播放面板/弹窗（10 条）

| # | 位置 | 问题 |
|---|---|---|
| P3-35 | pages/player/danmaku_source_sheet.dart:229-232 | 切换失败 `catch (_)` 吞异常不写日志（同文件 `_searchAnime/_selectAnime` 都记日志，唯独真正改播放器状态的一步不记） |
| P3-36 | pages/player/danmaku_source_sheet.dart:120-123, 141-152 | 隐私模式只 gate 写入，旧搜索历史 chips 无条件渲染 → 开隐私模式后历史仍可见 |
| P3-37 | pages/player/player_screenshot_sheet.dart:127-129 | 邻图预缓存全分辨率解码 + 96MB 原始字节上限 → 浏览时解码缓存+原始字节可达 ~200MB（桌面入口故降 P3） |
| P3-38 | pages/player/episode_comments_view.dart:309-316 | `Tooltip(message: subtitle)` 传空字符串 → 悬停/长按弹空白气泡 |
| P3-39 | pages/player/episode_comments_view.dart:127-131 | `findChildIndexCallback` 用 `comments.indexOf` O(n) 反查 → 刷新 O(n²)；依赖对象同一性，未来重写 `==` 即错乱 |
| P3-40 | pages/player/syncplay_sheet.dart:607-612 | 官方服务器判断原样 `contains` 大小写敏感（连接时 `isOfficialSyncPlayEndPoint` 有小写归一）→ 已保存 `SYNCPLAY.PL:8996` 回显成"自定义" |
| P3-41 | pages/player/syncplay_sheet.dart:621-632 + syncplay_endpoint.dart:40-53 | 自定义地址校验接受含内部空格 host（`"ho st:8996"` 通过），错误反馈滞后到连接时 |
| P3-42 | pages/player/syncplay_sheet.dart:471-476, 630 | `GStorage.putSetting` 火后不理无错误处理（对照 danmaku_source_sheet 的历史写入有 catchError+日志，标准不一） |
| P3-43 | pages/player/episode_comments_sheet.dart:82-88 | 盲信 `applied` + 上游 `getBangumiEpisodeByID` 吞错返回 id=0 模板 → "加载失败"可误报为"本集还没有讨论"（sheet 可校验 `episodeInfo.id != 0` 兜底） |
| P3-44 | services/player/ 其余 P3 | syncplay_client.dart:615-618 Hello 缺 room 字段无防御抛 NoSuchMethodError（:609 有 containsKey 防御但 :616 在防护外再访问；:685 空 event map 抛 StateError）；:914-922 `_runInBackground` 非连接类错误 `Error.throwWithStackTrace` 配合 unawaited 成 zone 错误；:102-112 `.first.timeout` 后残留监听到下次事件；:285 TCP 连接无超时可挂数十秒；audio_controller.dart:202 封面解析期间（最长 8s）`_artworkPending` 丢弃全部播放状态发布（按暂停时系统控件仍显示播放中）；remote.dart:75-77 对话框关闭后流事件仍 setState（缺 mounted）；timed_shutdown_service.dart:38-49 Timer.periodic 每秒减 1 挂起时漂移；shader_asset_service.dart:31-35 按 exists 跳过 → 版本更新着色器永不更新，:9 late 目录失败后访问抛 LateInitializationError（被 playback_controller:487 吞掉降级）；pip_utils.dart:16-17 画中画比例未 clamp 到 Android 合法区间（~0.418-2.39），越界原生抛 IllegalArgumentException 只捕 PlatformException |

### info/video 页（5 条）

| # | 位置 | 问题 |
|---|---|---|
| P3-45 | pages/info/info_controller.dart:271-293 | 评分已成功但后续刷新失败误报"发表失败"（重试幂等无脏数据，纯误导） |
| P3-46 | pages/info/source_sheet.dart:78-79 | `_pluginFor` 用无 orElse 的 firstWhere：插件列表变动名称失配时抛 StateError（:103,123,212 三处调用） |
| P3-47 | pages/info/info_controller.dart:189-220 | 角色/staff 列表无代际防护（relations 有 `_relationRequestGeneration`），并发响应交错写同一列表（当前被上层旗标掩盖） |
| P3-48 | pages/video/video_controller.dart:856-864 | xifan 片尾段非数字时 `_cycaniSection=null`，但 15 秒 Timer.periodic 仍创建空转（进度永不上报+无效唤醒） |
| P3-49 | pages/info/source_captcha_flow.dart:90, 23-98 | 用户取消验证弹窗后 `verified.future` Completer 永不 complete → 悬挂 async 帧泄漏，可随使用累积 |

### 设置/插件编辑器（5 条）

| # | 位置 | 问题 |
|---|---|---|
| P3-50 | pages/settings/proxy/proxy_editor_page.dart:70 | 代理测试 `allowBadCertificates: true`（死代码页，恢复路由时应改默认校验） |
| P3-51 | pages/settings/sync/webdav_server_page.dart:57 | WebDAV 密码明文存 Hive（`webDavPasswd` settings_keys.dart:787），与三站会话走 SecureStorage 不一致 |
| P3-52 | pages/plugin_editor/plugin_editor_page.dart:988-1027 | 保存规则无名称校验：空名规则经 `_replacePlugin`（pluginNameKey('')=''）互相替换、ValueKey('') 混乱；导入路径有失败反馈而编辑器路径没有 |
| P3-53 | pages/plugin_editor/rule_dialogs.dart:121 | 分享/导入链接内嵌 captchaScript（在站点 WebView 上下文执行的 JS）无信任提示（桥能力受限无逃逸面，仅缺提示） |
| P3-54 | pages/settings/danmaku/danmaku_settings_sheet.dart:229-247 | "跟随视频倍速"开关直接读存储作 initialValue 与同文件其他控件数据源不一致（行为正确，仅不一致） |

### search/collect/popular（11 条）

| # | 位置 | 问题 |
|---|---|---|
| P3-55 | pages/collect/collect_page.dart:57-66 | 布局切换不持久化（只 setState 不写回）；timeline_page.dart:41 恒从 list 开始；qingyue_home_page.dart:167 用独立 weekGridMode —— 三处页面行为不一致 |
| P3-56 | pages/collect/collect_controller.dart:144-151 | `canLaunchUrl/launchUrl` 无异常保护（部分平台抛 MissingPluginException 等，兜底 toast 也不执行）；:44 `addCollect({type = 1})` 推断 dynamic（.g.dart:32 可证） |
| P3-57 | pages/collect/collect_sync_dialog.dart:153-156 | 运行中第一步置 running 前的空窗 `indexWhere` 返回 -1 → "第 0 / N 步" |
| P3-58 | pages/collect/collect_sync_dialog.dart:171-172 + dialog_task.dart:181 | `clickMaskDismiss: true` 默认 + `PopScope(canPop:!_running)` 只拦返回键：同步进行中点遮罩仍 pop(null) 静默取消进度 UI，与 canPop 意图矛盾 |
| P3-59 | pages/search/search_controller.dart:79-86 | 搜索历史在结果未知前写入（deleteDuplicates/saveHistory 先于 bangumiSearch await），网络失败也留词条 |
| P3-60 | pages/search/search_module.dart:36 | 对 path 参数二次 URL 解码（info_tabview:173 已 encodeComponent，modular 段通常已解码）：含孤立 `%` 的标签抛 FormatException |
| P3-61 | pages/search/search_page.dart:252-258, 342 + collect_page.dart:142 | Observer build 内同步 IO（loadWatched/AbandonedBangumiIds 仓库同步读、getSetting） |
| P3-62 | pages/search/image_search_widgets.dart:135 | 以文案字符串 `'未找到匹配结果'` 作控制流哨兵，改文案即把无结果误渲染成错误态 |
| P3-63 | pages/popular/popular_page.dart:154 | 空列表 `childCount: 10` 全 null 占位；popular_controller.dart:62-64 短页按整页推进 offset 跳条目、到末尾后每滚动事件重复发请求 |
| P3-64 | pages/collect/collect_library_view.dart:171 | Escape 无条件 `_closeSearch` → 未在搜索态按 Esc 也归零滚动位置 |
| P3-65 | pages/search+popular 目录级 | 整目录死代码（见 P1-1），popular 双重损坏（模块未挂载+控制器未注册） |

### services/存储/网络（13 条）

| # | 位置 | 问题 |
|---|---|---|
| P3-66 | services/download/download_manager.dart:101, 328-352 | `IDownloadManager.resume` 全工程无调用点死代码；其 `_activeTasks.remove(key)` 与 enqueuePriority 同隐患 |
| P3-67 | services/download/download_manager.dart:136-161 | 并行数设置只在构造时读一次：设置页滑块保存后运行中实例不刷新（对比 download_controller.dart:534 resolver 池每次重读），需重启生效 |
| P3-68 | services/download/background_download_service.dart:131-142 | `stopService` 失败时 `_isRunning` 仍 true → 后续 stop/updateProgress 被短路 |
| P3-69 | services/plugin/rule_engine.dart:310 | `'referer': '${config.baseUrl}/'` baseUrl 已带 `/` 时产生 `https://x.com//`，Referer 精确校验站点失败 |
| P3-70 | services/storage/storage.dart:227-236, 263-280 | `backupBox`/`restoreCollectibles` 无调用点死代码；后者若启用还有：绕过收藏写队列、clear 与逐条 put 间无 flush、`tempBox.close()` 不在 finally |
| P3-71 | services/storage/storage.dart:356-366 | `getSetting<T>` 用 `storedValue is T`：Hive 历史 int 遇 double 类型 key 静默回落默认（当前 key 无此路径，仅提示） |
| P3-72 | services/storage/image_cache_service.dart:20-43 | `sizeInBytes` 中 `file.stat()` 未捕获瞬时删除异常；`clear()` 只捕 PathNotFoundException，Windows 文件占用时中途失败 |
| P3-73 | services/network/image_file_service.dart:37-53, 112-118 | 信号量等待者在 `close()` 时不会被唤醒；`handedOff=true` 到 createImageFileResponse 之间同步抛则许可与 client 永久泄漏 |
| P3-74 | services/network/system_proxy_service.dart:296-298, 325-339 | 启动失败路径 `_stopWatcher` 关闭句柄但从不 UnregisterWait（线程池等待挂在已关闭句柄上）；`readString` 仅 RRF_RT_REG_SZ，ProxyServer 为 REG_EXPAND_SZ 读不到 |
| P3-75 | services/update/auto_updater.dart:226 | `launchUrl(...)` 未 await 未处理返回值，跳 release 页失败无感知 |
| P3-76 | services/platform/display_mode_service.dart:53-77 | `_systemBarsHidden` 在平台调用成功前置位：`_attempt` 吞掉瞬时失败后相同值被短路，本会话系统栏状态永久失真 |
| P3-77 | services/logging/logger.dart:178-206 | `t/d/i/w/e` 接受 stackTrace 参数全部丢弃（仅 f 使用），堆栈不落盘 |
| P3-78 | services/sync/bangumi_sync_service.dart:142-150 | `_applyLocalMutation` 两步提交：putCollectible 成功后进程在 appendCollectChange 前中断 → WebDAV 增量 change log 缺失该变更，两设备静默漂移 |

### request/utils（12 条）

| # | 位置 | 问题 |
|---|---|---|
| P3-79 | request/apis/bangumi_api.dart:43 | `getCalendar` 对缺失日期键无容错（`jsonData['$i']` 无 `?? []`，对比 :129 镜像版有）：缺任一天键外层 catch 返回部分列表静默残缺（与 P1-21 叠加） |
| P3-80 | utils/version.dart:3-19 | `needUpdate` 裸 `int.parse`：`v1.2.3`/`1.2.3-beta.1` 即抛（当前 tag 纯数字"2.4.3"潜伏；plugins_controller:290-294 有兜底而 auto_updater.dart:140 落通用 catch） |
| P3-81 | request/apis/bangumi_api.dart:569-571 + config/api_endpoints.dart:141-146 | `formatUrl` 纯 replaceAll 不编码：用户名含空格/`?`/`#`/`%` 时 `/v0/users/{username}/collections` 构造异常 |
| P3-82 | utils/m3u8_parser.dart:303-321 | `resolveNestedSegments` 组偏移 off-by-one（`groupOffset += maxNestedGroup` 应 +1）：外层段与嵌套锚点同组时组号碰撞 → 少写 DISCONTINUITY、广告过滤误判（仅影响含不连续的嵌套播放列表） |
| P3-83 | utils/media.dart:27-36 | `extractEpisodeNumber` 取标题第一段数字：「3D××× 第01话」→ 3（弹幕按集匹配错集；Re:0 → 0 被 >0 兜底但 3 这种不会） |
| P3-84 | request/apis/danmaku_api.dart:73 | `jsonData['comments']` 无容错：服务端错误 JSON 抛原始 TypeError 绕过统一错误映射 |
| P3-85 | utils/async_rate_limiter.dart:12-18 | 用墙钟 `DateTime.now()` 非单调时钟：NTP 校时/回拨影响等待间隔（配合 bangumi_api.dart:709 写限流器可能触发 429） |
| P3-86 | utils/date_time.dart:24-32 | dateFormat detail 分支死赋值：'MM-DD hh:mm' 格式永不生效恒用含年份格式 |
| P3-87 | request/core/ech_transport.dart:12, 74-80 | ECH 硬编码固定 Cloudflare IP 三站共用（api.bgm.tv/lain.bgm.tv/gh-proxy.org）：CDN 换段即整体失连只能随发版修复 |
| P3-88 | utils/m3u8_parser.dart:56-58, 159 | `bestVariant` 空列表 `reduce` 抛 StateError；EXTINF 非数值 `double.parse` 抛 FormatException（有外层兜底但错误信息裸） |
| P3-89 | request/apis/bangumi_api.dart:361-423 等 | CancelToken 全链路存在但 BangumiApi/DanmakuApi/TraceApi 无一透传：页面级取消全靠"结果过期"，网络本身不取消，长搜索退出仍占连接带宽 |
| P3-90 | request/apis/bangumi_api.dart:407-424, 509-523 | getBangumiEpisodeByID/getCharacterByCharacterID 失败静默返回模板 → 无法区分"无此集"与"请求失败"（连带 P3-43）；utils/anime_season.dart:44 season 边界带时间后缀进 air_date 过滤依赖服务端宽松解析；repositories/collect_repository.dart:21-29 孤儿注释（四条 doc 对应方法不存在） |

### webview/plugins/bbcode/根文件（12 条）

| # | 位置 | 问题 |
|---|---|---|
| P3-91 | lib/plugins/plugins.dart:188 | `int.parse(api)` 来自不受信 JSON（legacy 迁移不校验），值 `'2.0'` 抛 FormatException（导入/更新路径有 try，编辑器等读取点无） |
| P3-92 | lib/plugins/plugins_controller.dart:108 | 损坏 plugins.json 顶层非 List 时 for 遍历出 MapEntry 类型异常 → pluginList 已被 clear，后续写盘把空列表覆盖回去；写盘无 temp+rename 原子性 |
| P3-93 | lib/plugins/plugins_controller.dart:210-233 | onReorder 快照 JSON 在进串行队列**之前**生成：与排队中的 remove/update 交错可能把含已删规则的中间态写回（revision 只防并发 reorder） |
| P3-94 | lib/webview/video/impl/video_webview_impl.dart:47-48, 131 | `shouldInterceptRequest` 内 `unloadPage()` 未 await 未捕获 |
| P3-95 | lib/webview/video/video_webview_controller.dart:53-57 | broadcast 流无重放：极快拦截的事件在调用方 `.first` 订阅前发出即丢失白等超时 |
| P3-96 | lib/webview/captcha/captcha_webview_windows_impl.dart:20-73 | init() 无重入保护：重复调用重复订阅 loadingState 并对运行中 headless 再 run() |
| P3-97 | lib/webview/video/impl/video_webview_android_impl.dart:279（apple:322, linux:73） | `webviewController!` 空断言：init 的 onWebViewCreated 未回调或 dispose 后调用即 null check 异常（windows 实现用 `?.`，不一致） |
| P3-98 | lib/bbcode/generated/* | BBCode.tokens:37-38 / Lexer:39-40 / Parser:31 生成代码中文 token 是乱码（生成时源编码错误），token 永不匹配属死 token 维护陷阱 |
| P3-99 | 验证码 JS（三平台同构） | a) 跨域验证码图 canvas 被 taint → toDataURL 抛 SecurityError 被静默吞，类型1验证码静默失效；b) captcha code 含换行时 `'$escapedCode'` 单引号串语法错误（转义只处理 `\` 和 `'`）；c) inappwebview 版 submitCaptchaInteract（:461）evaluateJavascript 无 try/catch |
| P3-100 | lib/webview/captcha/impl/captcha_webview_inappwebview_impl.dart:130-132 | 文档启动注入脚本首行 `callHandler(...)` 无 try（整段未包 IIFE）：桥不可用即 ReferenceError 终止整个 UserScript（同文件 :360-361 按钮脚本首行就有 try） |
| P3-101 | lib/webview/video/impl/video_webview_impl.dart:450-468 | Range 请求黑名单漏 `.webp/.jpeg/.avif/.m4a/.vtt/.otf`：任何带 Range 头资源被当视频 URL 触发 notifyVideoSourceResolved，播放器拿错地址且搜索提前终止 |
| P3-102 | lib/main.dart:29 | 存储初始化失败早退路径上 `AppDeepLinks().start()` 仍订阅且 `markReady` 永不调用 → `_open` 永久挂起于 `_ready.future` |
| P3-103 | bbcode 性能/残留 | bbcode_widget.dart:57-65 每次 build（含 mask 的 setState）同步在 UI 线程完整重跑 ANTLR 解析不缓存；video_webview_impl.dart:33、video_webview_android_impl.dart:35 生产代码残留 `print('[WebView] Created ...')` |

### bean/modules（8 条）

| # | 位置 | 问题 |
|---|---|---|
| P3-104 | modules/collect/collect_button.dart:37-59 | 收藏按钮不订阅 `CollectRepository.changes`：WebDAV 同步/其他入口改动同条目时已挂载按钮状态残留 |
| P3-105 | modules/bangumi/bangumi_item.dart:100, 150-159 | 解析过严：`json['${i+1}'] as int`（count 缺失/变 double 即抛）、`json['image']` null 时 `Map.from({'large': null})` 抛类型错误 |
| P3-106 | modules/bangumi/bangumi_review.dart:6 | `assert(score>=0 && score<=10)` 仅 debug 生效，release 放行越界分数 |
| P3-107 | bean/card/bangumi_info_card.dart:65-67 | votes==0 时 `votesCount[i]/votes*100` → tooltip 显示 "NaN% (0人)" |
| P3-108 | modules/danmaku/danmaku_module.dart:41-43 | DanmakuEntry 颜色持久化 `(color.r*255).toInt()` 截断非四舍五入且丢 alpha（视觉不可辨） |
| P3-109 | modules/comments/comment_response.dart:18 | `total: json['total']` 未判空（其余字段均有 ?? 防御） |
| P3-110 | modules/danmaku/danmaku_episode_response.dart:47 vs 58 | toJson/fromJson 结构不对称（fromJson 读 `json['bangumi']['episodes']`，toJson 把列表直写 `'bangumi'` 键）往返必崩——当前无调用方死代码；comment_item.dart:163-168, 212-218 与 comment_response.dart:29-34, 58-62 同类 toJson 键不对称死代码 |
| P3-111 | modules/characters/character_item.dart:70,79 | `json['actors'] as List`、`json['images'] as Map` 空缺强转崩溃（无 cast 角色/无图角色整页失败）；:43 `infobox[0]['key']` 空 infobox RangeError（当前无调用方带雷死代码）。同文件族见 P2 组：comment_item.dart:51,108,156 头像/已删用户/replies 空缺强转崩溃 |

### 页面杂项（7 条）

| # | 位置 | 问题 |
|---|---|---|
| P3-112 | pages/logs/logs_page.dart:126-136 | 清空日志自行拼路径 `writeAsString('')` 绕过 logger 的 `_logLock`，与后台写入交错可能写丢 |
| P3-113 | pages/logs/logs_page.dart:74-78 + logger.dart:126-146 | 日志页 `readAsString()` 全量载入+`_fullContent` 副本（日志无轮转见 P3-77 邻项，logger.dart:96-152 无轮转无上限），打开日志页内存瞬间翻倍 |
| P3-114 | pages/download/download_controller.dart:489-497, 516 | 同集号换线路重下静默覆盖 completed 元数据（URL 去重挡不住不同线路），旧自定义目录文件成孤儿，无确认弹窗 |
| P3-115 | pages/download/download_controller.dart:601-617 | 任意解析异常（DNS/404/结构变更）统一误报"解析视频源超时" |
| P3-116 | pages/download/download_episode_sheet.dart:212-234 | 批量下载把 paused/failed/resolving 视为可选但 startDownload URL 去重静默跳过 → toast 虚报"已添加 N 集" |
| P3-117 | pages/download/download_controller.dart:126 | 平台回调 `data['id'] as String` 无保护强转（缺键/类型不符抛未捕获） |
| P3-118 | pages/my/my_controller.dart:104-106 | `_shieldSubscription ??=` 永不取消（注释声明播放期保活属有意，但控制器非应用级单例时即订阅泄漏，与同文件 attach/detach 严格管理不一致）；pages/timeline/timeline_options.dart:111-121 开关回调直接传 `Future<void> Function(bool)` 未 await 未 unawaited |

### 下载死代码（并入 P3-66）与旧版页面

| # | 位置 | 问题 |
|---|---|---|
| P3-119 | pages/download/download_controller.dart:1000-1004, 358-361; repositories/download_repository.dart:46,245,178-186 | 死代码：`completedCount`（UI 另算一份）、`getEpisodeByUrl` 及接口、`getEpisodeWithProgress`（已全局 grep 确认） |

---

## 五、测试套件审查（6 条问题 + 覆盖缺口）

### 问题

| 级别 | 位置 | 问题 |
|---|---|---|
| P1 | test/cycani_danmaku_test.dart:62 | `if (hasDandanCredentials) return;` CI 中凭据必注入 → **空转返回报绿色 pass**（应改 `skip:`） |
| P1 | test/catalog_ui_consistency_test.dart:338-341 | 依赖 `CATALOG_UI_PREVIEW` 环境变量，无人设置时**零断言 pass**（手工截图生成器混入常规测试） |
| P3 | test/async_rate_limiter_test.dart:12,30,51,72 | 墙钟 Stopwatch 毫秒断言（`lessThan(30)`/`greaterThanOrEqualTo(35)`）CI 高负载即假失败，余量仅 5ms |
| P3 | test/cycani_api_chain_probe_test.dart:275-283 | 即便 opt-in 运行，最终断言只要求"每站至少一条链路成功"，其余几十条失败仅打印——作回归门禁时大部分链路已坏仍绿 |
| P3 | test/cycani_live_test.dart:61-65 | `expect(statusCode, 206); if (statusCode != 206) throw ...` 后半永不可达（冗余死断言） |
| P3 | test/catalog_account_widgets_test.dart:11-24 | cooldown.dispose() 在最后一个 expect 之后：断言失败时 timer 泄漏到同文件后续用例 |

### 核查无问题的方面

- Mock 签名匹配：抽查 site_accounts/aggregator/cycani_api/remote danmaku/giri/webdav/hive 全部一致；noSuchMethod 兜底的 mock 意外调用响亮失败
- 无未 await 假通过；每文件独立 isolate + setUp/tearDownAll 重置；共享状态污染防护良好（bangumi_sync_service_test、cycani_source_sync_test 是防污染正面样本）
- 非 live 测试确无真实网络；live 测试全部环境变量门控且诚实标注

### 覆盖缺口（高风险零覆盖）

| 模块 | 现状 | 风险 |
|---|---|---|
| services/download/download_manager.dart（985 行）、background_download_service、download_directory_service、repositories/download_repository、download_controller（测试中仅 noSuchMethod 空壳） | 仅 download_path_migration 有测试 | **高** |
| utils/m3u8_ad_filter.dart（广告分段识别，直接决定下载产物） | 零测试 | **高**（纯函数易测，补测性价比最高） |
| pages/player/player_controller.dart（505 行）+ controller/ 各控制器 + syncplay_client.dart（951 行协议）+ history_playback/external_player/audio_controller/screenshot_export | 仅 danmaku controller 部分、timed_shutdown、syncplay_endpoint（仅字符串解析）有测试 | **高** |
| services/video_source/（resolver pool、webview 解析服务） | 零测试 | **高**（播放可用性核心链路） |
| services/sync/webdav.dart 的 syncHistory/syncCollectibles（历史+收藏备份主体） | 仅 setEnabled/init 失败/弹幕屏蔽词有测试 | **高**（已有 _MemoryWebDavClient 可复用） |
| request/core/ech_transport、ech_adapter、acceleration_interceptors | 零直接测试 | 中高 |
| 插件运行时（plugin_search_service/validity_tracker/cookie_manager/captcha_verification_service）、plugin_site_client、rules_repo_client、plugin_catalog_api、trace_api | 零测试（rule_engine/api_rule_engine/xpath/import_parser 已良好覆盖） | 中高 |
| request/apis/bangumi_api + bangumi_client | 仅 buildBangumiSearchParams 有测试 | 中 |
| services/network/（proxy_manager/system_proxy/metered_network/rules_mirror/proxy_aware_image_cache） | 零测试 | 中 |
| 弹弹play 客户端（danmaku_client/danmaku_api） | 仅凭据缺失 guard（即 P1 假通过那条） | 中 |
| 页面控制器（video_controller 1111 行/info/search/timeline/history/my/collect） | 基本零覆盖 | 中 |
| services/update/（涉及下载执行更新包）、webview/、deep_links、bbcode、shaders、platform/*、utils 杂项 | 零测试 | 中低 |

**覆盖良好正面清单**：历史同步全链（merger/codec/service/repository）、收藏同步（merger/plan）、bangumi_sync_service、弹幕屏蔽词 WebDAV 同步、三站聚合（离线 fixture+合并规则）、弹幕多路合并管线、cycani_api 认证/401 单飞/分页、site_accounts 会话竞态、对话框系统、插件规则引擎、m3u8 parser、episode_url、search_parser。

---

## 六、确认无问题重点疑点（正面结论）

1. **三站会话存储**：token/cookie 均存 FlutterSecureStorage；`_writeSession` 串行化队列 + epoch 双重校验（site_accounts.dart:106-133）正确防旧会话写回（含 logout 与 in-flight refresh 竞态）；`CatalogHttp` 跨域拦截器把 cookie/CSRF 严格限制在各自 origin（catalog_http.dart:36-52）
2. **播放控制器并发链路**：`AsyncSessionOwner` + `canInstall` + 每原子操作后 `isCurrentPlayer` 复查 + `_OwnedPlayer._disposeFuture` 幂等 dispose，是全项目质量最高的部分；`PlaybackCachePolicy`/弹幕发送时间轴 offset 方向分析自洽
3. **深链安全**：scheme 白名单、Bangumi ID 仅纯数字且 `'$id'==raw` 拒前导零/符号、search query 经 Uri 编码，无注入面
4. **更新安全**：SHA-256 强校验 + 临时目录内验证后 rename；校验失败即弃
5. **历史同步**：history_sync.dart 933 行——`padLeft(16)` 毫秒+eventId 字典序、clear 墓碑、LWW、有界归并均自洽无丢事件
6. **Hive 层**：typeId 0-8 全局唯一无冲突；6 个 .g.dart 与手写注解逐字段一致；`Hive.registerAdapters()` 先于所有 openBox；main → GStorage.init → ModularApp 顺序无依赖倒置；CollectType/BangumiCollectionType 全部经 collect_type_mapper 显式映射；站点负 ID 条目被 bangumi_sync_service.dart:138 `bangumiId<=0` 正确排除出 Bangumi 同步
7. **磁盘缓存**：catalog_disk_cache 同 key 写串行化、temp+rename 原子替换、三重限制正确；搜索 key 经 sha256 哈希成文件名安全
8. **其他**：xifan/giri 1e9/2e9 偏移在 site_native_catalog.dart:313/407 与 catalogDanmakuIds 过滤间一致；`CatalogVideo.id` 三站均正数（负 ID 仅在 toBangumi/SiteEntry 层）故 `_tile` 守卫不误伤；bangumi_relation BFS 有 fetchCount/maxDepth 双上限；弹幕屏蔽词墓碑同步正确；`onReorderItem` fork 版已在框架侧修正 newIndex

---

## 七、结构性债务与建议

1. **先决断 8 个未挂载模块 + 孤儿 onboarding**（P1-1）：是"待接线"还是"废料"。这是当前最大功能性问题源头：3 个存活死链 + 插件编辑器不可达 + 同步配置 UI 锁死。若裁剪，须连同后台消费键（webDavEnable/autoUpdate/checkPluginUpdateOnStartup/defaultStartupPage/showRating）、`_categoryPath` 死分支、旧版 MyPage 一并清理，否则留下"后台逻辑活着但 UI 永远配不了"的暗功能
2. **统一身份方案**：负 ID 双轨制（giri/xifan 与 cycani 共用负 ID 空间撞号 + `toBangumi` 硬编码 cycani 前缀，见 P3-6/P2 组 catalog_identity 条目）是 docs/ 两代审计都点名的深层债务。当前靠"所有卡片覆写 onTap + 持久化只用带偏移的详情行"纯约定式安全；建议以 `(CatalogSource, rawId)` 二元组贯穿全链路，解码收口一个函数
3. **docs/ 已滞后一代**：4 份审计仍引用 `cycani_catalog_sources.dart`、`cycani_home_page.dart` 等旧文件名（代码已完成改名重构与 11-07 整改），A1-A7/B1-B4/C1-C3 重复项部分已整改。建议生成新一版或标注失效
4. **修复优先级 Top 5**：
   ① P1-1 路由死链（决断裁剪或接线）
   ② P1-3 批量移动 int.parse（一行修复）
   ③ P1-17/18 下载 206 校验 + enqueuePriority 并发 tmp（数据损坏类）
   ④ P1-19/20 WebDAV 备份竞态 + 收藏变更 ID 撞号（数据丢失类）
   ⑤ P1-5/8/9/10/11 BBCode 与评论渲染崩溃组（远程内容可触发，高频可见）
   次优先：P1-13/14 SyncPlay 协议两处、P1-7 m3u8 query、P1-6 季度差一、P1-22 代理证书、P2-29 openBox 无差别删数据

---

## 附录：已通读且无发现 contradict 的文件清单（按模块）

- **cycani**：catalog_action、catalog_snapshot、catalog_plugins、catalog_navigation（本身）、catalog_lru、catalog_read_retry、catalog_disk_cache、cycani_api 主体（401 单飞/分页/https 校验/快照串行写）、cycani_detail_page 主体、catalog_detail_page 主体（缓存失效/竞态防护/8s 超时兜底）、cycani_auth_page、cycani_profile_settings、cycani_account_stats、qingyue_space_view、catalog_detail_metadata、site_comments（去重/游标环/重试/快照 canApply）、catalog_search_page（generation 防护）、catalog_week_selector 主体、danmaku_cache/codec/options/source_settings/dialog、giri_danmaku（CDN 双解析竞态/URL 校验）、giri_collections、playback_danmaku/discussion/resolvers、catalog_comments、comment_widgets/comment_date、feed_widgets（ScrollPosition 增删对称）、account_layout/account_widgets、xifan_challenge、read_retry
- **services/player**：low_memory_mode、playback_cache_policy（identical 校验）、player_error_mapper、screenshot_candidate/export_service/image_cache、syncplay_endpoint（IPv6/端口校验）、external_player、external_playback_launcher、history_playback_service
- **services**：download_path_migration、plugin 引擎主体（api_rule_engine/import_parser/cookie_manager/search_service/validity_tracker/xpath_strategy/captcha_verification——收尾单飞设计正确）、history_storage_coordinator、history_sync_service、danmaku_shield_sync_service、webdav_remote_file_commit、startup_update_check、update_download_source/update_downloader、acceleration_mode、bangumi_acceleration、bangumi_image_url_rewriter、ech_http_licenses、image_acceleration、image_file_response、metered_network_service、proxy_aware_image_cache_manager、proxy_manager、proxy_utils、rules_mirror、app_exit、desktop_window_config、platform_environment_service、player_menu_service、tray_service、webview_feature_service、windows_shortcut、app_deep_links、kazumi_deep_link、system_proxy_service FFI 主体、AsyncSession/AsyncSerialQueue/AsyncSingleFlight/RateLimiter 原语本体
- **pages/player**：transport_bar、pointer_interaction、item_surface、player_controller 主体、keyboard_shortcuts 主体、adjustment_hud、feedback_overlay、screenshot_controls/image、destination_sheet、video_details_sheet、player_models、panel_controller、super_resolution、aspect_ratio、screenshot_controller、debug_controller 订阅管理、全部 6 个 .g.dart
- **pages**：info_module、info_actions_menu、character_info_view/page、info_page、rating_review_dialog、source_alias_dialog、source_sheet_view、video_controller.g、video_module、video_playback_args、video_page_layout、video_system_bars、player_content_tabs、video_side_panel、episode_selection_panel、video_page、search_controller.g、search_widgets、image_search_page、collect_controller.g、collect_library_card/query/controls、collect_module、settings_module、decoder/renderer/super_resolution/storage/download/low_memory/keyboard_settings、danmaku_module/sheet/ch_convert/shield 全族/time_offset、sync_settings_widgets、bangumi_sync_page、proxy_module、plugin_shop_page、editor_form_widgets、rule_management_widgets、plugin_update_actions、plugin_catalog_view、history/ 全部 7 文件、my_page 主体/my_space_view/my_module、timeline_page 主体/timeline_week_selector/timeline_module、onboarding/ 全部 6 文件、download_page/widgets/page_module、about/ 全部、menu/ 全部、storage_error_page
- **bean/modules**：appbar 2 文件、character_card、network_img_layer（BoxFit/hero shuttle/三态完备）、palette_card、rule_card、staff_card、user_comments_card（didUpdateWidget 复位）、adaptive_bottom_sheet、dialog.dart（handle 单次/toast revision 严密）、dialog_helper/dialog_task、exit_confirmation_dialog、dialog_helper、material_bottom_sheet、update_available_dialog、bean/settings 6 文件、bean/widget 18 文件（image_preview 全 controller 释放等）、bangumi_collection_type/collection/interest/tag(+g)/relation/review/episode_item/sync_priority、character_full_item/actor_item/characters_response、collect_layout/sync_plan/type/type_mapper、danmaku_ch_convert/search_response/shield_rule/shield_sync、download_module.g、history_module(+g)、watch_stats、plugin_http_module、road_module、image_search_module、plugin_search_module、search_history_module.g
- **request/utils**：network_exception、dio_logger_interceptor、download_http_client、plugin_site_client、rules_repo_client、trace_client、bangumi_client、danmaku_client（敏感头剥离设计正确）、async_* 原语、episode_url、encoding、file_system、http_headers、image_extension、m3u8_ad_filter（启发式本身合理）、danmaku.dart、theme、device、bangumi_mirror_credentials、dandan_credentials、constants、collect_crud_repository、danmaku_shield_repository（崩溃自愈设计正确）、history_repository、search_history_repository、dio_factory、collect_layout_switch（三处引用一致）
- **webview/plugins/bbcode**：api_rule_config、anti_crawler_config、plugins_controller.g、bbcode_elements、BBCodeListener、video_webview_controller 本体、video_webview_windows_impl（订阅生命周期正确）、app_module、core_module、navigation、hive_registrar.g
