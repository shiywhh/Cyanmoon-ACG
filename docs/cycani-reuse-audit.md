# 次元城代码复用审计报告

> 审计范围：`lib/features/cycani/` 全部 34 个文件（约 12,500 行）+ 16 个宿主集成文件 + 路由表（`index_module` / `settings_module` / `video_module`）。
> 审计方法：全量通读 + grep 逐类量化核实（Dio 工厂、倒计时、确认框、LRU 缓存、日期格式化、头像菜单、孤儿页面路由可达性）。
> 结论只列"能复用但未复用"，不含改动；每条附文件：行号证据。

---

## 一、页面级重复（7 项）

### A1. 评论页两套 —— 重复度最高
| | 次元城 | 稀饭 / GiriGiri |
|---|---|---|
| 文件 | `cycani_comments.dart`（309 行） | `cycani_source_comments.dart`（425 行） |
| 结构 | 标题行+排序下拉+刷新 → 输入框+发布 → 评论卡片（昵称/置顶/内容/日期/回复数）→ 触底分页 | 完全相同的结构 |
| 状态机 | `CycaniFeed` | 手写 cursor 分页（`replyCursor`/`_replyLoading`/`_RetryFirstReplyPage`） |

铁证：日期格式化逻辑原样复制，输出同样的 `yyyy-MM-dd HH:mm`：
- `cycani_comments.dart:130-135`（`_date`）
- `cycani_source_comments.dart:44-55`（`sourceCommentDate`，是 `_date` 的超集，处理了秒/毫秒时间戳）

后者可直接被前者调用；进一步可提取公共评论列表骨架（头行/输入行/卡片/分页），两页只保留数据适配层。

### A2. 周选择器三份实现
- 现成组件：`cycani_week_selector.dart`（TabBar 版，带每日计数、无障碍、自适应滚动，100 行）——仅主页 tab3 用了一次
- 内联重写 ①：`cycani_home_overview.dart:186-205`，主页概览"追番周表"手写 周一~周日 ChoiceChip 行
- 内联重写 ②：`cycani_home_page.dart:931-957`（`_giriHomeCalendar`），Giri 主页日历又手写一遍同样的 ChoiceChip 行

连带两套按天请求缓存并存于同一文件：`_CycaniHomePageState._week()`/`weekData`/`weekEpochs`（三站合并周表）与 `_giriHomeWeeks`（Giri 专用周表）。

行为分歧提醒：概览区 `_fetch`（`cycani_home_overview.dart:80-84`）走 `api.schedule()`（仅次元城），tab3 走 `mergedSchedule()`（三站合并）——同一 App 两个"周表"数据口径不同，收口时需先确认是否有意为之。

### A3. 排行榜拉取逻辑：统一版写了但生产代码零调用
- `CycaniCatalogSources.ranking()`（`cycani_catalog_sources.dart:848-896`）已统一三站排行（cycani 按榜名→`rankVideos`；xifan 按 view_count；giri 按 hits_week）——**但 grep 全库只有 2 个测试文件调用它，生产代码零调用**
- 重复实现 ①：`cycani_home_page.dart:497-506`（`_ranking()`，cycani 分支与 `ranking()` 的 cycani 分支相同）
- 重复实现 ②：`cycani_home_overview.dart:85-92`（`_fetch` rank 分支，再次"按名字找榜→rankVideos"）
- 重复实现 ③：`cycani_home_page.dart:197-242`（`_giriRankingTab` 分支，giri 榜组+分页又写了一遍，未走 `giriRankingGroups()` 的缓存路径前与 `ranking()` giri 分支重叠）

### A4. 登录/账户表单组件重复
| 重复块 | 位置 ① | 位置 ② |
|---|---|---|
| `_field()` 输入框封装 | `cycani_auth_page.dart:94-114` | `cycani_profile_settings.dart:224-237` |
| 60s 验证码倒计时（`Timer.periodic`+mounted 守卫） | `cycani_auth_page.dart:47-57` | `cycani_profile_settings.dart:245-253` |
| "邮箱+验证码+发送按钮"表单（3 处） | 注册/重置 `cycani_auth_page.dart:150-161` | 绑邮箱 `cycani_profile_settings.dart:279-295`；换邮箱 `cycani_source_accounts.dart:2238-2259` |
| 改密表单（当前/新/确认+校验，2 处） | 次元城改密 `cycani_profile_settings.dart:298-323` | 稀饭改密 `_XifanPasswordDialog`（`cycani_source_accounts.dart:2099-2169`） |
| 未登录→登录按钮→push 登录页→刷新 脚手架 | `cycani_profile_settings.dart:81-94` | 同文件 `:260-268`（Security 页） |

