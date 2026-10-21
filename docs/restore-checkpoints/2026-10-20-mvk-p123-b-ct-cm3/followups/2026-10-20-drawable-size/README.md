# Live window/drawable size restoration follow-up — 2026-10-20

This appends the frozen two-lane viewport/scissor size-query change on top of P1/P2/P3+B+C-T+C-M3+C-REG. It retains1.0.3 display/sync metadata and remains a local cumulative1.0.4 candidate. Parent commit `7a3a24591f75d53a9022487a3f2e25d3d5c05afa`, all prior checkpoint blobs, master/stable tags/releases/Homebrew remain unchanged.

**Source completion status remains `implemented-reviewed-compared-observation-exit-unresolved`. Do not relabel it as all-runtime-validation-passed.**

## Exact payload and restoration

The [selection manifest](evidence/artifacts/validation/v104-drawable-size-20261020/restoration-selection.json) binds188files/86,534,824bytes. All selected bytes and0644/0755 modes are preserved without path/prose normalization. The manifest/handoff and small navigation/restore metadata are added separately. No entire app, raw engine duplicate, game archive, actual user profile or cache contents are added. Selected content inventories and cleanup paths are metadata/historical references.

Use the [original restoration instructions](../../README.md), then the prior [C-REG followup](../2026-10-20-c-reg/README.md) to reconstruct the exact C-REG basis. This followup changes exactly four signed files: Lobby engine31,276,160bytes, Chobby engine34,960,000bytes, signed launcher executable and CodeResources. Each engine is below100MB. The two source lanes retain official sync identities; launcher implementation, translation stack and settings remain unchanged. `app-restore.json` binds the full1194-entry basis and result inventories plus four payload paths.

```sh
python3 restore-drawable-size-app.py --base-app /path/to/restored-c-reg/BAR.app
python3 restore-drawable-size-app.py --base-app /path/to/restored-c-reg/BAR.app --out /NEW/path/BAR.app
```

Default verifies basis/payloads only. With a fresh output path the helper copies the basis, overlays four exact signed files, verifies all1194 entries and strict nested signature on macOS. It never signs, launches or installs. File/link bytes and file modes are bound; arbitrary xattrs/quarantine are not. The publisher syntax-checks this helper but performs no app copy/reconstruction.

For source restoration, obtain fresh descriptor sources from the original wrapper and apply the existing C-REG overlay to its MVK component. Then use `restore-manifest.json`'s six `sourceTransitions`: for each Lobby/Chobby component-relative path verify `beforeSHA256` and replace it with the exact `postimage`, retaining its mode. Each lane changes only MacSDL3EGLBridge.h/.mm and GlobalRendering.cpp. Corresponding preimages and `applied-source.patch` are selected. Do not apply this to active source/build trees. The retained wrapper supplies unchanged dependency sources/licenses/compiler/numeric configuration. Owner native-build receipts bind raw engine hashes to relocated/signed package hashes; raw engine copies are intentionally not duplicated here.

## Existing checks, not publisher reruns

The [owner report](evidence/reports/v104-drawable-size-20261020.md), [completion](evidence/artifacts/validation/v104-drawable-size-20261020/completion.json) and [independent review](evidence/artifacts/validation/v104-drawable-size-20261020/independent-review.json) preserve six source changes and extracted source-bound existing display fixtures:102 CPU assertions per lane with ASan/UBSan, two native incremental builds, AstraHigh PASS/no actionable findings,1194 app entries/211 closure edges/strict nested signing. Assertions use SDL/Cocoa/GL doubles and are not102 native display-transition scenarios. Real monitor movement and native fullscreen Space transitions were not verified. Original stage-time pending fields are retained rather than rewritten.

## Reference FPS and unresolved separate observation

Eight interleaved comparison sessions exited normally under AC+LowPower ON, game fullscreen hidden1512x950,Ultra/AAOff/Spring. The user confirmed concurrent other work, so FPS is **reference only**, not isolated code net effect or a proven improvement. Metal3 means43.3320→50.2745(+16.0216%); Metal4 means33.1134→32.5977(−1.5575%); n2 per app/backend. Keep this condition separate from previous batches. Native macOS display/Space presentation is deferred by SDL while hidden; no physical Retina/display-move claim is made.

One **separate OS-sampled observation failed the15-second native exit callback/PID-absence check**. Sampling and the900-frame benchmark completed; the sampler itself exited normally before quit was requested. The cause remains unresolved between product difference, sampler effects and simultaneous work; do not assign blame. Original failed receipt/events/infolog/controller request+status/sample and exit-boundary analysis are preserved by the exact selection. This run is excluded from FPS tables **and runtime acceptance**. Its private failure profile/cache are retained locally, not uploaded or removed by this publisher. All owned processes are now absent according to the owner completion. Only successful eight-run caches48roots/2662leaves/76,955,677logical bytes were retired; this is not a physical APFS reclaim measurement.

Publisher work is limited to selected-file hashing/copying, fresh-index branch publication and anonymous2-worker byte/tree/mode readback. No new build/test/game/install/cleanup/automation or product/active-source/app/user-profile edit is performed. Actual launcher HEAD/index/dirty state and frozen inputs are checked before/after. Original raw evidence bytes and all previous checkpoint records remain unchanged.
