# 青月次元（三站聚合）全量代码复审：复用清单与不对称点

> 复审日期：2026-11-04。目标形态：**三站对等聚合**的"青月次元"——次元城 / 稀饭 / GiriGiri 三个站地位平等，不允许出现"次元城一个、稀饭/Giri 一个"式的成对实现。
> 复审范围：全仓库（`lib/features/cycani/` 34 文件 12,500 行 + 全部宿主集成 + 播放器 + 设置 + 路由 + 品牌资源）。
> 方法：在前四轮全量通读基础上，本轮用 grep 对"站点特判 / 品牌字样 / 身份锚点 / 命名"做全量枚举定量。
> 口径：**"复用"= 方法/组件已按 `CatalogSource` 参数化或天然与站点无关，改个名就能继续用；"特判"= 代码里硬编码了"次元城优先"的分支，聚合前必须拉平。** 本报告只审计不动代码。

---

## 一、总体结论

1. **数据与聚合层已经高度 `CatalogSource` 参数化**——`CatalogSource` 枚举贯穿搜索/浏览/周表/弹幕合并/详情合并，这部分是三站聚合的现成地基，**复用度很高**（估计占 cycani 模块 6 成以上）
2. **不对称集中在 9 个层面**（见第四节）：身份体系、会话/账号、首页布局、评论 UI、追番/历史、弹幕通路、播放解析识别、设置/存储键命名、路由与品牌
3. 定量：`CatalogSource.cycani` 特判 **26 处**；含 `Cycani` 字样的文件 **43 个**；lib 内"次元城"品牌字样 **27 处**（另 AndroidManifest 1 处、pubspec 2 处）；以 cycani/giri 命名的设置键 **5 个**、存储键前缀 **4 组**
4. 最深的一处不对称是**身份体系双轨制**：次元城条目用"负 ID + `cycani:` 前缀"方案，稀饭/Giri 用"1e9/2e9 偏移"方案——两套身份解码散布在 4 个文件里，聚合必须先统一

---

## 二、可直接复用的通用层（方法级清单，改名即用）

以下符号内部逻辑已是三站对等或与站点无关，是青月次元的核心资产：

### 2.1 目录聚合（复用度最高）
| 现有符号 | 位置 | 职责 | 复用说明 |
|---|---|---|---|
| `CatalogSource` 枚举（cycani/xifan/giri + `label` + `detail(id)`） | cycani_catalog_sources.dart:13-25 | 站点身份的唯一权威 | 直接复用；`cycani` 是站点名不是 App 名，保留 |
| `mergeCatalogRows(input)` | :58-160 | 三站结果合并（Bangumi ID 主键 + 别名连通分量 + 站点唯一性校验） | 直接复用，聚合核心算法 |
| `catalogRowKey(row)` / `catalogSource(row)` | :27-33 | 行身份键 | 直接复用 |
| `catalogDanmakuIds(members, selected)` | :37-54 | 从合并组提取各站 ID（歧义不选） | 直接复用 |
| `CycaniCatalogSources.search/searchSource` | :994-1096 | 三站并行搜索 + 快照缓存 | 直接复用（内部 `_row()` 已做字段归一） |
| `browse(source, page, ...)` | :679-775 | 三站分类浏览（含各自筛选器映射） | 直接复用 |
| `schedule(source, day)` / `mergedSchedule(day)` | :929-992 | 三站周表单站/合并 | 直接复用 |
| `ranking(source, movie:)` | :848-896 | 三站排行统一入口 | 直接复用（注意：生产代码目前没在用它，见复用审计 A3） |
| `xifanRankingIds / xifanWeeklyRanking / xifanHomeSections / giriRankingGroups / giriBrowseFilters` | :815-846, :264-313, :777-813, :634-677 | 各站特有数据源适配 | 保留为站点适配器 |
| `giriKinds / xifanKinds / xifanTags` | :591-632 | 各站筛选字典 | 保留为适配器常量 |

