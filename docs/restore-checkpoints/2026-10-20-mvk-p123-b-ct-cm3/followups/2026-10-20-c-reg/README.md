# C-REG implementation restoration follow-up — 2026-10-20

This appends frozen **P1/P2/P3+B+C-T+C-M3+C-REG**, still displaying1.0.3 and described only as a local experimental1.0.4 candidate. Parent commit `45e1bc37ccb68b95b630666497813c9bd1b95603` and every previous checkpoint file remain unchanged. This is not a stableRelease/Homebrew update.

The [handoff](evidence/artifacts/validation/v104-c-reg-20261020/github-handoff.json), [exact selection](evidence/artifacts/validation/v104-c-reg-20261020/restoration-selection.json), [report](evidence/reports/v104-c-reg-20261020.md) and [final completion](evidence/artifacts/validation/v104-c-reg-20261020/completion.json) bind the frozen state. All269 selected files/33,346,511bytes are preserved without prose/path normalization, including original0644/0755 file modes. The selection manifest and handoff are included separately if not already selected. `evidence-index.json` records these exact bytes. Content inventories are metadata, not game content or user profile contents.

## Scope, review and validation

C-REG carries known Buffer/Texture provenance into fresh resource registration and residency fallback while retaining generic entry behavior and ownership/lease/drawable/retirement requirements. It adds no allocator/pass/sync adjustment or cross-recording ownership sharing. Four product files and two existing fixtures, all six preimages and their patch are included; the [independent review](evidence/artifacts/validation/v104-c-reg-20261020/independent-review.json) found no actionable finding within its bounded source/evidence scope. CPU410 assertions, related native6, syntax6, prepared native6 and common Metal3/4 cycles are existing owner results, not publisher reruns. Prior fixture compile failures and their limitations remain recorded.

Original early package/validation receipts contain stage-time pending/unmeasured fields. They are preserved unchanged. Final completion, independent-review and comparison summaries record later completion; no early record was rewritten into a later acceptance claim.

## Comparisons kept separate

| Condition | Metal3 parent/candidate mean FPS | Change | Metal4 parent/candidate mean FPS | Change |
|---|---|---|---|---|
| Initial windowed1432×902 |48.1611 /48.1859 |+0.0516% |39.1514 /40.3943 |+3.1746% |
| Fullscreen-intent reverse1512×950 |49.5789 /49.1481 |−0.8689% |44.0696 /45.4144 |+3.0515% |

Each condition has eight completed sessions, two per app/backend. [Windowed summary](evidence/artifacts/validation/v104-c-reg-performance-20261020/comparison-summary.json) and [fullscreen reverse summary](evidence/artifacts/validation/v104-c-reg-fullscreen-reverse-20261020/comparison-summary.json) retain their own orders, samples and p95/p99. Do not pool these conditions or infer statistical significance, universal net benefit, stable improvement/regression or an other-Mac/MP guarantee.

For fullscreen, game `Fullscreen=1` and actual SDL fullscreen intent/flags were verified with a1512×982 container and1512×950 safe viewport. The native window was hidden: SDL defers actual display/Space presentation while hidden. This is **not physical Retina resolution or proof of visibly presented fullscreen gameplay**. Keep that limit when describing the result.

## Source and exact signed-app restoration

First use the existing [source/app restore instructions](../../README.md) to obtain a **fresh descriptor** source/app from the publicv1.0.3 basis. `restore-manifest.json` binds each of the six source/fixture preimages and postimages. In the fresh MVK `moltenvk-1.0.0` source tree only, verify the four current file hashes against `beforeSHA256`, then replace their component-relative paths with the corresponding `postimage` payloads. This applies C-REG after B+C-T+C-M3. Copy the two changed fixture files into a copied workspace's tools/tests using their declared paths; their exact originals remain available. The supplied workspace-relative `c-reg.patch` records the same six changes. Do not apply it to active source/build directories or infer a new dependency upgrade. Retain the earlier full wrapper's component licenses, compiler/numeric flags and build configuration.

For exact app bytes, restore the earlier **descriptor** app with the original `restore-app.py`, then use this followup's helper:

```sh
python3 restore-c-reg-app.py --base-app /path/to/restored-descriptor/BAR.app
python3 restore-c-reg-app.py --base-app /path/to/restored-descriptor/BAR.app --out /NEW/path/BAR.app
```

Without `--out` it verifies the existing1194-entry basis and three selected payloads only. With a fresh `--out`, it creates a new copy and overlays exact signed launcher/MVK/CodeResources bytes, verifies the final1194-entry inventory and strict nested signature on macOS. It never signs, launches or installs an app. `app-restore.json` binds both inventories and all three paths. No engine or launcher implementation change is introduced by copying signing bytes. Arbitrary extended attributes/quarantine are outside the file-content claim.

The raw rebuilt MVK is preserved under `evidence/build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib`; its packaged install-name/signing output is a separate selected app payload. Hashes and the owner's original package script/closure receipt explain this association. Source restoration and exact signed-app restoration are separate choices; the publisher did not recompile or reconstruct another full app. Removed private content clones/caches are historical paths, not restoration inputs. Automation remains PAUSED; master/stable tags/releases/Homebrew and actual launcher HEAD/index/status are preserved.
