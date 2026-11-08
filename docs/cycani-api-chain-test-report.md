# 次元城 API 链路实测报告（含图片加速分析）

> 测试日期：2026-11-04。网络环境：校园网（DNS 10.8.8.8），全部直连（与 App 的 DIRECT 策略一致）。
> 方法：① 新增只读探测测试逐条请求全部公开链路并计时；② 开启仓库全部 10 个只读联网测试门控跑完整测试；③ 对失败主机用 curl / Dart 原生 socket 逐 IP 定位根因；④ 对全部图片主机独立采样测速。
> 产物：[test/cycani_api_chain_probe_test.dart](../test/cycani_api_chain_probe_test.dart)（可随时复跑）。

---

## 一、API 链路实测结果

### 1.1 分主机链路表（探测 32 条/轮 × 2 轮 + 仓库实时测试两批）

| 主机 | 链路 | 结果 | 延迟 |
|---|---|---|---|
| **次元城** `www.cycani.org/api` | 14 条：推荐 / banner / 分区 / 列表 / 搜索 / 详情+选集 / 相关推荐 / 评论 / 评论回复 / 弹幕 / 播放地址守卫 / 榜单+榜单详情 / 周表 / 账户守卫 | ✅ **全部通过，两轮稳定** | 84~617ms，健康 |
| **GiriGiri** `m3u8.girigirilove.com/api.php` | 12 条：分类 / 详情 / 评论 / 站内弹幕 getScrolling / 外部 XML（含 CNAME 回退）/ 主页聚合（bannerList、appConfigData、famousList、likeList）/ 周表 / 榜单组+榜单分页 / 筛选 4 端点 / sso 状态 / 验证码图 | ✅ **全部通过** | 2694~8998ms，偏慢但稳；周表 1 分钟缓存生效（第二轮 0ms 命中） |
| **稀饭 Web** `next.xifanacg.com` | 3 条 HTML：主页 / 排行榜 / 系列页 | ✅ 全部通过 | 180~627ms |
| **稀饭 API** `api.xifanacg.com` | 分类 / 搜索 / 详情+选集 / 弹幕 RPC / 评论 RPC / 播放解析 / 登录 token | ❌ **全部连接超时**（探测 9/9 失败） | 每条 8~10s × 3 次重试 = **最坏 24.9s** 才报错 |
| **外部弹幕中继** `ext-danmaku.moedot.net` | bangumi 匹配 + comment 拉取 | ⚠️ curl 通（200/431ms），Dart TCP 连接曾 4s 失败，同为抖动 | — |

仓库自带实时测试：批次 A（次元城/Giri 向）**30 过 / 4 挂**，批次 B（稀饭重度/三站合并）**31 过 / 7 挂**——**挂的 11 项全部是 api.xifanacg.com 依赖链**，其余（次元城弹幕、官方榜单、Giri 弹幕双路、Giri 筛选器、Giri 浏览/榜单/周表等）实时全过。三站合并搜索/周表在该窗口退化为两站仍可用（容错设计有效）。

### 1.2 稀饭 API 失败根因（已定位）

- `api.xifanacg.com` CNAME → `veilx-asia.veilx-edge.com`（CDN 多节点 23.136.252.3/.4 轮询，**仅 IPv4，无 AAAA**）
- Dart socket 逐 IP 连测同一节点 4 轮：`OK 1203ms / FAIL 3006ms / OK 213ms / OK 205ms` → **TCP/TLS 首连成功率约 50~75%**，系校园网到该节点的丢包抖动
- Dart `HttpClient` 单次连接只试一个地址、8~10s 超时内不回退；`retryPublicCatalogRead` 再补 2 次同地址重试 → 单链路最坏 24.9s
- 对照：稀饭 Web 主机（23.147.164.132）与次元城、Giri 主机全程稳定——**问题只在这一个 CDN**

### 1.3 受稀饭牵连的链路（当前网络窗口）