### 2.2 数据模型与分页
| 现有符号 | 位置 | 复用说明 |
|---|---|---|
| `CycaniJson` 及 `cycaniMap/cycaniList/cycaniInt/cycaniUniqueLabels` | cycani_models.dart:4-28 | 通用 JSON 助手，直接复用（改名去 cycani） |
| `CycaniVideo`（JSON 包装 + `toBangumi()` 归一卡片模型） | :30-67 | 直接复用；`toBangumi()` 的身份方案需按第四节 4.1 调整 |
| `CycaniEpisodes.toRoad()` | :69-88 | 直接复用 |
| `CycaniPage / CycaniFeed` | cycani_paging.dart | 通用追加分页（generation 防串台/去重/cursor），直接复用 |
| `CatalogDiskCache` | cycani_catalog_disk_cache.dart | 公开数据磁盘缓存（sha256 键/7 天/200 文件/写队列），直接复用 |
| `retryPublicCatalogRead` | cycani_read_retry.dart | 只读重试，直接复用 |

### 2.3 弹幕
| 现有符号 | 位置 | 复用说明 |
|---|---|---|
| `CycaniDanmakuLoader.loadCombined(...)` | cycani_danmaku_loader.dart:12-85 | **五路并行合并框架**，直接复用（站点路数作为参数传入，本身不知道站点） |
| `CycaniDanmakuLoader.parse(items)` | :124-153 | 站内弹幕 JSON→DanmakuEntry 解析，可复用为通用解析器 |
| `CatalogPlaybackDanmaku` | cycani_playback_danmaku.dart:44-172 | 按 source 分发的弹幕装配器，直接复用（内部 `_section()/_xifan()/_giriUrl()` 是适配器调用） |
| `catalogEpisodeNumber / catalogEpisodeUrl` | :15-42 | 严格集数匹配（拒绝猜测），直接复用 |
| `CycaniRemoteDanmaku`（稀饭弹幕+外部中继）、`GiriDanmakuApi`（Giri 站内/外部 XML） | cycani_remote_danmaku.dart / cycani_giri_danmaku.dart | 保留为站点适配器 |
| `CycaniDanmakuDialog` | cycani_danmaku_dialog.dart | 三站共用的发送对话框（`send` 回调注入），直接复用 |

### 2.4 详情与讨论
| 现有符号 | 位置 | 复用说明 |
|---|---|---|
| `CatalogDetailScroll / CatalogDetailHeader / CatalogPoster / CatalogSynopsis / CatalogEpisodePicker` | cycani_detail_page.dart:486-668 | 详情页骨架组件，两套详情页已在共用，直接复用 |
| `CatalogDiscussionTarget`（含 `fromPlayback` 身份解析 + `send` 三站分发） | cycani_playback_discussion.dart:11-87 | 直接复用（`fromPlayback` 的字符串身份判断需按 4.1 调整） |
| `CatalogPlaybackDiscussion` | :89-131 | 讨论 Tab 容器，直接复用 |
| `SourceComments`（稀饭/Giri 评论） | cycani_source_comments.dart | 与次元城评论 UI 应合并为一（复用审计 A1），合并后成为唯一评论组件 |
| `publicSourceComment / sourceCommentDate` | :6-55 | 字段白名单 + 日期格式化，直接复用 |
| `xifanResumeMatch` | cycani_catalog_detail_page.dart:16-28 | 续播匹配，直接复用（应推广为三站统一 resume） |

### 2.5 播放集成（宿主侧，通用）
| 现有符号 | 位置 | 复用说明 |
|---|---|---|
| `OnlineVideoPlaybackArgs`（`catalogVideoIds/catalogBangumiId/initialEpisode/Road/Offset`） | video_playback_args.dart | 播放参数已 source 无关，直接复用 |
| `video_controller._fetchPlaybackDanmaku` 弹幕装配路径 | video_controller.dart:606-672 | 结构可复用；`source` 识别与 namespace 解码按 4.1/4.7 拉平 |
| `_resolveWithVideoSourceService` → `WebViewVideoSourceService` | :735-841 / webview_video_source_service.dart | 解析服务骨架复用；三站短路分支应收口为适配器注册表（4.7） |
| 选集侧栏 / 播放面板 / 超分 / PiP / SyncPlay / 截图 / 定时关闭 | player 全家 | 与站点无关，全部直接复用（见播放器审计第一节） |

