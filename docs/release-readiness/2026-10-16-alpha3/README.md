# 0.15.4-alpha.3 downloader shutdown fix

Unsigned experimental Apple Silicon/macOS 27 release. This update changes launcher shutdown only; native engines, graphics runtime, peer versions, simulation flags, NoGS payloads and renderer defaults are unchanged from alpha.2.

## Behavior

Previously, closing the launcher while an automatic game download was active could leave pr-downloader running. Both ordinary app quit and the explicit Chobby parent handoff now stop new content writes and drain this parent's registered downloaders before the parent exits. Queued content publication is canceled through the existing shared writer queue. Detached Chobby menu/helper ownership and natural helper idle shutdown are preserved.

A registered live downloader first receives SIGTERM. A two-second courtesy interval permits SIGKILL escalation. A five-second final close/drain deadline reports failure and keeps the launcher alive; it does not discard ownership or declare cleanup complete. These are shutdown policy bounds, not performance thresholds. Error, exit and a successful signal request do not count as child/pipe close. Concurrent quit requests share one drain.

This handles the launcher's normal quit lifecycle. Force Quit, an external SIGKILL, loss of power and unrelated processes are outside this guarantee. The shutdown latch stays closed after a failure so late downloads cannot be admitted behind a failed quit.

## Evidence

Existing main lifecycle unit tests passed 34/34; source CPU fixtures passed 17/17 and actual packaged-method integration passed 10/10 under Node 22.18. Node TypeScript checking passed. Fixtures preserve all original cases and exercise admission races, close ownership, repeated quit, escalation/deadline behavior and detached owner preservation. Packaged integration evaluates the exact three compiled writer methods and one verbatim compiled coordinator instance; it does not execute Electron or replace production methods.

The final packaged app was started hidden with isolated state. Its automatic byar:test downloader was observed alive, then ordinary app.quit was requested. That downloader exited by SIGTERM before launcher exit 0; no test cleanup intervention was needed and no owned process remained. No native game was launched for this focused check.


Both alpha.3 Chobby renderer-mode menu checks passed with current official test-4659-5fb5727 / game metadata test-31657-2f0a840: reviewed ordinary menu pixels, genuine helper connection, parent exit 0, ordered native shutdown/PID absence and natural helper idle shutdown/connection removal, with zero owned processes and no forced test cleanup. Metal4 emitted its actual native command-backend activation and queue-retirement messages. These are menus only; no multiplayer game or detached native exit-code claim.

Both native binaries and shared runtime match alpha.2 byte for byte. The 309-edge native static closure is carried forward only after matching all 39 unique payload files; existing SDL dummy hidden-contract checks passed for both lanes. Independent source review found no actionable issue after the final shutdown deadline was added. Installer, source and notice archive identities are recorded in validation.json and SHA256SUMS.

Alpha.2's historical Metal4 game shutdown failure is retained. Its rendering results are native-payload evidence only; no old game is relabeled a complete alpha.3 lifecycle pass. No new benchmark, product observer, diagnostic probe, native build, game, FPS/energy result, full multiplayer, endurance, physical iMac transition or clean-machine acceptance is claimed. Ad-hoc signatures provide integrity but are not Developer ID signing or notarization. Existing dependency audit and provenance limitations remain in the earlier release-readiness documentation.

The app version is alpha.3. The unchanged native window caption continues to identify its alpha.2 compatibility build, R95 + VBO + R4. The ordinary workspace BAR.app, earlier releases, user settings/content and native Metal4 port are preserved.
