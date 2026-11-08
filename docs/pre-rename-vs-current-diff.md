# 旧备份 vs 当前代码 全面差异报告

- 对比日期：2026-11-08
- 对比对象：`.snapshot-pre-rename/`（2026-11-07 22:51，包名改名前的完整备份）vs 当前 `lib/`、`test/`、`pubspec.yaml`
- 方法：按「机械改名映射表」把旧文件中的旧标识符（`CycaniJson→CatalogJson` 等）归一化后逐行 diff；归一化后剩余的差异即为**真实改动**。工具脚本与映射表存于临时目录（`rename-map.sed` / `cmp_snap.sh`）。

---

## 一、总览

| 类别 | 数量 | 说明 |
|---|---|---|
| lib 配对成功 | 420 个文件 | |
| ├ 纯改名 / 完全一致 | 414 个 | 机械改名归一化后逐字节一致 |
| ├ **有真实差异** | **39 个** | 归一化后剩余 2~280 行，见第三节 |
| 只在旧备份 | 6 个 | 5 个为改名（见改名表），1 个真删除 |
| 只在当前 | 7 个 | 5 个对应上面改名 + 2 个新文件 |
| pubspec.yaml | 零差异 | |
| test/ | 31 个有差异 | 同步新类名/设置键名为主；删 1、增 1 |

### 文件改名映射（旧 → 现）

| 旧文件名 | 现文件名 |
|---|---|
| `cycani_home_page.dart` | `qingyue_home_page.dart` |
| `cycani_my_page.dart` | `qingyue_my_page.dart` |
| `cycani_space_view.dart` | `qingyue_space_view.dart` |
| `cycani_search_page.dart` | `catalog_search_page.dart` |
| `cycani_avatar_store.dart` | `catalog_avatar_store.dart` |
| `cycani_source_accounts.dart` | `site_accounts.dart` |
| `cycani_catalog_sources.dart` | `catalog_aggregator.dart` |
| `cycani_catalog_disk_cache.dart` | `catalog_disk_cache.dart` |
| `cycani_catalog_detail_page.dart` | `catalog_detail_page.dart` |
| `cycani_week_selector.dart` | `catalog_week_selector.dart` |
| `cycani_paging.dart` | `catalog_paging.dart` |
| `cycani_feed_widgets.dart` | `catalog_feed_widgets.dart` |
| `cycani_models.dart` | `catalog_models.dart` |
| `cycani_read_retry.dart` | `catalog_read_retry.dart` |
| `cycani_giri_collections.dart` | `giri_collections.dart` |
| `cycani_giri_danmaku.dart` | `giri_danmaku.dart` |
| `cycani_native_catalog.dart` | `site_native_catalog.dart` |
| `cycani_source_comments.dart` | `site_comments.dart` |
| `cycani_xifan_challenge.dart` | `xifan_challenge.dart` |

主要标识符改名（逻辑不变）：`CycaniJson→CatalogJson`、`CycaniVideo→CatalogVideo`、`CycaniFeed→CatalogFeed`、`CycaniPage→CatalogPage`、`CycaniCatalogSources→CatalogAggregator`、`CycaniVideoSliver→CatalogVideoSliver`、`CycaniLoadMore→CatalogFeedLoadMore`、`CycaniWeekSelector→CatalogWeekSelector`、`CycaniError→CatalogError`、`CycaniEpisodes→CatalogEpisodes`、`CycaniDanmakuOptions→CatalogDanmakuOptions`（及 Loader/Dialog/SourceSettings 同前缀）、`CycaniBootstrap/HomePage/MyPage→Qingyue*`、`CycaniDestination→QingyueDestination`、`CycaniSpaceView→QingyueSpaceView`、`CycaniSearchPage→CatalogSearchPage`、`CycaniAvatarStore→CatalogAvatarStore`、`cycaniMap/Int/List→catalog*`、`cycaniToast→catalogToast`、`cycaniConfirm→catalogConfirm`、路由 `'/cycani/detail'→'/qingyue/detail'`。`CycaniApi`、`CycaniAvatar`、`CycaniAccountStats`、`cycani_api.dart` 等保持原名。