### A5. 追番/历史两套列表 UI
- 次元城账号：主页 tab4/5 网格 UI（批量管理、库内搜索、列表/网格切换，`cycani_home_page.dart:756-803、1361-1389`）
- 稀饭/Giri 账号：`SourceAccountsPage(library:4/5)` 纯 ListTile 页（`cycani_source_accounts.dart:1884-1915`）
- 两者加载条/错误重试/触底追加的脚手架同构（后者 `:1936-1947` 手写 `NotificationListener` 滚动追加）。数据模型不同是客观原因，但列表骨架可共享；与 README"跨站追番、历史写回尚未实现"同源
- 另见：播放器心形收藏与上述追番体系的数据通路断链（本地收藏库 + Bangumi 同步 vs 各站云端追番，收藏无处查看/负 ID 静默失败），详见[《播放器功能审计》第二节第 8 项](cycani-player-unused-features.md)

### A6. 头像：显示与选择三处不统一
- `CycaniAvatar`（`cycani_my_page.dart:16-62`）：只支持次元城账号（本地文件优先→远程回退）
- 外站账号头像在 `_CycaniMyPageState.build` 内联另一套 `CircleAvatar`+`FileImage/NetworkImage` 逻辑（`cycani_my_page.dart:300-330`）
- 选头像菜单写了两遍：`cycani_profile_settings.dart:102-129`（从本机选择/恢复账号头像）与 `cycani_source_accounts.dart:1819-1842`（选择本地图片/恢复账号头像），文案都不一致
- `CycaniAvatarStore` 本就有 `sourcePath()/chooseSource()`（`cycani_avatar_store.dart:35-39`）支持按来源键存取——把 `CycaniAvatar` 参数化为按存储键取图即可三处归一

### A7. 启动页重写（原版成了孤儿）
- `CycaniBootstrap`（`cycani_home_page.dart:41-104`）重写了插件初始化/着色器/下载/屏蔽词启动序列
- 原版 `lib/pages/init_page.dart`（326 行，含插件更新检查等更全逻辑）已无任何路由与外部引用（grep 证实）
- 差异点：Bootstrap 未继承原版的"插件更新检查"，如需保留该能力，复用比重写省事

---

## 二、组件级：现成组件没被用（4 项）

### B1. `CycaniError`（带重试+401 登录按钮，`cycani_home_page.dart:1464-1499`）
已用于：主页、搜索页、评论、`CycaniDetailPage:339`。
未用手写"加载失败，重试"TextButton 的地方：
- `cycani_catalog_detail_page.dart:310-315`
- `cycani_feed_widgets.dart:145-151`（`_XifanSeriesPage`）
- `cycani_giri_collections.dart:183-184`
- `cycani_source_comments.dart:410-411`
- `cycani_home_page.dart:967-982`（`_giriHomeCalendar` 错误分支，同文件里就有 `CycaniError`）

### B2. `cycaniConfirm`（`cycani_home_page.dart:1504-1521`）
未复用、各写一份"取消/删除"确认框：
- `cycani_giri_collections.dart:120-138`（`_delete`）
- `cycani_source_accounts.dart:1508-1528`（`_removeHistory`）

### B3. `CycaniLoadMore`（`cycani_feed_widgets.dart:178-259`）
绑定 `CycaniFeed`，因此 `SourceAccountsPage` 触底追加只能手写滚动监听（`cycani_source_accounts.dart:1936-1947`，`extentAfter < 320`）。把触发器泛化为回调参数即可复用。

### B4. `CycaniAvatar` 未参数化（同 A6）
存储键已支持 `int id` 与 `source+user` 两种，组件只暴露了前者。