### 2.6 我的页与设置
| 现有符号 | 位置 | 复用说明 |
|---|---|---|
| `CycaniSpaceView / CycaniDestination` | cycani_space_view.dart | "我的"布局与站点无关（数据由外部注入），直接复用 |
| `CycaniWeekSelector / CycaniLoadMore / CycaniError / cycaniConfirm / cycaniToast` | 组件 | 通用 UI 助手，直接复用 |
| `CycaniDanmakuSourceSettings` | cycani_danmaku_source_settings.dart | 来源开关 UI 直接复用（键名见 4.8） |
| `CycaniAvatarStore` | cycani_avatar_store.dart | 本地头像库（`pathFor`/`sourcePath` 双键已支持来源维度），复用后统一头像渲染 |

---

## 三、保留为站点适配器的部分（命名应彻底站点化，不是要消灭的部分）

聚合的正确姿势是"一个中性内核 + 三个对等适配器"，以下现有类就是适配器雏形，聚合时应**正名**为站点专属而非删除：

| 现有类 | 实际角色 | 聚合后应扮演 |
|---|---|---|
| `CycaniApi`（cycani_api.dart，667 行） | 次元城站适配器：会话/追番/历史/评论/弹幕/播放地址 | 站点适配器之一（正名后与其他两站并列） |
| `NativeCatalogApi`（cycani_native_catalog.dart） | 稀饭+Giri 的目录/选集/播放适配器 | 拆成 `XifanCatalogApi` + `GiriCatalogApi` 两个对等适配器更干净 |
| `SourceAccounts`（cycani_source_accounts.dart） | 稀饭（GoTrue）+Giri（Cookie+CSRF）会话与账号操作 | 拆成两站各自的账号适配器 |
| `CycaniRemoteDanmaku` | 稀饭弹幕 + 外部聚合中继客户端 | 保留（中继部分是跨站公共设施，可独立） |
| `GiriDanmakuApi` | Giri 站内 + 外部 XML 弹幕 | 保留 |
| `xifanHomeSections/_xifanHome/xifanRankingIds`、`giriHomeAccountSections`、`_cycaniBanners` | 各站首页数据适配 | 保留，但首页组装要对称化（4.3） |

---

## 四、不对称点全量清单（"次元城一个、稀饭/Giri 一个"，聚合前必须拉平）

### 4.1 身份体系双轨制（最深的一处）
- **次元城方案**：`toBangumi()` 生成**负 ID**（`id = -videoId`）+ `info: 'cycani:$id'` 前缀（cycani_models.dart:42-66）；卡片点击靠前缀识别（bangumi_card.dart:38-40）
- **稀饭/Giri 方案**：正数**偏移 ID**，`1000000000 + id` / `2000000000 + id`（cycani_native_catalog.dart:287,341）
- 解码逻辑散布 **4 处**且各自为政：`video_controller.dart:622-633`（负 ID / >2e9）、`cycani_playback_discussion.dart:29-55`（负 ID / -itemId-2e9）、`cycani_playback_danmaku.dart:84-108`、`cycani_catalog_sources.dart:46`
- 另有第三种身份：**插件名字符串**——`pluginName == CycaniApi.pluginName`（plugins.dart:242,262；playback_discussion:29）与 `== CatalogSource.xifan.label`（:38）、`== giri.label`（:47）三种写法并存
- **聚合要求**：统一为单一方案（建议：`CatalogSource` + 原始 ID 的二元组贯穿全链路，`toBangumi` 用保留字段而非复用 id/info 字段），解码收口为一个函数

### 4.2 会话与账号（三套系统、不对称生命周期）
- 三套会话实现：`CycaniApi`（token vault，自管理）vs `SourceAccounts._gKey/_xKey`（Giri Cookie / 稀饭 GoTrue token）
- 启动只恢复次元城会话：`CycaniBootstrap → CycaniApi.instance.restore()`（cycani_home_page.dart:57）；稀饭/Giri 会话惰性恢复——聚合应做对称的会话注册表
- 账号管理 UI 三套：`CycaniAccountPage`（次元城登录注册）+ `CycaniProfileSettingsPage/CycaniSecuritySettingsPage`（次元城资料/安全）+ `SourceAccountsPage`（稀饭/Giri，含 Geetest、Giri 图形验证码、重认证）；`SourceAccountsPage(initialGiri == null)` 的三入口列表里"次元城"又跳回另一套（`CycaniSourceAccount`）
- 头像渲染两套：`CycaniAvatar`（次元城）vs `CycaniMyPage` 内联 `CircleAvatar`（外站，cycani_my_page.dart:300-330）；`CycaniAvatarStore` 其实已支持双键（`pathFor`/`sourcePath`）
- 统计两套：`loadCycaniAccountStats`（cycani_account_stats.dart）vs `CycaniMyPage._externalStats`

