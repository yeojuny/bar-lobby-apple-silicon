# Release validation and limits — 2026-10-15

This independent unsigned experimental release is one BAR.app for Apple Silicon/macOS 27+, with bar-lobby, Multiplayer (Chobby) and a shared Metal3/experimental Metal4 setting.

| Evidence | Scope |
| --- | --- |
| Frozen source | 552 launcher input hashes and three reviewed fixtures; source lock `146cb4b8…` |
| Packaged application | Inventory `6f8908edf3f81deda984e9ec5f5fd3ee31b5c5a46bcb2b803343ae3bf201a02d`; exact source/ASAR binding and strict ad-hoc signature verification |
| Native functional batch | 31 native, 6 prepared, 23 group, 10 ownership, 96 offscreen cases and 16 presentation frames on the earlier native-tested parent; runtime bytes match the release |
| Renderer UI | Earlier UI-fixed package checked Metal3 default, saved/reopened Metal4 and external Metal3 override preserving the saved choice; the helper-fixed release app subsequently rendered both Chobby menus and returned visibly to Lobby after the short game; renderer Settings checks remain scoped to that earlier UI-fixed package |
| Chobby Metal3 / Metal4 | Both rendered menus and real helper connections passed on inventory `6f8908ed…`; launcher exit 0, ordered native shutdown/PID absence and natural helper idle shutdown/connection removal observed. Detached native exit code was not observed |
| Short default-Metal3 Lobby game | Jade Empress 1.41 rendered terrain, water, units, minimap and HUD; completed frame 331, native exit 0/PID absent and visible Lobby return. This is a short smoke check |
| DMG and ZIP | Both DMG and ZIP were opened independently; all 1,171 app file/link entries, bytes, modes and strict ad-hoc signatures matched inventory `6f8908ed…`. The actual Finder DMG layout showed the original artwork, one BAR.app and Applications shortcut at the configured positions. |

The final app uses native engines `27fa06c6…` (Chobby) and `794ced8b…` (bar-lobby), and MoltenVK `0e7c41b9` / packaged SHA `aebf0df5…`. The helper-fixed launcher changed the ASAR and its corresponding outer metadata/seals; native/runtime/helper and other resource bytes remain unchanged from the native-tested parent. No whole-app ASAR-equality claim is made across launcher revisions.

Native checks, actual menu handoffs, local game smoke and archive integrity are distinct observations. These bounded checks do not establish a complete session, new public-peer compatibility, clean-machine rebuild/install or a final-candidate performance gain. Historical human multiplayer and scoped Windows-reference shield comparisons remain separate evidence.

[Performance evidence](PERFORMANCE.md), [distribution](DISTRIBUTION.md), [source/provenance](SOURCE-STATUS.md) and [artwork/notices](ASSET-NOTICES.md) provide the supporting scope. Private gameplay/session logs, screenshots, settings and failed-attempt chronology remain outside the public export.

## Known limits retained in the audit

The recorded post-update dependency audit still reported nine production-graph package entries (eight high, one moderate), plus development/build findings. Package counts are not counts of independently reachable vulnerabilities. Source and final-bundle review distinguished SSR-only Vue findings, build/compiler chains and bounded runtime callers; the audit does **not** claim zero vulnerabilities or universal exploit resistance. The scoped Electron/axios/WebSocket/Markdown/XML corrections are included without a blanket framework update.

The Chobby checks retained Lua errors in `api_analytics.lua:83` and `gfx_limit_idle_fps.lua:161`; ordered shutdown and natural helper cleanup still completed. The pinned game's content/deprecation warnings are also retained. These passing entry/exit checks do not mean that the game/content logs are error-free. Metal4 was checked at native and Chobby-menu level on this artifact; the short final local-game smoke used Metal3.