三站合并搜索/周表（缺稀饭路）、五路弹幕（缺外部聚合+稀饭两路，剩次元城+Giri 两路）、稀饭账号/评论/追番/播放解析、外部弹幕（部分依赖稀饭匹配）。登录态链路（token 下发/刷新、次元城 play-url 实发、账号写操作）无凭据未实发，仅验证了匿名拒绝守卫均正常。

### 1.4 复现命令

```bash
CYCANI_CHAIN_PROBE=1 flutter test test/cycani_api_chain_probe_test.dart --no-pub
# 仓库实时测试（按需开门控）：
CYCANI_DANMAKU_LIVE=1 CYCANI_OFFICIAL_RANK_LIVE=1 CYCANI_FILTERS_LIVE=1 \
GIRI_DANMAKU_LIVE=1 CYCANI_COMMENTS_LIVE=1 CYCANI_NATIVE_CATALOG_LIVE=1 \
  flutter test test/cycani_danmaku_test.dart test/cycani_official_ranking_test.dart \
  test/cycani_source_filters_test.dart test/cycani_giri_danmaku_test.dart \
  test/cycani_source_comments_test.dart test/cycani_native_catalog_test.dart --no-pub
CATALOG_PUBLIC_LIVE=1 CYCANI_CATALOG_LIVE=1 XIFAN_HOME_LIVE=1 CYCANI_PARITY_LIVE=1 \
CYCANI_MERGE_LIVE=1 CATALOG_FIVE_DANMAKU_LIVE=1 \
  flutter test test/cycani_public_catalog_live_test.dart test/cycani_catalog_sources_test.dart \
  test/cycani_danmaku_merge_test.dart test/cycani_playback_danmaku_test.dart --no-pub
```

---

## 二、API 链路加速方案

| 级别 | 措施 | 依据 |
|---|---|---|
| **P0** | 稀饭/中继等抖动主机 `connectTimeout` 8~10s → **3~4s**（重试次数不变） | 健康路由首连实测 213ms，3s 足够；丢包窗口下"多试快试"优于"少试慢试"，最坏 24.9s → ~12s，总尝试次数反而更多 |
| **P0** | 超时后**换地址重试**：重新 `InternetAddress.lookup` 再连（happy-eyeballs 式），必要时对稀饭可选启用系统代理回退 | 单地址 8s 不回退是当前最大痛点；注意次元城必须 DIRECT（区域门禁），稀饭无此约束但需评估 |
| **P1** | 弹幕缓存条件放宽：五路全成功才写缓存（`video_controller.dart:654-670`）→ **部分成功也缓存**（来源标记与 `includes()` 过滤已存在，改动小） | 抖动网络下外部/稀饭常挂 → 永不缓存 → 每次播放全量重拉（最长 40s）；命中缓存时 0ms |
| **P1** | 次元城详情页 `detail→episodes→recommendations` 串行 → recommendations 与 episodes 并行（`cycani_detail_page.dart:181-207`） | recommendations 只依赖 id；省 ~130ms |
| **P2** | `/ranks`、`/video-zones` 加 30~60s TTL 内存缓存 | 一次会话被主页 `_filters()`、HomeOverview、`_ranking()` 各拉一遍（~150ms/次） |
| **P2** | Giri 外部弹幕 DNS 回退 alidns→cloudflare 顺序 → 竞速并行（`cycani_giri_danmaku.dart:188-218`） | 该链路实测 3.1~3.8s，失败分支要等前一家超时 |
| **P2** | `CycaniApi.episodes()` 多线路第 1 页并行（`cycani_api.dart:474-509`） | 现按线路串行 while 翻页 |
| **P3** | Giri banner/公告等公开数据接入 `CatalogDiskCache` 短 TTL（detail 已缓存，banner 未缓存） | 主页聚合实测 5.4~7.6s，二次进入应近 0 |

已确认无需优化：三站搜索/周表/弹幕五路均已并行；磁盘缓存先于网络展示；Giri 周表已有缓存。

---

## 三、图片加载现状

### 3.1 缓存与加速栈

