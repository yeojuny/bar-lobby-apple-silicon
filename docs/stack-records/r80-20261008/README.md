# BAR Apple Silicon: R80 source checkpoint

Recorded on 2026-10-08 in the owner's GitHub fork. This preserves the cumulative **Recoil engine + Mesa/Zink + MoltenVK** source changes used by the R80 candidate, their exact upstream bases, build inputs, and bounded validation results. It is a source checkpoint, not a new binary release or an upstream submission.

## What is preserved

| Component | Exact upstream base | Cumulative changed files | Patch |
|---|---|---:|---|
| Recoil / Lobby engine | `694e9df7cf5068aef2cdebbf5e6587d539344001` | 77 | [engine-r80.patch](patches/engine-r80.patch) |
| Mesa, including Zink | `45019c28811991cc02f87f0360235b8e4c369155` | 26 | [mesa-r80.patch](patches/mesa-r80.patch) |
| MoltenVK, Metal3 and experimental Metal4 | `52aa21f54d7a84c5c441fc26359692b0980b384c` | 69 | [mvk-r80.patch](patches/mvk-r80.patch) |
| Engine dependency compatibility | Exact individual commits in manifest | 3 | BARb, CircuitAI and streflop patches in [patches](patches) |
| SPIRV-Cross | `aa217aeb6c9f0ace7a0ab233b28807edf45eb165` | 7 | [mvk-dep-SPIRV-Cross-r80.patch](patches/mvk-dep-SPIRV-Cross-r80.patch) |

All **182 changed files** were checked against the pinned source inventories associated with the R80 components. Each patch was applied to its exact upstream file preimages, and the resulting bytes matched the recorded target source. The current engine's later font edit was deliberately replaced with the preserved R80 preimage during export; its reviewed follow-up is recorded separately below.

These are cumulative patches against upstream: they include inherited macOS adaptations and selected upstream contributions as well as this optimization series. They are not 182 new performance fixes. Dependencies without changes are also pinned in [source-record.json](source-record.json). Symlinks and executable modes are retained in the patches.

## Entry points

- [Change overview and status](CHANGES.md)
- [Source commits, file hashes, patch hashes and application checks](source-record.json)
- [Build options, compiler/SDK identity, dependency commits and packaged binary hashes](build-inputs.json)
- [Restoring the source checkpoint](RESTORE.md)
- [Historical upstream intake and attribution](provenance/run95-intake.json)
- [Performance data](evidence/performance.json) and [validation scope](evidence/validation.json)
- [SHA-256 checksums of the record files](SHA256SUMS)

The Mesa value `95e64e515a507f6536b7be30a39aee1cc1e443ca31338916ac7150afcf24151a` is a locally derived build/content digest, **not an upstream Git commit**. The upstream Mesa base is the 40-character commit in the table. Mesa **!40962 is excluded**.

## Performance evidence

Same comparison series on 2026-10-07: AC connected, low-power mode enabled, reported thermal state 0; Seths Ravine Remake 1.3.1; `test-31479-433a460`; Ultra, CUS GL4, 4x MSAA, VSync off, 1432×902. Each arm started with an empty dedicated Mesa cache. Measurement covered frames 240–1140, approximately 30 seconds. OS Metal caches were not cleared.

| Stack | Backend | Mean FPS | p99 frame time (ms) |
|---|---|---:|---:|
| RUN95 + VBO | Metal3 | 36.6598 | 41.897 |
| r58 | Metal3 | 43.5240 | 49.159 |
| r58 | Metal4 | 36.6486 | 55.878 |
| r78 | Metal3 | 46.5778 | 42.000 |
| r78 | Metal4 | 41.4821 | 48.842 |
| r80 | Metal3 | 46.5279 | 42.886 |
| r80 | Metal4 | 42.0438 | 47.153 |

R80 Metal3 observed **+26.92% mean FPS over RUN95+VBO Metal3** in this series. R80 Metal4 remained **9.64% below R80 Metal3**. This is a whole-stack comparison, not attribution of the gain to MoltenVK alone, and not a statistical guarantee: one sample per arm, fixed order, no excluded samples. R78 and R80 use the same engine and Mesa; their measured difference isolates the changed MVK artifact more closely, but still has run-to-run uncertainty.

## R81 font follow-up: reviewed, not integrated

[r81-font-candidate.json](r81-font-candidate.json) and the two `r81-*.patch` files preserve the subsequent fallback-font filename and initial Fontconfig cache fixes. CPU tests and an independent review passed. They are **not part of R80's binaries or performance measurements**. Applying the two patches requires different roots, documented in RESTORE.md. App integration and actual font/UI validation remain pending.

## Boundaries and attribution

The rendering path is Recoil OpenGL → Mesa/Zink → Vulkan → MoltenVK → Metal. CUS GL4 and explicit Run57 NoGS presentation are preserved; an exposed GL/GLSL version is not evidence of Geometry Shader support. Native Metal4 commands are an experimental opt-in in this MVK fork, distinct from merely selecting a newer Metal shader language.

The R80 Lobby engine contains cumulative local changes. The Chobby engine remains the separately pinned official-version lane; sharing Mesa/MVK does not mean the optimized Lobby engine was ported to Chobby. Cross-platform multiplayer determinism is not certified by these graphics tests. The record includes retained dependency compatibility changes and must not be advertised as a rendering-only patch against every upstream file.

Patches retain original project attribution and licensing. See [licenses](licenses), exact source repositories in the manifest, and the historical intake record. Upstream contributors' retained changes are not claimed as original work here. This work and record were AI-assisted. No upstream issue, pull request, or endorsement is implied. Private match logs, game assets, user settings, credentials and binaries are not included.