### 4.3 首页布局（三种结构）
- `recommendations(source)` 返回三种不同布局协议：次元城（推荐分组 + `cycani-overview` 槽位）、稀饭（`_xifanHome` 固定五分组 HTML 解析）、Giri（banner/公告/台词/日历/推荐的大杂烩，catalog_sources.dart:423-586）
- 主页渲染端再各自特判：`cycani-overview` 槽位仅次元城有（cycani_home_page.dart:1068-1079）、`_giriHomeCalendar`（:925-992）、`_accountHomeRows/_giriRecommendationSliver`（:994-1031，Giri 登录态专区）、`tab==0 && activeSource==giri` 分支多处
- **聚合要求**：定义统一的首页分区协议（`{layout: hero|calendar|ranking|overview|text|quotes|grid, ...}`），三站适配器各自产出，渲染端只认 layout 不认站点

### 4.4 评论（两套 UI，见复用审计 A1）
- `CycaniComments`（次元城）vs `SourceComments`（稀饭/Giri），结构 60% 重复、日期格式化原样复制
- 讨论 Tab 分发点：`CatalogPlaybackDiscussion`（:119-126 `target.source == cycani ? ... : ...`）

### 4.5 追番 / 历史 / 统计（三条通路 + 三种时机）
- 追番：播放器心形 → 本地库+Bangumi（负 ID 静默失败，播放器审计第 8 项）；详情页次元城 → `CycaniApi.favorite`；稀饭/Giri → `setXifanFollow/setGiriFollow`——**三条通路互不相通**
- 历史上报三种时机/三种目标：次元城（15s 定时 `CycaniApi.reportHistory`）、稀饭（15s 定时 `recordXifanProgress`，episode 级）、Giri（详情页打开时一次性 `recordGiriHistory`，**vod 级**，无进度）（video_controller.dart:166-193 vs cycani_catalog_detail_page.dart:504-507）
- 续播三种：次元城 `history['progress']`（cycani_detail_page.dart:270）、稀饭 `xifanResumeMatch`（catalog_detail_page.dart:16-28）、Giri 无
- 收藏/历史列表 UI 两套（复用审计 A5）+ 库快照两套（`CycaniApi.saveLibrarySnapshot` vs `SourceAccounts.saveLibrary`）

### 4.6 弹幕通路
- 五个来源开关按站命名而非按通道命名：`cycaniExternalDanmaku/cycaniXifanDanmaku/cycaniSiteDanmaku/giriSiteDanmaku/giriExternalDanmaku`（settings_keys.dart:195-219）——"external"只有一个但挂在 cycani 名下；Giri 比 Xifan 多一个外部开关，语义不对齐
- 缓存写入条件枚举全部五开关（video_controller.dart:654-660）——加第四站要改这里（已在 API 报告 P1 建议放宽）
- 来源标签字符串身份：`'[次元城]'/'[稀饭]'/'[GiriGiri]'/'[GiriGiri外部]'/'[外部聚合]'`（cycani_danmaku_options.dart:15-19）+ 兜底 `_ => external`
- 发送入口两套：播放器输入框（本地回显，播放器审计第 6 项）vs 讨论 Tab（真发送）
- `CycaniDanmakuLoader.source = '[次元城]'` 遗留常量与 `CycaniDanmakuOptions.cycaniSource` 重复

