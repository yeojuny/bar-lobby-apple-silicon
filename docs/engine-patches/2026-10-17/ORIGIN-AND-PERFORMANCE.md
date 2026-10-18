# Origin, chronology and measured performance

This record distinguishes earlier local investigation, external references, selective integration and subsequent corrections. It does not establish worldwide priority, wholly independent origin, or an isolated FPS contribution for each change. Selected upstream integrations are catalogued separately in the [integration ledger](../../stack-records/2026-10-17/INTEGRATIONS.md).

## Work preceding r57

A read-only review of the project's contemporaneous reports found restart-related work before the October 5 r57 integration:

| Date / record | Work and boundary |
|---|---|
| June 6, `thread-06k-focused-warning-triage.md` | Identified the Metal primitive-restart warning and cautioned against changing rendering semantics merely to suppress it. Diagnosis, not evidence of an implemented performance fix. |
| June 12, `thread08-final-local-candidate.md` | Narrowed Zink submission synchronization in a local candidate. This was a different layer from the later Recoil 250µs fence wait, and was not production accepted in that record. |
| September 5 / October 2, `graphics-aesthetic-update-assessment-20260905.md` and `run94-stack-review-recoil-boundary-20261002.md` | Recorded Kitrae's Recoil PR #3156 as a restart-performance reference, held rather than approved for adoption. Earlier local work must not be taken as proof that no external references existed. |
| October 2–3, `metal4-vulkan-integration-20261002.md` and `metal4-r29-performance-batch-20261003.md` | r20/r29 accelerated required restart/index conversion and sentinel-containing segment compaction. These changes did not remove the engine's restart request. |
| October 4, `metal4-r42-original-index-20261004.md` | Avoided a UINT32 copy when the original index data was proven usable. |
| October 4, `metal4-r43-work-elimination-20261004.md` | Disabled restart only for newly generated Mesa draws proven to contain no sentinel; Recoil binaries were unchanged. The report observed component conversions dropping from 36 to 12, not a demonstrated game-FPS gain. Existing split-to-direct restart disabling was explicitly excluded from the new work credited to r43. |

These filenames identify local project reports reviewed for chronology; the reports are not all exported in this launcher repository. Dates reflect the reports' recorded context, not filesystem timestamps. The public [R80 cumulative source checkpoint](../../stack-records/r80-20261008/README.md) provides inspectable implementation evidence but does not reconstruct every original edit date.

Restart correctness, faster required emulation, and omission of unnecessary restart are distinct tasks. The earlier work establishes a local development history; it does not by itself prove first authorship of every idea. No separate early index-unroll fix is asserted without a corresponding primary record.

## Selective benbreen-informed engine integration: r57

[benbreen/RecoilEngine-AppleSilicon](https://github.com/benbreen/RecoilEngine-AppleSilicon) is an independent unofficial macOS port. Its reviewed snapshot was [`a49a8ecc5265c4dd3f8d0016d90b32e81e22c73b`](https://github.com/benbreen/RecoilEngine-AppleSilicon/tree/a49a8ecc5265c4dd3f8d0016d90b32e81e22c73b). It uses Mesa/Zink/KosmicKrisp and SDL2; this port uses Mesa/Zink/MoltenVK and SDL3. The engine-side ideas can be relevant across those different translation backends.

Our r57 adaptation was informed by its 1ns→250µs fence waits, model-upload ring expansion (three→six by default on macOS), actual synchronous worker-entry QoS requests and unnecessary primitive-restart avoidance. These ideas retain that attribution. We did not wholesale transplant its display/readback path or simulation changes. Our restart optimization instead requires a narrow model-index sentinel proof and revokes that proof on relevant modification/exposure paths.

The October 5 `benbreen-performance-intake-20261005.md` still recorded 1ns engine waits and three-slot model rings before this integration, while acknowledging the preceding r43 downstream work. `metal4-r57-engine-integration-20261005.md` records the selective implementation and explicitly states that the donor topology whitelist was not copied unchanged. The larger ring applies to model-data uploads; it should not be described as changing every generic stream ring. This attribution is to the r57 integration, not to all earlier restart or synchronization work.

250µs is a wait timeout, not an unconditional per-frame sleep; completion remains required. A deeper ring consumes additional memory. QoS is a scheduling request, not a guarantee of P-core placement or higher FPS.

## Additional local corrections: r57a / r58

The r57a review corrected QoS configuration access before initialization. It also identified stream-lifetime issues not solved simply by increasing ring depth or wait duration.

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
