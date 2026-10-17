# Origin, chronology and measured performance

This work arose while investigating our MoltenVK-based Metal4 path falling behind Metal3. Shared renderer preparation was one investigation area; this does not establish an intrinsic Metal4 performance limit or assign all work to MoltenVK.

## External foundation and adaptation: r57

[benbreen/RecoilEngine-AppleSilicon](https://github.com/benbreen/RecoilEngine-AppleSilicon) is an independent unofficial macOS port. Its reviewed snapshot was [`a49a8ecc5265c4dd3f8d0016d90b32e81e22c73b`](https://github.com/benbreen/RecoilEngine-AppleSilicon/tree/a49a8ecc5265c4dd3f8d0016d90b32e81e22c73b). It uses Mesa/Zink/KosmicKrisp and SDL2; this port uses Mesa/Zink/MoltenVK and SDL3. The engine-side ideas can be relevant across those different translation backends.

Our r57 adaptation was informed by its 1ns→250µs fence waits, model-upload ring expansion (three→six by default on macOS), actual synchronous worker-entry QoS requests and unnecessary primitive-restart avoidance. These ideas retain that attribution. We did not wholesale transplant its display/readback path or simulation changes. Our restart optimization instead requires a narrow model-index sentinel proof and revokes that proof on relevant modification/exposure paths.

250µs is a wait timeout, not an unconditional per-frame sleep; completion remains required. A deeper ring consumes additional memory. QoS is a scheduling request, not a guarantee of P-core placement or higher FPS.

## Additional local corrections: r58

Review of our integrated stream-buffer path found that a bound slot may keep being read in unchanged frames, after its old fence. CPU reuse must account for the last actual read. We added bound-slot use tracking, distinguished pending reservations from issued fences, and required appropriate completion before overwrite.

The review also reproduced a CPU use-after-free when mapping failure/fallback destroyed fence storage still referenced by pending reservations. Teardown/resize/fallback now clear owned reservations safely. CPU mappings and GPU binding offsets were made consistent with aligned byte stride. Duplicate reservation work and unnecessary null-sync queries were reduced; completion failures are not treated as success. Existing teardown `glFinish` was retained.

These are local fixes/adaptations found during this work, not a claim that the concepts are unprecedented. r58 itself changed `StreamBuffer.h`, `StreamBuffer.cpp` and `ModelsDataUploader.cpp` relative to r57a. Its historical sanitizer fixture checked 13,205 conditions using a GL ordering model; that is not a real GPU test or proof that every legal GPU schedule was covered.

## Later local upload work: r73 / r75

r73 removed the intermediate Lua-number array. r75 reduced instance-data repacking; this catalog isolates the instance part from its separate Matrix work. Later callback/ownership corrections are retained in the published split series. These methods are shared renderer code used by the applicable Metal3/Metal4 engine path. Their original Lobby integration does not by itself establish inclusion or acceptance in every Chobby engine version.

## Measured whole-stack result

| Historical integration | Metal3 mean FPS | p95 ms | p99 ms |
| --- | ---: | ---: | ---: |
| RUN95 + VBO | 36.6598 | 34.013 | 41.897 |
| r58 | 43.5240 | 42.646 | 49.159 |
| r78 | 46.5778 | 28.809 | 42.000 |
| r80 | 46.5279 | 29.055 | 42.886 |

The observed mean gain was **18.72% by r58**, before r73/r75, and **26.92% cumulatively by r80**. r58's tail frame times were worse in this series. A separate refresh measured 37.0047→44.1325→46.7471 FPS for RUN95→r58→r73, a 26.33% cumulative increase.

Each row is one run, not a replicated per-patch experiment. The fixed named scene used AC/Low Power, Ultra/CUS/4xMSAA/VSync off, 1432×902 and 900 simulation frames in the first series; engine/Mesa/MoltenVK changed together, and global caches/background load were not fully controlled. The percentage cannot be assigned to the fence fix, ring depth, QoS, primitive restart or either Lua patch individually. These are historical stacks, not a fresh benchmark of candidate.4 or candidate.5.

[Full published measurements and limits](../../release-readiness/2026-10-15/PERFORMANCE.md) · [Cumulative R80 source patches](../../stack-records/r80-20261008/patches/) · [Current release/source distinction and stack ledger](../../stack-records/2026-10-17/README.md).