### 4.7 播放解析识别
- `WebViewVideoSourceService._runResolve` 三个硬编码 URL 短路依次 if（webview_video_source_service.dart:66-109）——应改为"适配器注册表：每站一个 `canResolve(url) + resolve(url)`"，第四站零改动接入
- `video_controller` 的 namespace 解码（:622-633）与 `_xifanProgress` 页面 URL 特判（:806-823）是次元城/稀饭专属逻辑硬编码在通用控制器里
- 插件对象构造不对称：次元城插件持久注册（`updatePlugin(cycaniPlugin())`，cycani_home_page.dart:60），稀饭/Giri 插件每次播放临时 `Plugin.fromJson`（cycani_catalog_detail_page.dart:512-521）——`plugins.json` 里永远只有次元城一个

### 4.8 设置键与存储键命名
- 设置键：5 个以 `cycani*/giri*` 开头（4.6）；聚合后按"通道"命名并做旧值迁移
- 存储键 4 组前缀：`cycani.native.session.v1`、`cycani.native.library.v1.`、`cycani.giri.session.v1`/`cycani.xifan.session.v1`、`catalog.account.{giri,xifan}.*.v1`——次元城占用 `cycani.native`（native 一词暗示它是"本体"，其余是外挂），聚合应统一为 `sites.{name}.*`
- `CycaniApi.pluginName = '次元城'` 同时是插件名、路由身份、弹幕来源标识——一物三用

### 4.9 路由与品牌
- 路由：`/`（Bootstrap）、`/cycani`、`/cycani/detail`（index_module.dart:23-44）——主路由以单站命名；聚合应为 `/home`、`/catalog/detail?source=`（或路由参数带 source）
- 品牌字样 27 处（lib）：`main.dart`（窗口标题）、`exit_confirmation_dialog.dart`、`tray_service.dart`（托盘 tooltip'次元城'+图标）、`audio_controller.dart`（媒体通知渠道）、`index_module.dart`、`route_error_page.dart`、`settings_module/interface_settings`、`CycaniAboutPage`（'次元城'）、`space_view`（'关于次元城'）、`source_accounts.dart` 等
- 品牌资源与工程名：`pubspec.yaml`（description"次元城专用原生客户端"、launch_icons `cycani.png`、display_name 次元城）、`AndroidManifest.xml` label"次元城"、`assets/images/logo/cycani.*`、截图文件名前缀 `Cycani_`（screenshot_export_service.dart:40）、`README-CYCANI.md`、`build-cycani.ps1`
- 测试名 26 个 `cycani_*`、模块目录名 `lib/features/cycani/`、文件名 34 个 `cycani_*.dart`

### 4.10 与既有审计的重叠项（聚合时顺带解决）
- 复用审计：A1 评论两套、A2 周选择器三份、A3 排行三份（`ranking()` 零调用）、A5 追番/历史两套列表、C4 命名空间解码两处、C10 打开卡片三条导航路径
- 播放器审计：第 6 项弹幕发送假 UI、第 8 项收藏三通路不通
- API 报告：稀饭连接抖动 P0、弹幕缓存条件 P1

---

## 五、命名映射建议表（目标：中性内核 + 站点适配器 + 青月次元品牌）

### 5.1 通用层改名（去"次元城"化，统一 `Catalog*`/`Qingyue*` 前缀）
| 现名 | 建议名 | 层级 |
|---|---|---|
| 文件前缀 `cycani_*.dart`（通用内容的 34 个） | `catalog_*.dart` / `site_*.dart`（按内容） | 文件 |
| `CycaniJson/cycaniMap/cycaniList/cycaniInt/cycaniUniqueLabels` | `CatalogJson/catalogMap/catalogList/catalogInt/catalogUniqueLabels` | 模型 |
| `CycaniVideo / CycaniEpisodes` | `CatalogVideo / CatalogEpisodes` | 模型 |
| `CycaniPage / CycaniFeed` | `CatalogPage / CatalogFeed` | 分页 |
| `CycaniCatalogSources` | `CatalogAggregator`（三站聚合器） | 聚合 |
| `CycaniHomeOverview / CycaniHomePage / CycaniBootstrap` | `CatalogHomeOverview / QingyueHomePage / QingyueBootstrap` | 页面 |
| `CycaniSearchPage / CycaniMyPage / CycaniSpaceView / CycaniWeekSelector / CycaniLoadMore / CycaniError` | `Catalog*` 同义改名 | 页面/组件 |
| `CycaniDanmakuLoader / CycaniDanmakuOptions / CycaniDanmakuDialog / CycaniDanmakuSourceSettings` | `CatalogDanmaku*` | 弹幕 |
| `CycaniComments`（合并 SourceComments 后） | `CatalogComments` | 评论 |
| `CycaniAvatarStore / CycaniAvatar` | `AvatarStore / SiteAvatar` | 头像 |
| `CycaniAccountStats` | `SiteAccountStats` | 统计 |
| 路由 `/cycani`、`/cycani/detail` | `/home`、`/catalog/detail`（source 作参数） | 路由 |