### 删除与新增

- 真删除：`features/cycani/cycani_home_overview.dart`（首页 overview 聚合卡组件）、`test/cycani_home_overview_test.dart`
- 真新增：`features/cycani/catalog_library.dart`（三站合并库）、`lib/bean/widget/collect_layout_switch.dart`（公共布局切换按钮）、`test/catalog_connection_live_test.dart`（TLS 回归）

---

## 二、真实差异总表（39 个文件，按归一化后剩余行数排序）

| 剩余行数 | 文件（旧 → 现） | 主题 |
|---:|---|---|
| 280 | `cycani_home_page.dart → qingyue_home_page.dart` | 三站聚合 + 周表网格 + 评分角标 |
| 126 | `cycani_catalog_sources.dart → catalog_aggregator.dart` | 聚合数据层 |
| 59 | `pages/collect/collect_library_controls.dart` | 切换按钮提取 |
| 53 | `pages/timeline/timeline_page.dart` | 时间表页切换按钮 + 海报墙 |
| 49 | `cycani_comments.dart → catalog_comments.dart` | 评论门面合一 |
| 47 | `bean/card/bangumi_timeline_card.dart` | RatingBadge 组件 |
| 25 | `services/storage/settings_keys.dart` | 弹幕设置键中性化 |
| 22 | `cycani_playback_discussion.dart → catalog_playback_discussion.dart` | 评论门面调用点 |
| 22 | `cycani_danmaku_source_settings.dart → catalog_danmaku_source_settings.dart` | 弹幕设置键 |
| 21 | `services/network/catalog_image_url.dart` | 图片双节点代理 |
| 16 | `cycani_danmaku_loader.dart → catalog_danmaku_loader.dart` | 类名改名 |
| 16 | `cycani_danmaku_options.dart → catalog_danmaku_options.dart` | 弹幕设置键 |
| 15 | `cycani_source_accounts.dart → site_accounts.dart` | 会话写队列超时保护 |
| 14 | `cycani_detail_page.dart`（同名） | 评论门面调用点 |
| 14 | `cycani_playback_danmaku.dart → catalog_playback_danmaku.dart` | 类名改名 |
| 14 | `features/cycani/catalog_connection.dart` | TLS 修复 |
| 13 | `catalog_playback_resolvers.dart` | 稀饭 #src=K 解析 |
| 11 | `cycani_catalog_detail_page.dart → catalog_detail_page.dart` | 评论门面调用点 |
| 10 | `pages/player/controller/player_danmaku_controller.dart` | 类名改名 |
| 9 | `services/network/image_file_service.dart` | 双节点轮询 |
| 8 | `cycani_danmaku_dialog.dart → catalog_danmaku_dialog.dart` | 类名改名 |
| 8 | `cycani_my_page.dart → qingyue_my_page.dart` | 收藏/历史路由收口 |
| 8 | `pages/video/video_controller.dart` | 类名改名 |
| 6 | `pages/player/player_item.dart` | 类名改名 |
| 6 | `cycani_models.dart → catalog_models.dart` | metaTags air 字段 + 类名 |
| 6 | `cycani_remote_danmaku.dart`（同名） | 类名改名 |
| 6 | `features/cycani/cycani_api.dart`（同名） | 类名改名 |
| 4 | `cycani_space_view.dart → qingyue_space_view.dart` | 品牌命名 |
| 4 | `cycani_feed_widgets.dart → catalog_feed_widgets.dart` | 网格行高 42→52 |
| 4 | `request/apis/danmaku_api.dart` | 类名改名 |
| 4 | `pages/settings/settings_page.dart` | 品牌 `/cycani→/qingyue` |
| 4 | `pages/settings/danmaku/danmaku_settings_sheet.dart` | 类名改名 |
| 4 | `pages/settings/danmaku/danmaku_settings.dart` | 类名改名 |
| 4 | `features/cycani/cycani_profile_settings.dart` | `CycaniAboutPage→QingyueAboutPage` |
| 3 | `pages/collect/collect_library_view.dart` | 改用公共切换组件 |
| 2 | `pages/settings/settings_module.dart` | About 路由 |
| 2 | `pages/video/video_page.dart` | import 改名 |
| 2 | `app_widget.dart` | 窗口标题 次元城→青月次元 |
| 2 | `pages/index_module.dart` | 路由 `/cycani→/qingyue` |