---

## 三、逻辑/工具级重复（10 项）

### C1. Dio 客户端工厂 ×6
"DIRECT 代理适配器（绕区域门禁）+ 超时 + followRedirects:false + 敏感头剥离"几乎相同的 `_client()`：
`cycani_api.dart:66-72`（构造器内变体）、`cycani_catalog_sources.dart:180-198`、`cycani_native_catalog.dart:59-77`、`cycani_giri_danmaku.dart:34-47`、`cycani_source_accounts.dart:42-60`、`cycani_remote_danmaku.dart:52-67`。
且原版 `lib/request/core/network_config.dart:54-55` 已有 `createAdapter()` 可挂接。这是全部重复中收益最大的一项。

### C2. 手写"60 条上限、满了删最旧"缓存 ×4
- `cycani_detail_page.dart:151-152`
- `cycani_source_comments.dart:141`
- `cycani_catalog_sources.dart:1066-1068`（`_searchSnapshots`）
- `cycani_native_catalog.dart:192-193`
一个 20 行的迷你 LRU 类即可替代四处。另有同类"串行写队列"模式实现 3 遍：`CycaniApi._libraryWrites`（`cycani_api.dart:115-198`）、`SourceAccounts._sessionWrites`（`cycani_source_accounts.dart:108-135`）、`CatalogDiskCache._writing`（`cycani_catalog_disk_cache.dart:13,62-81`）。

### C3. "读磁盘缓存→showCached→网络刷新"模式 ×6
`cycani_search_page.dart:50-59`、`cycani_comments.dart:87-98`、`cycani_home_overview.dart:94-105`、`cycani_home_page.dart:346-354,394-419`、`cycani_detail_page.dart:153-180`、`cycani_source_comments.dart:88-99,177-181`。可折进 `CycaniFeed`（构造时传 cacheKey）。

### C4. ID 命名空间解码两处并行
编码集中在 `cycani_native_catalog.dart:287,341`（giri=`2000000000+id`、xifan=`1000000000+id`），解码却写了两份：
- `cycani_playback_discussion.dart:29-55`（`CatalogDiscussionTarget.fromPlayback`）
- `video_controller.dart:622-633`（`_fetchPlaybackDanmaku`）
应提取 `catalogVideoIdFromNamespace(int)` 一类函数，避免日后加第四站时改两处漏一处。

### C5. 弹幕 mode/color 解析 ×4
- 字符串 mode 映射（`top→5/bottom→4/else 1`）：`cycani_danmaku_loader.dart:140-144`、`cycani_remote_danmaku.dart:236-240`
- 数字 mode 映射：`cycani_giri_danmaku.dart:92-98`（2→5/3→4）、`:122-128`（4→4/5→5）
- `Color(0xFF000000 | (c & 0xFFFFFF))` 掩码出现 4 次（loader:146、remote:241、giri:97、giri:127，另 dialog:114 同构）

### C6. "busy 守卫 + try/catch + SnackBar"包装 ×6
`cycani_profile_settings.dart:62-75`（`_run`）、同文件 `:202-222`（Security `_run`）、`cycani_source_accounts.dart:2191-2208`（`_XifanEmailPage._run`）、`cycani_source_comments.dart:220-245`（`mutate`）、`cycani_giri_collections.dart:68-91`（`_mutate`）、`cycani_catalog_detail_page.dart:236-254`（`_sourceAction`）。`bool busy` 字段另在 6 个 State 类中重复声明。可做成 mixin 或 `runBusy(context, action, {errorText})`。

### C7. 日期格式化 ×2（见 A1，grep 证实仅这两处 `pad(date.month)`）

### C8. 同一个 FutureBuilder 建两遍
`cycani_home_page.dart:994-1016`（`_accountHomeRows`）与 `:1018-1031`（`_giriRecommendationSliver`）：相同 key/initialData/future 三元组各写一个 FutureBuilder。

### C9. 字段白名单快照构造 ×3
公开数据落盘前的逐字段拷贝：`cycani_source_comments.dart:6-42`（`publicSourceComment`）、`cycani_api.dart:147-198`（`saveLibrarySnapshot`）、`cycani_comments.dart:55-71`（`publicRows`）。模式相同（遍历白名单字段 if containsKey），可提取 `pickFields(map, fields)`。