### 5.2 适配器正名（保留站点语义）
| 现名 | 建议名 |
|---|---|
| `CycaniApi` | `CycaniSiteApi`（或保留，配 `XifanSiteApi / GiriSiteApi` 对等） |
| `SourceAccounts` | 拆 `XifanAccountApi / GiriAccountApi` |
| `NativeCatalogApi` | 拆 `XifanCatalogApi / GiriCatalogApi` |
| `CycaniRemoteDanmaku` | `XifanDanmakuApi` + `ExternalDanmakuRelay`（中继独立） |
| 会话/库存储键 `cycani.native.*`、`catalog.account.*` | 统一 `qingyue.site.{name}.session/library.v1`（需旧值迁移） |
| 设置键 `cycaniExternalDanmaku` 等 5 键 | 按通道命名如 `danmakuSourceExternal/Xifan/Cycani/Giri/GiriExternal`（迁移旧值） |

### 5.3 品牌替换清单（青月次元）
`pubspec.yaml`（name/description/display_name）、`AndroidManifest label`、`assets/images/logo/`（新增青月次元图标，替换 cycani.png/ico 引用点：启动图标、托盘、登录页、关于页、Bootstrap）、`tray_service` tooltip、`audio_controller` 通知渠道名、`exit_confirmation_dialog`、`main.dart` 窗口标题、`route_error_page`、`CycaniAboutPage` 文案、`screenshot_export_service` 前缀 `Cycani_`、`README-CYCANI.md`/`build-cycani.ps1` 文档化改名、测试文件前缀

---

## 六、聚合化改造顺序建议（不动代码，仅路线）

1. **统一身份模型**（4.1）：定 `SiteEntry(source, rawId)`，收口编解码；`toBangumi` 身份改走保留字段；`fromPlayback` 去字符串身份
2. **会话注册表**（4.2）：`SiteSessionRegistry` 对等管理三站会话，bootstrap 对称恢复；账号管理 UI 收敛为"每站一页 + 统一外壳"
3. **站点适配器接口化**（三、四节）：定义 `SiteAdapter { catalog; comments; favorites; history; danmaku; playback; homeSections }`，把 `CycaniApi/NativeCatalogApi/SourceAccounts` 的能力填进三个实现——现有的 `CatalogSource` 参数化函数正好是接口方法的现成素材
4. **首页协议化**（4.3）：统一 layout 枚举，三适配器产出，渲染端去站点 if
5. **评论/追番/历史/弹幕发送收敛**（4.4-4.6，顺带解决复用审计 A1/A3/A5 与播放器审计 6/8 项）
6. **品牌与命名迁移**（4.9、五章）：代码改名（IDE 重构即可，无行为变化）→ 设置/存储键迁移（旧值读一次写新键）→ 品牌资源替换
7. **收尾**：webview 解析分支收口为适配器注册表（4.7）；按 API 报告处理稀饭连接与图片通道

## 七、与既有文档的关系

| 文档 | 关系 |
|---|---|
| `cycani-reuse-audit.md` | 其 A1/A2/A3/A5/C4/C10 是本报告 4.4/4.3/4.5/4.1/4.7 的重复实现细节，聚合改造时一并消解 |
| `cycani-api-chain-test-report.md` | 三站 API 可达性与加速结论对聚合同样成立；稀饭抖动 P0 是聚合体验的最大风险项 |
| `cycani-player-unused-features.md` | 第 6/8 项（弹幕发送假 UI、收藏三通路）在聚合改造中必须收口；其余不可达清单与聚合无关但可顺带处理 |

---

*复审完成时间：2026-11-04。未改动任何代码。*
