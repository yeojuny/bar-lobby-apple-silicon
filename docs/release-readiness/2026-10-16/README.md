# 0.15.4-alpha.2 compatibility update

This is an unsigned experimental Apple Silicon/macOS 27 prerelease. It addresses presentation compatibility with current official game content; it does not change the shared graphics runtime or the network engine identities.

The supplied iMac log used official game test-31653-ebba846. Its newer loader defaults nested Lua includes to archive-only access and sandboxes user widgets. The previous raw renderer adapter was therefore bypassed; raw Options and tracker replacements also lost required handler/callback access. This was not a Lua 200-local-variable compilation limit or a settings reset.

## Narrow changes

- A compiled, immutable presentation catalog supplies the already reviewed bundled widgets before the unmodified official widget sandbox selects trust. Only exact reviewed official handler/helper sources and fixed compiled payloads are admitted. Arbitrary user widgets keep the official sandbox. Unknown handler versions are not silently granted trust. This can require a future compatibility update when official loader code changes.
- Native Lua no longer advertises the geometry-stage-specific setter when the existing effective policy says GS is unavailable. OpenGL 4.6 and GLSL 460 remain available; CUS GL4 and accepted explicit NoGS implementations remain. Unsupported GS compilation is not the normal routing test.
- Fullscreen geometry uses the actual target screen bounds and real safe-area insets. Desktop workarea is separate; no laptop-model or resolution heuristic is applied to an iMac. Logical-input and drawable scaling are preserved. Physical iMac/multimonitor transitions still require user testing.
- The window caption identifies `BAR Apple Silicon 0.15.4-alpha.2 [R95 + VBO + R4]` and the actual base engine version. Network/replay engine identities are unchanged.
- Font delegation supports current pixel-size calls. Map-edge delegation accepts the current common vertex path. VBO correction applies only missing protections independently. Current CUS palette lookup preserves the official no-team sentinel, valid custom colors and bounded invalid-index fallback.

## Healthbars and known warnings

The supplied log successfully compiled the Health Bars NoGS shader, but blocked the unit tracker's LuaUI callbacks. That is evidence for a data-delivery defect, not proof that every missing bar has that cause. The widget also enumerates existing units at initialization. Positive tracker-to-healthbar CPU tests passed. Actual hidden Metal3 and Metal4 game screenshots now show the damaged unit's healthbar and the Settings entry. Full-health bars can intentionally be hidden by the existing visual policy.

The current official cursor code requests a missing area-attack asset, while the engine already supplies an attack-cursor backup. The warning alone does not establish an invisible cursor defect. No blanket cursor-behavior change or synced game-content edit is included. Upstream content warnings such as shield.energyupkeep, yardmap or optional map texture messages are not presented as fixed.

## Verification and limits

Independent source/package review found no actionable production issue in the compatibility changes. Existing CPU tests passed, both native lanes built, all 48 compiled presentation payloads match per engine, static dependency closure covers 309 edges, and DMG/ZIP readback matches the exact app. Existing SDL dummy hidden-window checks passed for both engine lanes.

The final app launched the Lobby lane with official test-31653-ebba846 on Jade Empress 1.41. In Metal3, the existing private damaged-unit scene showed a healthbar and Settings, preserved 20 effective Ultra options and 4x MSAA, initialized Nano/Energy NoGS without GS compilation failure, applied the CUS palette, and completed native exit 0, responsive hidden Lobby return, launcher exit 0 and zero remaining owned processes. Metal4 showed the same scoped pixels and functional checks, with an actual Metal4 command-backend activation message and native exit 0.

Metal4's overall lifecycle check failed: an automatic byar:test downloader was still active after the launcher exited and the test had to terminate that owned child. No remaining child was left running. The downloader binary and download/lifecycle source are unchanged from alpha.1, and the Metal3 automatic download finished before exit. This is an inherited timing-dependent download-on-quit limitation, not evidence that Metal4 rendering caused it. Do not treat the Metal4 run as a complete shutdown pass. Prefer letting active content downloads finish before closing the launcher.

Both Chobby renderer modes launched the current official menu test-4659-5fb5727 with game metadata test-31657-2f0a840. Each showed ordinary menu pixels, a genuine helper client, parent exit 0, ordered native shutdown/PID absence and natural helper idle shutdown/connection removal, with zero remaining owned processes. Detached native exit codes were unavailable and are not inferred. No account, room or multiplayer game action was performed. The current game package and menu closure were verified, and its widget-handler/shader-helper bytes match the compiled reviewed allowlist. Preparation attempts blocked by advancing official tags remain failures; only the final exact-bound menu runs count as accepted.

Earlier failed preparation, hidden-window guard and inspector-context attempts are retained as failed results; they are not silently relabeled successful. These short hidden checks do not establish complete effect-animation parity, a public multiplayer game, long-session stability, physical iMac fullscreen behavior or clean-machine installation.

The translation runtime is byte-identical to alpha.1. No new benchmark, diagnostic probe or instrumentation was added to the product. No FPS or energy improvement is claimed. Historical performance measurements remain in the previous release-readiness directory with their original conditions and slow results.

Matching source archives include complete native source snapshots, generated presentation headers, the existing generator and fixtures, and final launcher/overlay inputs. Build notes retain dependency-provider and bit-reproducibility limitations, including current FreeType build headers versus the unchanged packaged runtime. Legal notice payloads/dependency versions are unchanged; source-side alpha.2 mapping explains the historical package association in retained notice records.
