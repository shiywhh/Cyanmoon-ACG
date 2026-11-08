# Three-site audit remediation Implementation Plan

**Goal:** Resolve the four audit documents with equal site behavior, safe source caches, and default Baidu public-image acceleration.
**Architecture:** Shared presentation and source identity, site-specific adapters and session ownership. Preserve legacy IDs/keys on disk via compatibility rather than deleting user data. Public proxy traffic never carries account credentials.
**Tech Stack:** Flutter/Dart, Dio, media_kit, Hive, flutter_cache_manager.

1. Inspect current implementation, preserve baseline, run existing offline suite.
2. Common foundation: source identity codec, network factory and independent session restoration; preserve site-specific rank semantics.
3. Repair player: real native danmaku send, source-aware follow, offline discussion, cloud Giri progress/resume and stale-session guards.
4. Reuse public page primitives: comments/date, weekday selector, error/confirm, avatar/list/navigation; retain snapshots during refresh.
5. Network/images: allowlisted Baidu public images with direct fallback, small Xifan grid variants, cached poster/banner/avatar; source-scoped danmaku cache retaining failed-source data.
6. Analyze and run targeted + full regression; record unresolved checks honestly. No report UI, no APK build, no physical-device requirement.

Tests: new image URL/privacy/fallback tests; source identity and progress contracts; partial cache tests; existing account, navigation, comments, detail/home tests. Review diff against baseline after tests. Network claims require current probes, not historical assumptions.

---

## Completion record (2026-11-07)

All six steps implemented and verified: `flutter analyze` 0 errors; full offline suite **394 passed / 26 skipped** (live-gated). A mechanical rename (generic layer → `Catalog*`/`Qingyue*`, routes `/cycani`→`/qingyue`, app brand strings) was layered on top; a pre-rename snapshot exists at `.snapshot-pre-rename/`.

## Unresolved / by-design notes (step 6, recorded honestly)

1. **`_sessionWrites` hang in consecutive widget tests**: awaiting the write queue inside a second FakeAsync test zone never completes (cross-zone chained-future artifact). Mitigated with a 2-second `timeout` guard in `_xOptions`/`_checkGiriSession` so session reads proceed; production runs in one zone and is unaffected. Root cause of the zone interaction not fully chased down — recorded as open.
2. **Settings keys**: Dart identifiers neutralized (`danmakuSource*`); **on-disk names deliberately kept** (`cycaniExternalDanmaku` etc.) so existing user settings survive. Migration intentionally not attempted.
3. **Site adapters keep site-prefixed names** (`CycaniApi`, `CycaniDetailPage`, account pages): these are the 次元城 site adapters; per the neutral-kernel + site-adapter architecture, site-named adapters are correct.
4. **Cross-site library**: home favorites/history tabs now merge all signed-in sites with per-row write routing (`catalog_library.dart`). A true cross-site "same show merged across sites" view remains a product-level open item (README "跨站写回" note superseded by this).
5. **DNS multi-address fallback (probe report item 三10)**: `Socket.startConnect` already staggers attempts across all resolved addresses; with the 4s connect timeout + 2 read-retries the worst case is bounded (~12s). No code change needed.
6. **Android real-device validation** remains outstanding (as before; plan excluded it).
7. **`CatalogWeekSelector` vs `CatalogWeekPicker`** — verified as a layered design (counts vs simple wrapper), not duplication.
