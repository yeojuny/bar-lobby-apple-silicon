# Independent final R performance review

**No actionable discrepancy. Four complete Q-R-R-Q Metal4 sessions give R a+0.8458334790% mean FPS observation.** This is not a proven repeatable causal gain. Selecting R as the next exploratory local work baseline is consistent with the requested cumulative workflow and passed correctness review, provided Q/C restoration remains available and the measurement limits remain explicit. It is not certification of a faster formal release or a memory benefit. No product edit, build/test/GPU/app run or repeated whole-app hashing occurred in this review.

## Selection, actual runtime and matched conditions

All four prepared executions are included, Q-R-R-Q, n=2 per app; no automatic retry or result-based omission. Plan/host hashes, receipt SHA256 values, role app paths and every per-run FPS/p95/draw sample count agree with actual benchmark outputs. Both apps display1.0.3/local v1.0.4 candidate. Actual loaded stack-library verification is true, with Q MVK3f7ae550916228c89eec51f3f1741e54b5fbe62929e03a22038158d7ba076dd6 versus R8f8010bdcb59397564c21c80ad2eb87fb4690b45e6def36478db7e11fc781462. Every run proves active native Metal4 queues and completed submissions, not merely environment selection.

Each run uses900 simulation frames240→1140 and equal quality/camera/resolution/seed/workload/command/game/map evidence: Ultra, AA0, VSync0, Spring; seed7654321, `luarules benchmark armbull armbull 80 8 1400`; private cold caches. Diagnostics/statistics/collector/tracing/performance tracking are OFF, with no sampler requested. SDL fullscreen and hidden flags are present, logical1512×982 and notch-safe1512×950/default1×. Native display/Space transition is deferred while hidden; visible exclusive/physicalRetina fullscreen is not established by this route.

All38 power observations pass AC Power, Low Power Mode and thermal0. All four finish normally with graceful quit/lobby return, no remaining owned processes, protected inputs unchanged and passed power checks. OS before/summary/context and the independent read of sw_vers agree on macOS27.2 build26B118. This bounds the within-session comparison; it does not prove the human-reported RC channel or attribute historical absolute FPS changes to that update. OS/user background load and clock state remain incompletely controlled.

## Independent arithmetic

| Actual order | App | FPS | p95 ms | Render interval samples |
| ---: | --- | ---: | ---: | ---: |
|1|Q|46.076702117920|31.016000747681|1380|
|2|R|46.895664215088|29.660999298096|1405|
|3|R|46.059989929199|30.173999786377|1380|
|4|Q|46.099296569824|28.938999176025|1381|

| App | Mean FPS | Change versus Q | Mean per-run p95 ms |
| --- | ---: | ---: | ---: |
|Q|46.087999343872|—|29.977499961853|
|R|46.477827072144|+0.8458334790%|29.917499542237|

These arithmetic means and ratios were independently recomputed from raw receipts and match summary/completion/report. The p95 mean is a mean of two per-run percentiles, not a pooled percentile. R's two runs differ46.896 versus46.060; its lower run is below both Q values. Do not convert a positive mean or slightly lower mean p95 into a claim of both-run improvement or statistical significance. This experiment does not measure idle-choice opportunity frequency, time spent in allocator selection, allocation churn, peak/physical memory or long-run net benefit.

## Correctness/preservation and separate historical number

The prior source/readiness reviews established the single native selection-function delta, ownership/accounting invariants, CPU1027 checks, native6 cases and the frozen-Q negative-control failure at the intended new selection assertion. That evidence was not rerun. Metal3 does not execute this changed allocator policy, so no unrelated Metal3 FPS matrix was required here; this does not claim a new Metal3 improvement.

Root final analysis records exact Q/R inventories, frozen R source/build, unchanged launcher/user profiles, same raw/package pins, restored screen idle and awake release. The four successful-cache cleanup receipts independently sum to24roots/1332leaves/38,483,426logicalbytes, all selected paths absent. The three standalone successful test executables were subsequently retired: selection/completion recorded3 files/5,226,032logicalbytes and those exact paths are absent. Source/recipes/logs/pins/Markdown/raw/app evidence remains; earlier readiness verification describes completion-time availability of the executables and is not invalidated by this documented retirement. Physical reclaimed storage was not measured.

The report's separate historical Metal3 answer is not pooled into Q/R. metal3-history-answer.json links a retained C record with56.965129852295FPS, paired56.21106338501/56.965129852295 mean56.5880966186525. Referenced receipt/summary hashes, per-run value, paired arithmetic and AC+LowPower/safe viewport900frame/legacy-backend evidence match. This verifies the identified matched historical record and its stated pair; the review did not run an exhaustive new global search for every possible historical maximum.

## Final decision/report binding

At performance analysis and this review, the selected pointer was still Q, consistent with completion's “before decision” fields. Root intends only a subsequent local metadata selection of R, retaining Q/C. Those fields are historical pre-decision data, not an inconsistency with the report's next-baseline plan. The source/build/app bytes remain frozen. The coordinator selection receipt should link this review and final report, without relabeling the small-sample observation as guaranteed speed/memory gain.

Final report SHA256 f90b16540e9a557cdfa4d9842288d960ef76d918178f98099c4fc58cd17eecf8 matches completion. The report accurately preserves per-run variation, n2/OS/background limits and lack of memory/MP/other-Mac proof. No existing timestamp/sample-exit uncertainty was closed by these successful sessions.