```
卡片网格 → NetworkImgLayer（CachedNetworkImage + memCacheWidth 解码降采样 ✅）
              ↓ defaultCacheManager = ProxyAwareImageCacheManager
          ImageFileService.get()
              ├─ ImageAcceleration.current == ech    → EchTransport（ECH 加密握手，仅 lain.bgm.tv 白名单）默认
              ├─ ImageAcceleration.current == mirror → BangumiImageUrlRewriter → wsrv.nl（仅 lain.bgm.tv/api.bgm.tv 白名单）
              └─ direct → NetworkConfig HttpClient（connectTimeout 12s / receiveTimeout 12s）
```

- **加速开关只覆盖 bangumi 图源**：`BangumiImageUrlRewriter` 白名单仅 `lain.bgm.tv` / `api.bgm.tv`，三站图源三种模式行为完全相同（直连）
- **wsrv.nl（mirror 通道）在本网络被 RST 重置**（0.2~0.3s connection reset）——"镜像"模式当前不可用，方案不能依赖它
- 次元城自有 UI 有 **3 处裸 `Image.network`**（无磁盘缓存、无解码降采样、不走缓存管理器）：
  1. `CatalogPoster` 详情页海报（`cycani_detail_page.dart:587-616`，有 errorBuilder 多 URL 回退 ✅）
  2. 主页 banner 轮播（`cycani_home_page.dart:897`）
  3. 我的页远程头像（`cycani_my_page.dart:53`）

### 3.2 图源主机实测（curl 采样）

| 主机 | 内容 | 实测 | 评价 |
|---|---|---|---|
| `gimg1.baidu.com` | 次元城封面（站方已代理 `img1.cycapp.org`） | 16KB 首包 **52~87ms** | ✅ 最快，百度 CDN |
| `img1.cycapp.org` | 次元城源站 | TLS 直连失败 | （App 拿到的 cover_url 已是 gimg 代理串，无影响） |
| `img2.xfmanga.top/r/1200/` | 稀饭封面（服务端缩放变体） | 0.30~7.12s 抖动；整图 **364KB / 4.5s** | ⚠️ 慢 + 抖 |
| `img2.xfmanga.top/r/600/` | 同上小变体 | 整图 **122KB / 0.66s** | ✅ **快 7 倍、体积 1/3，服务端变体可用** |
| `jpg.girigirilove.com` | Giri 网格封面（webp） | 7.3s / 直接 12s 连接超时 | ❌ **最差图源** |
| `m3u8.girigirilove.com/upload/` | Giri banner（gif） | 2.1s / 传输中断连 | ❌ 与慢速 API 同主机，互相抢连接 |
| `wsrv.nl` | 现有 mirror 通道 | 0.2s 被 RST | ❌ 本网络不可用 |

网格海报已复用 `NetworkImgLayer`（解码端已优化），**矛盾集中在网络层**：抖动主机上的首次下载与重复下载。

---

## 四、图片加速方案

| 级别 | 措施 | 依据 / 收益 |
|---|---|---|
| **P0-1** | 3 处裸 `Image.network` → `CachedNetworkImage`（`errorWidget` 保留 CatalogPoster 的多 URL 回退）：自动接入 `ProxyAwareImageCacheManager` | 详情页海报、主页 banner、头像**二次进入 0 下载**；同 URL 网格/详情不再重复下载；统一走 12s 超时与系统代理设置 |
| **P0-2** | 稀饭网格封面改用小变体：`img2.xfmanga.top/r/1200/...` → `/r/600/...`（客户端 URL 改写，仿照 `BangumiImageUrlRewriter` 的挂点；详情页保留 1200） | 实测 364KB/4.5s → 122KB/0.66s：**体积 −66%，时间 −85%**；网格卡显示宽度 <400px，600px 变体绰绰有余 |
| **P1-1** | `ImageFileService` 对连接失败做 1 次快速重试，或把图片通道 `connectTimeout` 12s → 6s | 抖动主机（jpg.giri、img2）单请求失败概率 25~50%，快失败快重试比 12s 挂死体验好；flutter_cache_manager 失败不落缓存，天然可重试 |
| **P1-2** | 对抖动图源限并发（4~6 个同时下载，优先可见项） | 丢包链路 36 张并发互相挤兑；限流后单张完成率上升，首屏可见图更快出来 |
| **P2-1** | 页面进入时对首屏前 N 张 `precacheImage`（走 `CachedNetworkImageProvider`） | 首屏海报与数据同涨，体感首帧提前 |
| **P2-2** | Giri banner（m3u8 主机 gif）数量少（轮播数张），随 P1-2 限流自然缓解，不单独处理 | — |
| **P3** | "镜像"模式修复：wsrv.nl 已被 RST，如需保留该模式应换国内可达镜像或自建反代（超 App 端范围，需另行评估）；短期内在设置项描述中注明适用网络 | 现状该开关对本网络用户是无效选项 |