### C10. "打开一个番剧卡片"三条导航路径
- `cycani_feed_widgets.dart:74-94`（`_openCatalogRow`：xifan_series→系列页，否则 push `CatalogDetailPage`）
- `cycani_home_page.dart:828-837`（`_tile.open`：`widget.api==null && tab<=3` 走 CatalogDetailPage，否则 pushNamed `/cycani/detail`）
- `bean/card/bangumi_card.dart:38-40`（负 ID+`cycani:` 前缀→pushNamed `/cycani/detail`）
三条路径终点都是详情页，但条件分支各异，新站接入时容易漏改。

---

## 四、复用做得好的部分（对照，不需要动）

- 详情页骨架组件共享：`CatalogDetailScroll/Header/Poster/Synopsis/EpisodePicker`（`cycani_detail_page.dart:486-668`）被两套详情页共用
- `CycaniDanmakuDialog` 三站弹幕发送共用（经 `CatalogDiscussionTarget.send` 分发）
- `_XifanProfileDialog` 一套对话框兼容稀饭+Giri（`cycani_source_accounts.dart:2008-2097`）
- `retryPublicCatalogRead` 统一只读重试（`cycani_read_retry.dart`，被 6 个文件使用）
- URL 严格解析器集中复用：`NativeCatalogApi.xifanEpisode/giriMedia`、`cycaniSectionId`
- 海报卡/时间线卡（`BangumiCardV`/`BangumiTimelineCard`）、`MyController`/`WatchStats`、`SettingsDetailScaffold`、`GStorage` 设置键体系均复用原版

---

## 五、附：孤儿页面与疑似断链（顺带发现，属死代码而非复用问题）

路由表实际只注册了：`/`、`/error`、`/cycani`、`/cycani/detail`、`videoModule`（`/video/`）、ImageViewer、`settingsModule`（含 danmaku/history/download 子模块）。

以下原版 Kazumi UI 页面**无任何路由、无目录外引用**（grep 证实）：
`pages/index_page.dart`、`pages/init_page.dart`、`pages/popular/`、`pages/timeline/`、`pages/search/search_page.dart`、`pages/my/my_page.dart`、`pages/info/`（`info_module.dart` 无人 import）、`pages/collect/`（页面本体；controller 仍在用）、`pages/menu/`。
注意：它们的 controller 层（`history_controller`、`collect_controller`、`my_controller`、`download`）仍被次元城正常复用——死掉的只是 UI 壳。

疑似断链一处：`pages/history/history_page.dart:231` 与 `pages/collect/collect_page.dart:147` 在点击条目时 `pushNamed('/info/')`，但 `/info/` 对应的 `infoModule` 未被任何模块注册——本地历史页（经设置可达）点击条目预计落到路由错误页。需实测确认后处理。

---

## 六、优先级建议（未改动任何代码）

| 优先级 | 事项 | 预期收益 |
|---|---|---|
| P0 | C1 Dio 工厂提取 | 删 6 份重复，统一代理/超时/头安全策略，未来加站只改一处 |
| P0 | A3 排行榜收口 | 让生产代码调用已写好且有测试覆盖的 `ranking()`，消除 4 份实现 |
| P1 | A1 评论页合并 + C7 | 删约 300 行重复 UI，日期函数立即合一 |
| P1 | A2 周选择器收口 + 明确两套周表数据口径 | 删两份内联 chips；顺带解决概览区/tab3 数据不一致的隐患 |
| P2 | B1/B2 错误与确认组件替换 | 小改动，交互一致性 |
| P2 | C2/C3/C6 缓存与 busy 包装提取 | 各删 4~6 处样板 |
| P3 | A4 表单组件、A6 头像组件参数化、C4 命名空间解码、C5 弹幕解析 | 中等收益，可与相邻需求顺带做 |
| P3 | 第五章孤儿页面清理 | 减少维护噪音；处理前先实测 `/info/` 断链 |

---

*审计完成时间：2026-11-04。审计基于工作区当前代码状态（未提交修改以文件系统为准）。*
