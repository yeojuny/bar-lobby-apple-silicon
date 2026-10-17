# r73 / r75: separated Lua VBO review series

The two patches reduce avoidable CPU preparation in the shared Recoil renderer. They do not implement a Metal4 backend, change the simulation, or remove required GPU completion. This is a **port-relative review series**, not an assertion that it applies directly to current official Recoil.

| Record | Scope | Port status | Local validation | Official Recoil status |
| --- | --- | --- | --- | --- |
| [r73](R73.md) / [patch 1](0001-r73-direct-lua-number-upload.patch) | Lua numbers directly into the existing CPU shadow, through the existing conversion core | Equivalent methods present in published candidate.4 sources | Existing CPU fixture rerun; exact function association recorded | Not submitted by this project as an individual PR; no official approval claimed |
| [r75](R75.md) / [patch 2](0002-r75-typed-instance-upload.patch) | Typed instance upload; excludes the separate Matrix optimization | Equivalent methods present in published candidate.4 sources | Current integrated instance methods are byte-identical to those checked by the existing full CPU fixture | Not submitted by this project as an individual PR; no official approval claimed |

## Exact base and prerequisites

The complete upstream ancestor is `694e9df7cf5068aef2cdebbf5e6587d539344001`, **plus pre-r73 local port changes**. The two exact historical preimage files are included under [base/](base/). Their hashes, both intermediate postimages and every extracted method hash are in [validation.json](validation.json). [Published-source association](published-source-association.json) verifies the current CPU-tested file against the exact candidate.4 source archive. The base is a two-file review input, not a complete engine checkout or a new runnable app.

The base already includes the port's VBO layout/padding, partial-attribute upload, Download and index-restart ownership contracts. Do not replace it with plain upstream files and assume equivalent behavior. Patch 1 folds in the later post-`__len` callback ownership/storage/layout checks; patch 2 keeps the later instance callback revalidation and transactional multiple-ID staging. Old uncorrected r73/r75 diffs are not offered as the safe current implementation.

Apply patch 1 then patch 2, in the order in [series](series). This order is a reproducible extraction dependency; it does not mean typed instance copying intrinsically requires direct Lua-number iteration. Header-guard-only cleanup and Matrix/projectile changes are excluded.

To examine the series without editing an installed app or your engine checkout, copy this directory's `base` folder into a disposable review folder. From that copied folder, use the absolute paths to the patches:

```sh
git apply --check /absolute/path/0001-r73-direct-lua-number-upload.patch
git apply /absolute/path/0001-r73-direct-lua-number-upload.patch
git apply --check /absolute/path/0002-r75-typed-instance-upload.patch
git apply /absolute/path/0002-r75-typed-instance-upload.patch
```

Rollback uses `git apply --reverse` in reverse order: patch 2, then patch 1. Application checks, exact postimage checks, and byte-exact restoration of the base passed locally. Integrating into another engine requires rebasing the narrow changes while retaining its layout/ownership contracts, then running that engine's checks.

## What was validated on 2026-10-17

- The separated two-patch artifact passed the existing real-Lua VBO CPU fixture: **1,218 cases / 24,860 assertions / 0 failures**, with ASan/UBSan.
- The current integrated source passed the existing full CPU fixture: **2,024 cases / 41,666 assertions / 0 failures**, including 391 paired internal calls and Lua callback cases.
- Nine relevant method bodies in the separated result, including both instance overloads, the typed helper and ownership checks, are byte-identical to the current production methods. This associates the instance tests with the extracted code. The existing internal fixture also exercises Matrix functions; those functions are not included in this narrow series.

The fixtures substitute object lookup/GL storage and do not compile a complete engine. The historical base plus split result has not received a new full native build, independent extraction review, GPU/game check, FPS measurement or multiplayer acceptance. Earlier reviews and runtime checks retain their exact historical scope. No new test harness, benchmark, instrumentation or app was introduced for this publication.

## Attribution and license

The surrounding engine is Recoil/Spring and retains its GPL-2.0-or-later license and original notices; see [LICENSE](LICENSE). r73/r75 implementation records describe work performed in this port, without asserting worldwide novelty. Earlier r57 optimization ideas were informed by benbreen's port; r58 added local lifetime/alignment corrections. [Full provenance and performance boundaries](ORIGIN-AND-PERFORMANCE.md).