不建议做的事：把三站图源接入 wsrv.nl（本网络已证实被重置）；给次元城封面换通道（百度代理 52ms 已是最优，且 cover_url 由站方下发）。

### 4.1 附录：百度 gimg 代理实测（2026-11-04 追加，回答"能否都走百度代理"）

`gimg1.baidu.com/gimg/app=2001&src={host+path}` 是百度图片的 Ohc 按需回源代理，**接受任意源站**：首访 MISS 由百度服务器回源抓取，之后 HIT 边缘缓存。字节级校验均为真图（稀饭→JFIF JPEG，Giri→RIFF/WEBP，gif 动图保真 `image/gif`）。

| 链路 | 直连 | 经 gimg | 提升 |
|---|---|---|---|
| 稀饭封面 364KB 全图 | 实测窗口直连瘫痪（15s 超时 / 15s 仅 8KB） | **0.22~0.39s** | ~40× |
| Giri 网格封面 70KB webp | 7.3s / 12s 超时 | **0.08~0.39s** | 20~100× |
| Giri banner gif（4.3MB） | 2.1s / 断连 | 可用（冷取 11.5s 为百度回源成本，热后快） | ✅ |

**落地建议**：挂点 `ImageFileService.get()`；白名单仅 `img*.xfmanga.top`、`jpg.girigirilove.com`、`m3u8.girigirilove.com`（次元城 cover_url 站方已是 gimg 串，不动）；**失败必须回退直连**；做成 `ImageAcceleration` 可选模式（该枚举已是三态，可替换失效的 mirror 或新增）。

**限制**：① 非公开接口，无文档/SLA，百度可随时变更或限流——务必开关化 + 回退，不作硬依赖；② 边缘缓存 `Expires` +1 个月且 `Last-Modified` 为假值（1970），同 URL 换图最长一个月取旧图（番剧封面基本不变，风险低；返回字节与直连有 ~295B 微差，疑似百度轻量重编码）；③ MISS 期间 Range 请求返回 52B 伪响应——flutter_cache_manager 不用 Range，无影响，自写断点续传需注意；④ 冷启动成本由百度承担，仅超大文件慢（顺带发现 Giri banner gif 单个 4.3MB，系 Giri 站自身问题）。

该方案与 P0-2（稀饭 r/600 变体）不互斥：gimg 连通性收益更大（同时解决 Giri），r/600 是体积/流量收益，可组合使用（gimg 的 src 指向 r/600 变体 URL 即同时拿到两者）。

---

## 五、结论速览

1. **次元城站链路全部健康**（84~617ms），无需动
2. **唯一的 API 大问题是 api.xifanacg.com 丢包抖动**：根因是网络→CDN 节点丢包 + Dart 单地址连接不回退 + 8~10s 超时×3 重试；降超时 + 换地址重试即可把最坏 24.9s 压到 ~12s 以内
3. **图片的最大单项收益是稀饭 r/600 变体**（−66% 体积、−85% 时间），其次是三处裸 `Image.network` 补上磁盘缓存
4. Giri API 慢（2.7~9s）但稳，靠已有缓存策略 + P3 公开数据缓存即可
5. 弹幕缓存条件放宽是抖动网络下播放体验的最大杠杆（P1）
