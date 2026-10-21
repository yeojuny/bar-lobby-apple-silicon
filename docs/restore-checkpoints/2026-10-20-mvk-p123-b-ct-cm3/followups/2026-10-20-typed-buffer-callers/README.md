# Typed Buffer caller restoration follow-up — 2026-10-20

This appends a frozen three-file typed Buffer callsite change after drawable-size commit `7ca6c11f457f59681c0dde6a927aabea24ac9c50`. All previous checkpoint blobs remain unchanged. App metadata is still1.0.3, a local cumulative1.0.4 candidate. Stable master/tags/releases/Homebrew are untouched.

The [exact selection](evidence/artifacts/validation/v104-typed-buffer-callers-20261020/restoration-selection.json) binds75files/8,959,515bytes. All selected byte sequences and0644/0755 modes are preserved, without normalization or original-record edits, together with the selection/handoff and small restore metadata. New raw MVK and compiled fixture executables are deliberately not duplicated. Selected source3 postimages/preimages/full patch, original fixtures/logs/receipts and invalid baseline attempt are retained. See [report](evidence/reports/v104-typed-buffer-callers-20261020.md) and [completion](evidence/artifacts/validation/v104-typed-buffer-callers-20261020/completion.json).

## Qualification retained

Existing owner checks: CPU410 assertions, syntax6, Metal4 **8 unique** cases (7 initial plus2 followup with one parallel byte-copy repeated), Metal3 common7; independent AstraHigh review found no actionable defect within its bounded scope. No new BAR game/FPS was run and no FPS gain is claimed. This does not mean every runtime check passed.

**Metal3 timestamp host/GPU/availability/padding mismatch remains unresolved.** It was reproduced on the exact prior raw library. The first invalid baseline override/loading attempt and subsequent valid exact-baseline receipt are both preserved; only the valid one supports reproduction. Baseline reproduction does not establish the mismatch's cause or fix. The earlier sampled BAR native-exit failure also remains unresolved; it is not closed by these checks. Full runtime acceptance/release approval are not claimed. Original package stage-time review-pending fields are preserved while the final independent-review/completion establish the later review result.

Owner-authorized cleanup retired4 successful-check executable/dSYM roots,8files/7,534,088logical bytes, with selection/completion receipts. Failed timestamp executable/symbols remain local, not uploaded as redundant payload. No physical APFS reclaim claim or publisher cleanup is made. Sources, fixtures, logs and original records are retained.

## Restore source or exact signed app

Use the [original restore instructions](../../README.md), then C-REG and [drawable-size](../2026-10-20-drawable-size/README.md) followups to obtain the fresh cumulative basis. `restore-manifest.json` identifies the three component-relative MVK source paths and their preimage/postimage hashes. In the fresh restored MVK tree verify `beforeSHA256` and overlay those three `postimage` files with their declared modes; `typed-buffer-callers.patch` preserves the same diff. Do not apply it to active source/build trees. Retain the original dependency/compiler/numeric/license coverage. Fixtures selected here are preserved inputs; temporary fixture edits were not retained as a new product change.

The exact app requires only **three signed files** from the drawable-size basis: MVK dylib, signed BAR executable and CodeResources. `app-restore.json` binds both1194-entry inventories. Native engines and launcher implementation remain unchanged. Use:

```sh
python3 restore-typed-buffer-callers-app.py --base-app /path/to/restored-drawable-size/BAR.app
python3 restore-typed-buffer-callers-app.py --base-app /path/to/restored-drawable-size/BAR.app --out /NEW/path/BAR.app
```

Default checks the complete basis inventory and payload hashes only. A fresh `--out` makes a new copy, overlays exact signed bytes, verifies all1194 entries and strict nested signature on macOS. It never signs, runs or installs. Arbitrary xattrs/quarantine are outside the byte claim. Publisher only syntax-checks the helper and performs no full app copy/reconstruction, new test/build/game/install/cleanup, shared-state or automation change. Actual launcher HEAD/index/dirty state, active inputs and protected remote state are verified before/after. Automation remains PAUSED.
