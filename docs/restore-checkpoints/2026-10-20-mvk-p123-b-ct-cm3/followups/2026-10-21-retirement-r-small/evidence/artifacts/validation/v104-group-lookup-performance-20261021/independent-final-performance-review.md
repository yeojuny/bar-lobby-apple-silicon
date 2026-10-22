# Four frozen candidates: independent final performance review

The16-session result is internally consistent, with no actionable evidence, arithmetic or reporting defect found. RLookup is promising in this batch on Metal4 while its Metal3 result is effectively unchanged. The data does not establish a repeatable causal improvement percentage or positive interaction with D/E1/E2/E3. Retaining selected R and preserving all four candidates is supported. Active source/build remains frozen RLookup.

Reviewed final report SHA256: `89c04d3de82ca27b0ab2ffe127a8ee6eeebc97bc8a9af6d747d1aacda665a4ca`. The reviewer performed read-only text/JSON/pin checks, and did not run any build, test, GPU workload, app, benchmark, complete-app hash or cleanup.

| Backend | Candidate | Two FPS results | Mean FPS | Change vs R | Lookup vs own parent | Mean per-run p95 ms |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| metal3 | R | 47.816383 / 48.625229 | 48.220806122 | +0.000000000% | — | 35.822999954 |
| metal3 | Combined | 47.687862 / 52.204002 | 49.945932388 | +3.577555842% | — | 31.830499649 |
| metal3 | RLookup | 47.705662 / 48.726749 | 48.216205597 | -0.009540539% | -0.009540539% | 35.833501816 |
| metal3 | CombinedLookup | 45.573883 / 46.678699 | 46.126291275 | -4.343591523% | -7.647551924% | 38.274000168 |
| metal4 | R | 42.756542 / 40.294724 | 41.525632858 | +0.000000000% | — | 42.221000671 |
| metal4 | Combined | 41.994038 / 43.376743 | 42.685390472 | +2.792871618% | — | 38.977998734 |
| metal4 | RLookup | 44.615425 / 44.765869 | 44.690647125 | +7.621832707% | +7.621832707% | 34.613500595 |
| metal4 | CombinedLookup | 41.713074 / 46.262905 | 43.987989426 | +5.929726768% | +3.051627123% | 37.001000404 |

All16 sessions match the grant and preparation: Metal3 R/RLookup/Combined/CombinedLookup/CombinedLookup/Combined/RLookup/R, then Metal4 CombinedLookup/Combined/RLookup/R/R/RLookup/Combined/CombinedLookup. Every arm result equals outcome, every registered receipt/plan/host hash matches, and linked native infolog, driver log and benchmark JSON hashes match. Raw benchmark JSON equals each receipt payload; FPS, p95, p99 and draw counts match the summary. No retries, missing runs, success filtering or historical pooling occurred. The symmetric order balances run-position sums within each backend, without controlling nonlinear load changes or exact wall-clock spacing.

The own-parent comparison is RLookup versus R and CombinedLookup versus Combined. All group means, changes versus R, own-parent FPS changes and own-parent p95 changes were independently recomputed. Reported means use arithmetic averages of per-run summaries; mean p95 is not pooled across rendered intervals. Each run measures240→1140,900 simulation frames, with variable draw interval counts reported separately. All four apps display1.0.3 and remain local v1.0.4 candidates.

Actual loaded runtime paths/hashes match per-arm plans and the established frozen package identities for all16 sessions. R uses MoltenVK8f8010bd…1462, Combined129e85bb…5077, RLookup348663cd…751b and CombinedLookup772042e6…b490; complete hashes are retained in the machine-readable record. Eight Metal4 sessions prove active native queues and completed submissions; eight Metal3 sessions use runtime selection0 and no active Metal4 queue. Runtime diagnostics and sampler/timeline/capture are OFF. Compiled diagnostics OFF and allocator32/growth2MiB/available8/idle64MiB are inherited from the unchanged qualified packages.

Actual Ultra/AA0/VSync0, Spring camera, seed7654321, workload, map/game/engine version and resolution agree across all16. Controller, scene, content and private settings pins match. The conditions object also equals the preceding comparison. Logical hidden SDL fullscreen is1512×982 with safe viewport1512×950; native display/Space presentation is deferred while hidden. All147 AC Power + Low Power observations pass with thermal state0. The root before/final OS check records macOS27.2 build26B118 unchanged.

All runs exit normally, preserve protected inputs, leave no owned process and start with empty cold caches. Screen settings restore900→0→900 and the awake assertion is released. All39 current source/fixture/build text pins match. Four inventory manifests each retain1194 entries and equal their prior frozen manifests. Root final build/raw/CMake/inventory/launcher HEAD/index/status/profile preservation checks were inspected and accepted without repeating whole-app hashing. The selected pointer directly equals its before-state R JSON.

RLookup Metal4 runs44.6154/44.7659 both exceed R42.7565/40.2947, with mean FPS+7.621833% and mean p95−18.018285%. This is a favorable batch observation, not a confirmed causal rate; R itself varies. RLookup Metal3 changes−0.009541%, essentially unchanged here. CombinedLookup Metal4 has+3.051627% versus its own parent but varies41.7131/46.2629; its Metal3 result is−7.647552%, while Combined itself varies47.6879/52.2040. The changed map lookup is a Metal4 preparation path, so the Metal3 difference is not evidence of the direct lookup-removal effect. These results remain included and do not establish positive synergy or a reliable universal gain.

Sixteen cache cleanup selections/completions independently sum96 roots,5331 leaves and153,934,417 logical bytes; all selected roots are absent and logs/results/Markdown remain. Physical reclaim is unmeasured and no cleanup was performed by the reviewer. The final report accurately describes the observations, limitations and unchanged selection. This review establishes neither allocator timing/peak-memory savings nor MP/other-Mac/race-freedom acceptance. The96-byte metadata increase per recording and existing sampled-exit/timestamp fixture limitations remain.

Full16-row order, receipt hashes, runtime identities, own-parent calculations and input bindings are saved in `independent-final-performance-review.json`.