---

## 三、真实差异详述（按主题）

### ① 品牌：次元城 → 青月次元（6 处，无功能影响）

| 文件 | 旧 | 现 |
|---|---|---|
| `app_widget.dart:285` | `title: "次元城"` | `title: "青月次元"` |
| `pages/index_module.dart:35` | 路由 `'/cycani'` | 路由 `'/qingyue'` |
| `pages/settings/settings_page.dart:181,257` | `context.navigate('/cycani')` | `context.navigate('/qingyue')` |
| `pages/settings/settings_module.dart:42` | `CycaniAboutPage` | `QingyueAboutPage` |
| `cycani_profile_settings.dart:309` | `class CycaniAboutPage` | `class QingyueAboutPage` |
| `cycani_space_view.dart:635` | `CycaniSettingsButton` | `QingyueSettingsButton` |

### ② 三站聚合（tab4/5 收藏历史 + 首页数据层）

**`qingyue_home_page.dart`（280 行真实差异）**

- tab4 追番 / tab5 历史：旧版只调次元城账号 API（`api.favorites(category,page)` / `api.histories(cursor)`，支持分页，加载后 `api.saveLibrarySnapshot(...)` 存快照）；现版改 `CatalogLibrarySource().load()` 一次合并三站已登录账号数据（不分页，行内带 `entry` + `progress`）。
- 收藏管理：旧版 `selected` 为数字 id 集合，`api.moveFavorites/removeFavorites/removeHistories` 直接写次元城；现版 `selected` 为 `entry.identity` 字符串，`_selectedEntries()` 按 `entry.source` 路由，仅对次元城源执行 `CatalogLibrarySource.writeFollow(entry, …)` / `deleteHistory(entry)`。
- 卡片 tile 新增：评分角标 `RatingBadge`（`score>0 && !(tab4/5 && listMode)` 时右上角）、tab4 来源角标（`entry.source.label` 左下角）、tab5 副标题优先 `entry?.subtitle`（带站点/进度信息）；`entry` 存在时点击改开 `CatalogDetailPage(row)`；搜索过滤优先匹配 `entry.title`。
- tab3 周表：新增 `weekGridMode` 字段与网格/列表切换（网格模式 `tileBuilder` 用 `_tile` 渲染海报卡）。
- 首页 tab0 移除板块：`layout=='overview'`（CycaniHomeOverview 聚合卡）、`layout=='categories'`（分类入口）、`layout=='quotes'`（giri 语录 PageView）、`layout=='calendar'`（`_giriHomeCalendar` + `_giriHomeDay/_giriHomeWeeks`）；`_giriRecommendationSliver` 改名 `_personalizedSliver`；`_giriHomeAccount` 改名 `_accountHomeSections`；`_homeRevision` 机制移除。
- 文案：`清空云历史→清空次元城历史`、`清空服务器上的全部观看历史？→清空次元城服务器上的全部观看历史？`

**`catalog_aggregator.dart`（126 行）**

