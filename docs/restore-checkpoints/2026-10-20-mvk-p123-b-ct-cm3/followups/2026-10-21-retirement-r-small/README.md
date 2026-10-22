# Restore the v1.0.4 experiments from retained R or Small

This follow-up preserves the experimental application states and their source/performance history before local retirement. It appends to `restore/mvk-20261020-p123-b-ct-cm3` at parent `90948f178d8194828d024b2278268633a11ef9b0`. It does not update master, stable tags, releases, Homebrew, installed applications or the active source/build trees.

**Keep local R and Small. Thirteen other existing v104 app bundles are retirement candidates only after publication and independent remote verification.** The signed apps still display version 1.0.3; the v1.0.4 names identify local experiments, not a published release.

## What is preserved

`app-restore-manifest.json` defines each target as an overlay on either retained R or retained Small. Each original has 1,194 regular-file/symlink entries, including file permissions, SHA-256 hashes and symlink targets. The 30 virtual overlays include 26 paths to the thirteen older apps, two R/Small cross-restorations and two identity checks. Every virtual result matches its actual original inventory. Strict nested signatures of the existing originals were inspected successfully.

| App directory under `artifacts/runtime/` | State |
|---|---|
| `v104-performance-candidate-20261020` | Initial P1–P3 performance candidate |
| `v104-performance-ab-candidate-20261020` | Combined A/B follow-up candidate |
| `v104-descriptor-candidate-20261020` | Earlier descriptor candidate |
| `v104-typed-buffer-callers-candidate-20261020` | C, typed Buffer callers |
| `v104-lookup-descriptor-release-20261020` | D, combined lookup/statistics changes |
| `v104-d-split-lookup-only-20261021` | D lookup-only split |
| `v104-d-split-stats-only-off-20261021` | D statistics-only split |
| `v104-e-structure-allocator32-20261021` | E with allocator count 32 |
| `v104-e-structure-candidate-20261021` | E with allocator count 64 |
| `v104-quiescent-allocator-candidate-20261021` | Q, quiescent allocator policy |
| `v104-r-combined-candidate-20261021` | R plus combined changes |
| `v104-r-group-locator-candidate-20261021` | R plus group locator |
| `v104-r-combined-group-locator-candidate-20261021` | Combined plus group locator |
| `v104-idle-first-allocator-candidate-20261021` | R, retained locally |
| `v104-r-small-bundle-candidate-20261021` | Small, R plus bounded reserve, retained locally |

There is no full-app archive. Identical overlay files are deduplicated. Existing immutable payloads at the parent commit are reused, including older signed engines. This follow-up adds 42 distinct payload files totaling 95,208,036 bytes; five existing payloads totaling 73,036,382 bytes are referenced. Most targets change only the MoltenVK library and two signing-related files. Earlier engine variants need five changed files. Existing app license/notices and other common files remain in the retained base app.

## C and the earlier A/B restore chain

The C inventory is exactly the same 1,194-entry basis preserved by the earlier [A/B/C retention checkpoint](../2026-10-20-abc-retention/README.md). Restore C from R or Small with this helper, then use that checkpoint's `restore-from-c.py` to recover its A or B. The original A/B restoration material is unchanged. Removing a local C bundle therefore does not remove the old A/B restoration basis.

C's notable Metal3 observation is preserved separately: **56.211063385010 and 56.965129852295 FPS, paired mean 56.5880966186525 FPS**, n=2 in that comparison. See `performance-index.json` and the public projections of the original receipts. This was the Seths Ravine Remake 1.3.1 benchmark, 900 simulation frames, fixed seed/camera, hidden fullscreen rendering and the recorded quality/power conditions. It is a historical observation, not proof of a stable causal speedup or a promise that a restored app will reproduce that FPS. Background load was not fully controlled, and prior sampled native-exit/timestamp uncertainties remain as recorded.

R/Small's original eight-run comparison is explicitly excluded from adoption (`useForAdoption=false`) because of possible background load; its projected decision record is included. The later idle forward/reverse retest was deferred. Pending runs are not counted as completed results. Comparisons keep their own execution order, conditions, sample size and limitations; unlike conditions are not pooled.

## Restore into a new directory

Obtain this entire follow-up directory from its eventual immutable published commit. Python 3 and macOS are required. Existing immutable payloads are downloaded anonymously from GitHub and verified by size, SHA-256 and Git blob identity. No credentials are used.

```sh
# Verify the exact retained base, obtain required payloads and check the virtual C result.
python3 restore-app.py --base-app /path/to/R/BAR.app --base-role R \
  --target v104-typed-buffer-callers-candidate-20261020

# Create C only at a fresh, nonexistent path whose parent directory already exists.
python3 restore-app.py --base-app /path/to/Small/BAR.app --base-role Small \
  --target v104-typed-buffer-callers-candidate-20261020 --out /new/path/C/BAR.app
```

The helper refuses an existing output or an output inside the base app. It checks all base entries before applying an overlay, verifies all target entries afterward and checks the existing signatures. It does not modify the base, sign, launch, install or change source files. Finder metadata, quarantine and arbitrary extended attributes are outside the file-content inventory contract.

Preparation verified original inventories, payloads and virtual overlays; it did **not** copy or reconstruct a full application or run a game. Helper syntax was checked without executing a restore. Remote anonymous byte/blob/mode verification and independent review are separate requirements before the owner retires apps.

## Source, fixtures and public evidence

`evidence-index.json` binds each selected local source/patch/review/result to its original hash and public exported hash. The collected preimages, postimages, versioned source states, fixtures, build settings and related validation results preserve the implementation journey. `source-snapshots/state-pins.json` pins current Small and retained R's changed source. Unchanged full source trees and earlier implementations remain available through the existing checkpoint chain and the corresponding published 1.0.3 source distribution. A clean build of every historical state was not repeated or newly certified here.

Public text uses `${WORKSPACE}`, `${HOME}` and `${TMPDIR}` (plus `${THREAD_ID}` for internal chat identifiers) in place of local absolute prefixes. These source/configuration examples require appropriate variable expansion or workspace adaptation before use. Original hashes make this normalization explicit; normalized files are not falsely described as byte-identical originals. Numeric benchmark data is preserved. Public execution receipts are field projections: their original local hashes remain recorded, while private profile contents, foreign-process metadata, credentials and internal chat identifiers are omitted. Complete private session directories are not published.

The held 147 historical test-reproduction cases are outside this retirement/publication unit. Unapplied 11a and #2837 design records remain explicitly unapplied; their presence does not claim implementation or a measured benefit.

## Retired legacy source wrappers

`storage/public-wrapper-retirement-index.json` records eight obsolete distribution source wrappers, totaling 2,992,273,249 compressed bytes, retired by the storage owner. Their 1,136 regular-member occurrences and semantic TAR metadata were preserved locally; 180 newly deduplicated files occupy 6,363,072 bytes. This checkpoint includes only that small public summary, not the local retained-member store or private profile-protection records. It does not promise reconstruction of the original outer gzip/TAR bitstream. The current 1.0.3, rollback 1.0.1 and 1.0.2 wrappers, 19 canonical source archives and the held 147 test-reproduction cases remain outside that retirement.
