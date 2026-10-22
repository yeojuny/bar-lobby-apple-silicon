# Reverse-order R versus Combined: independent final review

No actionable data-integrity, execution-selection, arithmetic or reporting defect was found. All eight reverse-order sessions are included exactly once. Retaining selected R and preserving Combined is supported; these measurements do not establish a stable performance benefit shared by both backends.

Reviewed final report SHA256: `62a756def5f2336a9f21c78d73a37068a68595e1287832d3c27bdb12c2a60500`. This was a read-only text/JSON review. No component review, build, test, GPU workload, app, benchmark or cleanup was rerun.

| Order | Backend | Candidate | FPS | p95 ms | Draw intervals | Sim frames |
| ---: | --- | --- | ---: | ---: | ---: | ---: |
| 1 | metal4 | R | 45.026566 | 33.001999 | 1349 | 900 |
| 2 | metal4 | Combined | 43.725071 | 34.964001 | 1310 | 900 |
| 3 | metal4 | Combined | 43.621185 | 34.692001 | 1307 | 900 |
| 4 | metal4 | R | 41.177937 | 42.109001 | 1234 | 900 |
| 5 | metal3 | Combined | 48.955746 | 32.700001 | 1467 | 900 |
| 6 | metal3 | R | 49.985340 | 31.964001 | 1498 | 900 |
| 7 | metal3 | R | 48.991066 | 32.754002 | 1468 | 900 |
| 8 | metal3 | Combined | 48.235794 | 34.976002 | 1445 | 900 |

| Backend | R mean FPS | Combined mean FPS | FPS change | R mean p95 ms | Combined mean p95 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| metal3 | 49.488203049 | 48.595769882 | -1.803325058% | 32.359001160 | 33.838001251 |
| metal4 | 43.102251053 | 43.673128128 | +1.324471602% | 37.555500031 | 34.828001022 |

Order matches the human rerun grant, prepared plans, outcome, eight individual arm results and summary: Metal4 R/Combined/Combined/R, then Metal3 Combined/R/R/Combined. Receipt SHA256, registered plan/host hashes, linked benchmark-result JSON and native/driver log hashes all match. The saved benchmark JSON equals each receipt payload; FPS, p95, p99 and render interval counts match the raw result. Both apps display1.0.3 and remain local v1.0.4 candidates.

Every actual loaded runtime path/hash matches its per-arm plan. R loads MoltenVK `8f8010bdcb59397564c21c80ad2eb87fb4690b45e6def36478db7e11fc781462`; Combined loads `129e85bb9a7d1cf53a991bbeb5afbbd578b563182de86a1b60ddf57f6b195077`. All four Metal4 sessions prove active native queues/completed submissions; all four Metal3 sessions record runtime selection0 and zero active Metal4 queues. Shared revision UUID alone was not used to distinguish apps. Runtime diagnostics are OFF; sampler, timeline and capture plans are OFF. Compiled OFF and allocator32 reuse the unchanged source/package readiness evidence.

All eight have matching actual Ultra/AA0/VSync0, Spring camera, scene, seed7654321, workload, map/game/engine version, plus identical controller/content/private-settings hashes. Actual measurement covers240→1140,900 simulation frames, with differing draw interval counts kept separate. Every run records hidden SDL fullscreen1512×982 and safe viewport1512×950. Native display/Space presentation remains deferred while hidden. The complete conditions object also exactly matches the preceding comparison.

All71 AC Power + Low Power observations pass with thermal state0. macOS27.2 build26B118 is unchanged in the root before/final OS check. Every session exits normally with protected inputs unchanged, no remaining owned process and initially empty cold cache. Screen settings restore900→0→900 and the awake assertion is released. Root final analyzer checks source/build/raw/app inventory, launcher HEAD/index/status and user profile preservation. Reverse inventory manifests equal the prior frozen R and Combined manifests; the38 pin manifest also equals the preceding reviewed manifest. No full-app hash collection was repeated by the reviewer. Candidate selection JSON directly equals the before-state R pointer.

Group FPS means and changes were independently recomputed. Mean p95 is the arithmetic mean of two per-run p95 summaries, not a pooled percentile. M3 mean p95 increases4.570599%; M4 decreases7.262582%. Metal4 R itself spans45.0266/41.1779 FPS, so the observed+1.324472% mean difference cannot establish a reliable effect. Metal3 now shows−1.803325%, opposite to the previous small positive observation; neither a stable common gain nor an isolated causal regression is established with n=2 and uncontrolled background load/clocks. Prior results remain separate, with no pooling or patch-contribution/synergy/memory attribution.

The prelaunch preparation path mistake was caught by the inventory guard; correction evidence records zero games/apps launched at that point and preserves the partial attempt. It is not a product runtime failure or omitted benchmark. All eight cache cleanup selections/completions total48 roots,2666 leaves and76,971,168 logical bytes, and all selected roots are absent. This is historical cleanup evidence verification only; no cleanup was performed in this review and physical reclaim is unmeasured. Original logs/results/Markdown remain.

The final report faithfully states the observed values and limitations, preserves the R choice and frozen Combined candidate, and makes no new claim about MP/other-Mac acceptance or existing timestamp mismatch/sampled-exit issues. Detailed hashes and receipt bindings are in `independent-final-performance-review.json`.