- 稀饭行补 `'area': row['region']`；giri 行补 `'area': row['vod_area']`、`'air': row['vod_time'] ?? row['vod_remarks']`（周表行是 vod_time，分类行是 vod_remarks）。
- 稀饭 fields 列表追加 `region`。
- 移除：`{'name':'','layout':'overview'}` 组、`giriQuotes()`（`/Vod/famousList` 台词）及其调用、`追番日历` section 与 `'layout':'calendar'` 标记、`index==3` 的 categories 组（giriKinds 入口）。
- 新增 `_ensureGiriScores()`：按当年 `/Vod/get_list`（每页 50、最多 1000 条）建 `vod_id→vod_score` 索引，按天内存缓存 + 按 `giri-score-index:年` 磁盘缓存；`schedule(giri)` 注入 `row['score']`（修复 giri 周表暂无评分）。
- import：`cycani_read_retry→catalog_read_retry`、新增 `dart:async`（磁盘缓存异步写）。

**`catalog_library.dart`（新增文件）**：三站合并库，`CatalogLibraryEntry {source, rawId, title, cover, raw, subtitle, followStatus}`，`CatalogLibrarySource.load()` 合并所有已登录站收藏/历史，`writeFollow/deleteHistory` 按行路由到所属站点适配器。

**`qingyue_my_page.dart`（8 行）**：收藏/历史入口一律 `widget.openLibrary(4/5)`；`_externalPage()` 不再带 `library` 参数（旧版外部账号模式跳 `SourceAccountsPage(initialGiri:, library:)` 定位到对应库）。

**评论门面合一（一2）**

- `catalog_comments.dart`（49 行）：`CycaniComments`（StatefulWidget，仅次元城）→ `CatalogComments`（StatelessWidget 门面，`source` 字段分发：cycani → 内部 `_CycaniCommentsView`（原实现），其余 → `SourceComments`（giri/xifan））。
- 三个调用点统一走门面：`catalog_detail_page.dart`（`SourceComments(giri:)` → `CatalogComments(source:)`）、`cycani_detail_page.dart`（`CycaniComments(videoId:)` → `CatalogComments(source: CatalogSource.cycani, …)`）、`catalog_playback_discussion.dart`（if/else 双分支 → 单一门面调用）。

### ③ 稀饭播放修复（CDN "sign invalid"）

**`site_native_catalog.dart`（121 行，由 `cycani_native_catalog.dart` 改名）**

- `xifanPlayback(anime, episode)` → 增加 `preferCandidate` 参数：主地址与全部 `candidates` 依次做 ranged GET 探活（`_streams`，5 秒连接超时，200/206 视为可用），取第一个真正出流的节点；全部失败回退首个可用地址。移除对播放地址 `hasFragment` 的拒绝校验（线路页地址现在带 `#src=K` 片段）。
- `_fetchDetail` 稀饭：向 `/functions/v1/issue-web-playback`（action=fallback）问一次首集，拿候选源数量与 `source_name`；第 k+1 个候选源各生成一条线路 Road（集地址带 `#src=$k`），拿不到时退回单线路。

**`catalog_playback_resolvers.dart`（13 行）**：解析页面地址 fragment `#src=K` → `preferCandidate: K`。

### ④ 图片加速（百度 gimg 双节点）

- `catalog_image_url.dart`（21 行）：`proxy()` 由单节点 `gimg1`（`Uri.encodeComponent` 编码 src）改为 `proxies()` 返回 `[gimg1, gimg2]` 两个独立缓存节点（src 用原始 `host+path`，不编码——编码形式会返回无效图片）。
- `image_file_service.dart`（9 行）：百度分支由"单代理失败即回退直连"改为循环尝试两个节点后再回退直连。

### ⑤ 网络层 TLS 修复（当时全站 400 的根因）

- `catalog_connection.dart`（14 行）：自定义 `connectionFactory` 拿到的是明文 socket（SDK 的 `http_impl.dart` 只在默认路径用 `SecureSocket.startConnect`），现版在 factory 内对 `https` 执行 `SecureSocket.secure(socket, host: host)` 升级（保留主机名做 SNI 与证书校验，socket 仍钉在已解析地址）；升级前若 completer 已完成则销毁 socket。

### ⑥ 评分显示

