# Third-order comparison follow-up — 2026-10-20

This appends only new measurement evidence. Parent commit `02f362888c330665ceb15c6cebfedf33c985679b` and original restoration checkpoint `c99015f5f79b1bbb59a5bc0cc893446c0ff5005c` remain unchanged. Their source/app restore payloads and earlier measurements are retained. No app/source/restoration-script or stable release change is included.

| Batch | Backend order | App order within backend | Metal3 candidate change | Metal4 candidate change |
|---|---|---|---|---|
| First | Metal3 then Metal4 | parent-candidate-candidate-parent | +7.5851% | -9.7959% |
| Second | Metal3 then Metal4 | candidate-parent-parent-candidate | +2.1239% | +11.0092% |
| Third (this record) | Metal4 then Metal3 | parent-candidate-candidate-parent | +1.1957% | -3.6348% |

Each cell is a separate batch with two samples per app/backend; do not pool these percentages or present stable improvement/regression, statistical significance or order-only causality. In this third batch Metal3 parent/candidate means were48.9888305664/49.5745964050FPS and Metal4 means43.9154357910/42.3192062378FPS. First-batch unlocked-console versus subsequent locked-console policy, elapsed time, global driver/filesystem caches, OS work and small samples limit attribution. C-T/C-M3 effects were not separated and no vertex cache was included.

The [owner report](evidence/reports/v104-descriptor-performance-order3-20261020.md) and [summary](evidence/artifacts/validation/v104-descriptor-performance-order3-20261020/summary.json) retain all eight samples, earlier batches separately, FPS/p95/p99, scene, runtime mapping and limits. All eight succeeded in one pass, with no failure or retry. The same read-only Lobby readiness stabilization used by the preceding successful continuation was reused. App/controller/measurement logic remained unchanged. No completed sample was replaced.

Conditions: same two frozen1.0.3-metadata apps (P1/P2/P3+B versus +C-T/C-M3), AC + LowPower ON, thermal0, Ultra/AAOff/Spring,1432x902,900 simulation frames and fresh private shader caches. Locked console remained permitted and `consoleLockStates=['True']` was observed. The publisher did not rerun the game or change screen/authentication settings.

Included: preparation, authorization, scripts/controller, screen observations, original outcome, all eight successful execution receipts, raw benchmark results/native logs and eight cache-cleanup selections/completions. Cleanup accounted for48roots/2666leaves/76,971,000logical bytes, not isolated physical APFS reclaim. The publisher performed no cleanup. Removed private shader/browser caches and content clones are excluded; their historical paths are not restoration prerequisites. The redundant large content-file inventory is excluded. Original/exported SHA256 pairs in `evidence-index.json` disclose workspace-path normalization to `$WORKSPACE`/`$HOME`.

Owner full1194-entry app inventories and source/launcher/user-pin checks passed, all owned test processes exited, and screen/awake state was restored. Publisher source/build/selected-app and actual launcher HEAD/index/dirty pins are checked before/after; original checkpoint blobs and master/stable tags/releases/Homebrew are checked unchanged. No new game, rebuild, app/source payload upload, install or product edit is performed. Existing [restoration instructions](../../README.md) apply unchanged.
