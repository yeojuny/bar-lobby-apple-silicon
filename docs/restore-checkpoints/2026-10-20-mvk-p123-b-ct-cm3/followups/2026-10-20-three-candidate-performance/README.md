# Three-candidate performance evidence — 2026-10-20

This appends only a frozen12-session comparison after commit `146bce2cbd060b15eb708c5bba68e27042471a8a`. All prior source/app checkpoints are unchanged. There are no product/source/app binary changes or duplicate app payloads. Each candidate still displays1.0.3 as a local cumulative1.0.4 experiment.

| Candidate | State | Metal3 mean FPS | Metal4 mean FPS |
|---|---|---:|---:|
| A | C-REG before drawable-size |46.0853 |39.4916 |
| B | A + live window/drawable size query |51.5120 |45.4710 |
| C | B + typed Buffer registration callers |51.5526 |46.6882 |

Within this new batch B/A is+11.7753%/+15.1412% (Metal3/4), C/B+0.0788%/+2.6767%. **n=2 per app/backend**; descriptive means do not establish statistical significance, guaranteed net benefit or universal performance. Earlier concurrent-workload FPS is not pooled with this comparison. OS/background/global driver/filesystem load is not completely controlled.

Read the exact [report](evidence/reports/v104-three-candidate-performance-20261020.md), [summary](evidence/artifacts/validation/v104-three-candidate-performance-20261020/comparison-summary.json) and [completion](evidence/artifacts/validation/v104-three-candidate-performance-20261020/completion.json). The selection preserves150files/13,652,809bytes: all three full app inventories, plans/hosts/controller,12 original results/receipts/infolog/hidden events/loaded runtime and exit evidence, power/screen/cleanup records. Original bytes and0644/0755 modes are kept without normalization. The source selection/handoff plus small binding/navigation metadata are separate additions; actual user settings/profile bytes, app binaries, game-content archives and private caches are excluded. `content-files.json` is metadata, not content bytes.

## Conditions and limits

All12 owner sessions exited normally;110 power observations confirmed AC+LowPower with thermal0. The same seed/map, Ultra/AAOff/Spring/VSyncOff/soundOff, requested/default1x and900 simulation frames(240→1140) were used, with a fresh private shader cache. The actual safe fullscreen viewport was1512×950 while hidden. SDL defers native display/Space presentation while hidden; this is not validation of visible native fullscreen/Space transitions or physical Retina modes. Power/scene/loaded-runtime checks and original screen-idle/owned-awake restoration are preserved. All app/source/launcher/user pins were checked by the owner.

These12 normal exits **do not resolve the cause of the earlier sampled native-exit failure**, and do not fix or qualify the exact-baseline Metal3 native-fixture timestamp host/GPU mismatch. No new sampling or diagnostics were used. Source checkpoint qualification remains as originally recorded; no stable-release promotion or broader gameplay/MP/other-Mac guarantee follows.

## Restore exactly the compared apps

`app-checkpoint-bindings.json` maps A/B/C to immutable existing restoration commits. All three selected1194-entry inventories were independently compared to the corresponding earlier restore inventories. Follow [C-REG](../2026-10-20-c-reg/README.md), [drawable-size](../2026-10-20-drawable-size/README.md) and [typed Buffer](../2026-10-20-typed-buffer-callers/README.md) recipes, starting from the [original publicv1.0.3 basis](../../README.md). There is no need for a new app archive or source/build export to recover these states. Old source/patches/signed overlays and metadata remain unchanged.

Owner cleanup retired only private shader/browser caches72roots/3996leaves/115,443,398logical bytes; content clones have separate receipts. This is not physical APFS reclaim. Removed paths are historical references, not restoration inputs. Publisher performs no cleanup, new game/test/build/install, full app copy/reconstruction, settings/profile/source/AGENTS edit or automation change. Actual launcher HEAD/index/dirty state and source/build/fixture pins and protected remote master/tags/releases/Homebrew are verified unchanged. Automation remains PAUSED.