- `bangumi_timeline_card.dart`（47 行）：新增公共 `RatingBadge`（胶囊评分角标，`compact` 变体，`score<=0` 渲染灰字"暂无评分"），`_buildRating` 委托实现；供时间卡与网格浮层共用。
- `catalog_models.dart`（6 行）：`CatalogVideo.toBangumi()` 的 `metaTags` 首位插入 `air`（更新至 X 集）字符串；`CycaniEpisodes→CatalogEpisodes`。
- `catalog_feed_widgets.dart`（4 行）：网格行高 `textScaler.scale(42)→scale(52)`（适配两行标题）；`CatalogFeedLoadMore` 注释更新。

### ⑦ 布局切换按钮（公共组件）

- `lib/bean/widget/collect_layout_switch.dart`（新增）：追番页同款网格/列表胶囊切换按钮（`CollectLayoutSwitch`）。
- `collect_library_controls.dart`（59 行）：原私有 `_CollectLayoutSwitch` 类移除（提取为公共组件）；`collect_library_view.dart`（3 行）：调用点改公共名 + import。
- `timeline_page.dart`（53 行）：AppBar actions 右侧（筛选按钮旁）加 `CollectLayoutSwitch`，`_layout` 状态（默认 list），`_buildDay` 增加 `CollectLayout.cards` 海报墙分支（`_posterGrid`：列数 3/5/6、行高 `(width-(n-1)*间距)/n/.65+scale(52)`，`BangumiCardV` 关 Hero），PageStorageKey 按布局区分。

### ⑧ 弹幕设置键中性化（一5，磁盘名保留兼容）

`settings_keys.dart`（25 行）5 个键的 Dart 名（磁盘存储名不变，老设置不丢）：

| 旧 Dart 名 | 现 Dart 名 |
|---|---|
| `cycaniExternalDanmaku` | `danmakuSourceExternal` |
| `cycaniXifanDanmaku` | `danmakuSourceXifan` |
| `cycaniSiteDanmaku` | `danmakuSourceCycani` |
| `giriSiteDanmaku` | `danmakuSourceGiri` |
| `giriExternalDanmaku` | `danmakuSourceGiriExternal` |

`catalog_danmaku_options.dart`（16 行）`read()` 工厂改读新键名；`catalog_danmaku_source_settings.dart`（22 行）设置项列表改新键名。其余 8 个文件（`catalog_danmaku_loader/playback_danmaku/dialog`、`cycani_remote_danmaku`、`player_item`、`video_controller`、`video_page`、`player_danmaku_controller`、`request/apis/danmaku_api.dart`、两处弹幕设置页）为 `CycaniDanmaku*→CatalogDanmaku*` 类名与 import 改名，逻辑不变。

### ⑨ 账号会话稳定性

`site_accounts.dart`（15 行，由 `cycani_source_accounts.dart` 改名）：`_xOptions` 与 `_checkGiriSession` 两处 `await _sessionWrites` 改为 2 秒超时保护（超时打 `KazumiLogger().w` 警告继续读），防写队列卡死拖住会话读取；新增 logger import。

### ⑩ test/ 差异（31 个文件）

- 主因为同步上述改名与新设置键名（danmaku merge/settings 系列、paging、catalog_sources、playback_danmaku 等），以及评论门面、image 双节点（`catalog_image_transport_test` 双 gimg 期望）、新门面构造参数等。
- 删除：`test/cycani_home_overview_test.dart`（对应组件删除）。
- 新增：`test/catalog_connection_live_test.dart`（TLS 升级回归，`CATALOG_TLS_LIVE=1` 门控）。

---

## 四、结论

414 个文件仅为改名归一；39 个文件的实际改动集中在七件事：**三站聚合（收藏/历史合并、评论门面、聚合数据层字段与板块调整）、稀饭播放候选探测、图片 gimg 双节点、TLS 连接升级、评分显示（RatingBadge + giri 周表评分索引 + air 字段）、弹幕设置键中性化、会话写队列超时保护**，外加品牌更名 6 处与今天的布局切换按钮 3 处。`pubspec.yaml` 无变化；Android 工程与签名配置不在本次对比范围（备份未包含 android/）。
