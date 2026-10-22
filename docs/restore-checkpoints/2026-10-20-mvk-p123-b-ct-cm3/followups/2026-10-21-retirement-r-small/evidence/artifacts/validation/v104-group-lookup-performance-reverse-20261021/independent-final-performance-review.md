# Four candidates, reverse order: independent final performance review

All16 reverse-order sessions pass the independent data-integrity and arithmetic review. No actionable defect was found. The earlier large Metal4 lookup gain is not reproduced; existing R has the highest mean FPS on both backends in this batch. Retaining R and all four frozen candidates is supported. These measurements do not establish a causal regression rate or a functional failure.

Reviewed final report SHA256: `f66040404a39cf1f24a22f107e515b6bc77fa330cdde1860d519859814de4408`. This was a read-only text/JSON/pin review; no builds, tests, GPU workloads, apps, benchmarks, whole-app hashes or cleanup were repeated.

| Backend | Candidate | Two FPS results | Mean FPS | Change vs R | Lookup vs own parent | Mean per-run p95 ms |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| metal3 | R | 47.875965 / 48.182129 | 48.029047012 | +0.000000000% | — | 37.256999969 |
| metal3 | Combined | 47.086056 / 47.291405 | 47.188730240 | -1.749601178% | — | 37.826000214 |
| metal3 | RLookup | 47.072292 / 47.350689 | 47.211490631 | -1.702212374% | -1.702212374% | 38.395000458 |
| metal3 | CombinedLookup | 47.533077 / 46.756973 | 47.145025253 | -1.840598167% | -0.092617424% | 36.233499527 |
| metal4 | R | 43.341438 / 42.072289 | 42.706863403 | +0.000000000% | — | 40.174999237 |
| metal4 | Combined | 40.391449 / 42.489994 | 41.440721512 | -2.964726956% | — | 41.240999222 |
| metal4 | RLookup | 43.716236 / 41.312862 | 42.514549255 | -0.450312040% | -0.450312040% | 39.819000244 |
| metal4 | CombinedLookup | 41.651581 / 39.947746 | 40.799663544 | -4.465792399% | -1.546927623% | 44.094001770 |

Grant, preparation,16 arm results, outcome and summary agree exactly: Metal4 R/RLookup/Combined/CombinedLookup/CombinedLookup/Combined/RLookup/R; then Metal3 CombinedLookup/Combined/RLookup/R/R/RLookup/Combined/CombinedLookup. All receipt/plan/host hashes match. Benchmark-result JSON and linked native infolog/driver log hashes match their references; saved benchmark JSON equals each receipt payload, and FPS/p95/p99/draw counts match summary. All16 planned sessions are included once, with no retry, filtering or historical FPS pooling. The prior report and coordinator hashes match the grant.

Actual runtime paths/hashes match plans and the unchanged frozen package identities for all four apps. Eight Metal4 sessions prove native queues and completed submissions; eight Metal3 sessions have runtime selection0 and no active native Metal4 queue. Runtime diagnostics and sampler/timeline/capture remain OFF; compiled OFF and allocator32 reuse the frozen qualification. Apps display1.0.3 and remain local v1.0.4 candidates. No shared revision UUID was used as a substitute for package identity.

Each measurement covers240→1140,900 simulation frames. Draw interval counts are distinct and vary. Actual Ultra/AA0/VSync0, Spring camera, seed7654321, workload, game/map/engine version and resolution agree across all16. Controller/scene/content/private settings pins match, and the conditions object equals the preceding batch. Every session records hidden SDL fullscreen1512×982 and safe viewport1512×950; native display/Space presentation is deferred while hidden.

All143 AC Power + Low Power observations pass with thermal state0, and root before/final OS checks record macOS27.2 build26B118. Normal exits, protected-input preservation, empty initial cold caches and no owned processes are recorded for all runs. Screen settings restore900→0→900 with awake assertions released. All39 current source/fixture/build text pins match, and the four1194-entry inventory manifests equal the preceding frozen manifests. Root final raw/build/CMake/app/launcher HEAD/index/status/user-profile checks were inspected and accepted without repeating full-app hashing. The selected pointer directly matches its before-state R JSON.

Arithmetic means, changes versus R and own-parent FPS/p95 rates were independently recomputed. The same-parent comparisons are RLookup versus R and CombinedLookup versus Combined. Mean p95 averages per-run p95 summaries; it is not pooled over rendered intervals. Reverse own-parent p95 changes are M3 RLookup+3.054461%, CombinedLookup−4.210069%; M4 RLookup−0.886121%, CombinedLookup+6.917879%. These may differ in direction from mean FPS.

The report correctly keeps batches separate. Prior RLookup Metal4+7.621833% becomes−0.450312% here; prior CombinedLookup Metal4+3.051627% becomes−1.546928%. RLookup now records43.7162/41.3129 against R43.3414/42.0723, so the prior both-runs-higher observation is absent. M3 own-parent changes are−1.702212% and−0.092617%. With n=2, uncontrolled background load/clocks and differing order, no stable additional gain, positive synergy or causal regression is established. M3 does not execute the changed Metal4 group lookup path; its differences cannot be assigned directly to removing that map lookup. Balanced run-position sums do not remove nonlinear load changes or equalize wall-clock timing.

Sixteen cache selections/completions independently sum96 roots,5335 leaves and153,950,004 logical bytes. Every selected root is absent, with result/log/Markdown references retained. This verifies recorded cleanup only; the reviewer performed no deletion and physical reclaim is unmeasured. The96-byte CPU metadata overhead remains; FPS does not prove allocator timing, peak-memory savings, MP, other-Mac or race-freedom acceptance. Existing sampled-exit and timestamp fixture issues remain outside the claimed result.

The final report and its separate-batch table accurately reflect the source data and limits. Complete16-row receipt/runtime bindings and calculation values are recorded in `independent-final-performance-review.json`.
