# Independent final E performance review

**No remaining actionable finding. C should remain current; E32/E64 are not supported as a broadly faster replacement, and allocator64 adds no established benefit.** All12 completed actual execution receipts and selected binding/preservation records agree with the final summary. No product edit, build, test, app or game execution was performed by this reviewer. Whole-app hashing was not repeated; prior owner/readiness review and root's final full-inventory preservation checks supply that evidence.

## Actual apps and execution

All apps display1.0.3 and are local v1.0.4 candidates. C is the existing typed-Buffer candidate. E32 is D+E1 immutable binding metadata+E2 direct native render descriptor+E3 prior-queue barrier reuse, with the old count32. E64 is identical E32 except the single allocator count64 constant. Therefore C-versus-E measures that combined candidate, not an isolated E1/E2/E3 contribution; E64-versus-E32 isolates the source-policy count delta within this experiment.

Each receipt's SHA256 matches the summary. The actual loaded-library evidence verifies all five stack components and the expected role-specific MoltenVK hashes: C `c5ea9b843ba2284c410a0b83b7e2412d4cbc0446f15232b5b317eca56b79f804`, E32 `3de11fa4ad010d70eb356bb6d3ed38af0e09802ec203aa93ea4a3db1cd5adbb9`, E64 `f625ec487c96b2f049cf7d1245360b72e729d512d7613692ffa0012c9382b65b`. Paths match preparation/package roles. Metal4 runs show actual native queue activation and positive completed submissions; Metal3 requests native OFF and has no active native queue. This is not backend inference from a label alone.

Order matches preparation: Metal3 C-E32-E64-E64-E32-C, then Metal4 E64-E32-C-C-E32-E64. Every plan/host file hash and run role was checked. All12 sessions completed normally, with graceful quit/lobby return, no remaining owned processes, protected inputs unchanged, passed power contract and no retry/promotion.

## Matched conditions and preservation

Every receipt has equal quality/camera/resolution/seed/workload/command/game/map evidence: Ultra, AA0, VSync0, Spring; seed7654321; `luarules benchmark armbull armbull 80 8 1400`; Seths Ravine Remake1.3.1;900 simulation frames240→1140. FPS/p95/sample counts match each underlying benchmark. Render interval samples remain distinct from simulation frames. Private caches start cold with zero prior entries. All diagnostics/statistics/tracing/performance tracking are OFF; preparation requests no sampler.

All111 observations show AC Power, Low Power Mode and thermal0. This does not establish that background user/OS activity was absent. SDL hidden/fullscreen flags and safe viewport1512×950 are verified in logical1512×982; native display/Space transition is deferred while hidden, default1×. This does not certify a visible exclusive/physicalRetina fullscreen workload.

Screen guard records idle900 restored to900 and owned awake assertion released. Root summary certifies exact C/E32/E64 inventories, E64 source/build preservation and unchanged launcher/user profiles; the individual protected-input checks agree. The current candidate pointer still selects C. Source and fixture pins were independently checked against recorded final bindings; before/package receipt hashes agree. Successful cache cleanup records72 roots/3999 leaves/115,456,473 logicalbytes and explicitly does not measure physical reclaimed storage. Historical failure evidence is not reclassified by these normal runs.

## Recomputed results

| Backend | App | Mean FPS | Change from C | Mean per-run p95 ms |
| --- | --- | ---: | ---: | ---: |
| metal3 | C | 53.5964775085 | — | 26.6825008392 |
| metal3 | E32 | 51.8205699921 | -3.3134780475% | 27.7375001907 |
| metal3 | E64 | 52.2018394470 | -2.6021076876% | 29.9645004272 |
| metal4 | C | 46.8734397888 | — | 28.7425003052 |
| metal4 | E32 | 47.1455593109 | +0.5805409702% | 30.9694995880 |
| metal4 | E64 | 46.6765213013 | -0.4201067565% | 29.0769996643 |

E64 versus E32: Metal3+0.7357492498%; Metal4−0.9948720866%. All means and percentage formulas were independently recomputed from actual receipts; they agree with summary/completion/report. p95 figures are arithmetic means of per-run percentiles, not pooled percentiles. n=2 per app/backend.

Metal3 C exceeds both E32 runs; E64 overlaps part of C's range. Metal4 E32 has one high and one low run around C, with a small+0.5805% mean; E64 is−0.4201% versus C. These samples do not establish a reliable general gain, a statistically proven regression or a causal unit-level explanation. Historical FPS is not pooled. Allocator32/64 fixture reset counts and this FPS experiment do not measure BAR peak memory, allocation churn or long-term net memory benefit. MP/other-Mac acceptance is not established. Keeping C current and preserving E as experimental outputs is consistent with the evidence.

## Owner final binding

Owner completion/report/final-bindings hashes match their referenced files. Owner yielded the source/build lane before root performance and froze E64. Final-bindings source9/fixture5 and unchanged D pins agree with the reviewed implementation; app-inventory file hashes for C/D/L/S/E32/E64 match owner records. E32/E64 package hashes match the root before-snapshot. Raw E64 identity and CMakeCache bindings agree between owner/root records. The owner's earlier FPSMeasured=false/root-work-remaining record describes the pre-performance handoff; it is not evidence that these subsequent12 runs did not occur.

The owner report correctly preserves validation limits: metadata432 is not full binder432; descriptor20728 excludes all outer command state; separate visibility actual-body CPU cases cover initialization/failure/reuse; custom sample patterns were not newly GPU-tested; E32 Vulkan15×2 and E64 count-specific allocator suites are distinguished. Count-only delta, diagnostics0, preserved growth2MiB/available8/idle64MiB and last-user/GPU completion rules remain accurately reported.

The root report's initial separated Metal4 rows lacked a Markdown table header. Root repaired the header/separator and final-app-list spacing; the final report hash in completion now matches. No numeric or execution data changed. Final report SHA256 is `f54be0781d481e71c88ea27f7ba9e14ee975723c0cbe6418ea7ce282e28bc5bc`.
