# R versus Combined: independent final performance review

The final eight-session comparison is internally consistent. No actionable evidence, arithmetic or result-selection defect was found. Retaining selected R and preserving R+D+E1+E2+E3 as a comparison candidate is supported: the small positive mean FPS changes do not establish a clear additional performance benefit. Active source/build remains frozen Combined; the selected application pointer remains R.

Reviewed final report SHA256: `e007b0727b4a375f09a6a341fe115f059e7f274b6de13f7ea5bc1f5ad461f72e`. The independent source/readiness reviews remain the code, allocator32 and compiled-diagnostics-OFF basis. No build, test, GPU workload, app or benchmark was repeated by this reviewer.

| Order | Backend | Candidate | FPS | p95 ms | Draw intervals | Sim frames |
| ---: | --- | --- | ---: | ---: | ---: | ---: |
| 1 | metal3 | R | 49.355385 | 32.930000 | 1479 | 900 |
| 2 | metal3 | Combined | 48.023193 | 34.625000 | 1439 | 900 |
| 3 | metal3 | Combined | 49.295300 | 31.851999 | 1477 | 900 |
| 4 | metal3 | R | 47.427242 | 35.691002 | 1421 | 900 |
| 5 | metal4 | Combined | 40.656258 | 43.561001 | 1218 | 900 |
| 6 | metal4 | R | 41.960827 | 40.832001 | 1257 | 900 |
| 7 | metal4 | R | 41.949108 | 39.431999 | 1257 | 900 |
| 8 | metal4 | Combined | 43.321156 | 39.272999 | 1298 | 900 |

| Backend | R mean FPS | Combined mean FPS | FPS change | R mean p95 ms | Combined mean p95 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| metal3 | 48.391313553 | 48.659246445 | +0.553679725% | 34.310501099 | 33.238499641 |
| metal4 | 41.954967499 | 41.988706589 | +0.080417390% | 40.131999969 | 41.416999817 |

All eight planned sessions are included exactly once, in the registered order. Each arm result equals the corresponding outcome; all eight receipt hashes and plan/host hashes match. Independently hashed benchmark-result JSON equals the embedded receipt payload, and all linked native infolog/driver log hashes match. Official native reports record the benchmark finishing at1140 with400 spawned units over900 gameframes. Actual measurement is240→1140,900 simulation frames; draw-interval sample counts differ and are reported separately.

Both apps display1.0.3 and are locally designated v1.0.4 candidates. Runtime library paths and SHA256 values in every receipt match its frozen per-arm plan: R MoltenVK `8f8010bdcb59397564c21c80ad2eb87fb4690b45e6def36478db7e11fc781462`; Combined `129e85bb9a7d1cf53a991bbeb5afbbd578b563182de86a1b60ddf57f6b195077`. Metal4 has four actual native queue proofs with completed submissions. Metal3 has runtime selection0 and zero active native Metal4 queues in all four receipts. A shared driver revision alone was not used to distinguish the candidates.

All eight runs have identical actual Ultra/AA0/VSync0 quality, Spring camera, seed7654321, armbull workload, Beyond All Reason test-31671-ad2e1b7, Seths Ravine Remake1.3.1 and engine BAR-1.0.3. Controller, scene, content and private settings file pins match. Runtime diagnostics are OFF; plan sampler/timeline/capture options are OFF. Logical hidden SDL fullscreen is1512×982 with safe viewport1512×950. Native display/Space presentation is deferred while hidden, so this does not certify visible fullscreen presentation.

There are73 passing AC Power + Low Power observations, all thermal state0. The OS is macOS27.2 build26B118 throughout the root before/final preservation check. Every session exits normally, returns to lobby, leaves no owned process and preserves protected inputs. Screen idle settings restore900→0→900 and the awake assertion is released. Root final source/build/app-inventory/launcher/profile preservation checks are accepted together with the independently established readiness pins; expensive complete-app inventory hashing was not repeated. The selected candidate JSON was directly compared with preparation and remains R.

Group arithmetic was recomputed independently. FPS is the arithmetic mean of two run FPS summaries; p95 is the mean of two run p95 summaries, not a pooled percentile. M4 Combined varies40.6563→43.3212 FPS, straddling both R measurements near41.955. Its mean p95 increases40.132→41.417ms (+3.201933%); M3 mean p95 decreases3.124412%. With n=2 and uncontrolled background services/clocks, neither a reliable improvement nor a definite causal regression is established. The comparison does not isolate D/E1/E2/E3 contributions or synergy, allocator timing/frequency/peak memory, race-freedom, multiplayer or other-Mac behavior. Historical FPS was not pooled and older absolute results should not be used as causal evidence.

Eight game-cache cleanup selections/completions independently total48 roots,2666 leaves and76,970,979 logical bytes; every selected root is absent. Derived successful standalone cleanup independently totals18 executables plus18 dSYM roots,72 leaves and45,519,724 logical bytes, matching each selected leaf size; all36 roots are absent. These are logical byte counts, not physical space reclaimed. Sources, extracted production inputs, raw libraries, apps, result JSON, failure/success logs and Markdown remain. Initial prepared compilation include failure and the later successful attempt are retained. The initial zero-selection cleanup preflight stopped without deletion before its xcrun wrapper filter was corrected.

The final report accurately records R selection retained, Combined preserved, active Combined source/build frozen, R preimage/raw and R/Q/C recovery apps retained. Existing timestamp mismatch and sampled-exit failures are not claimed repaired. Machine-readable receipt bindings, hashes and calculations are saved in `independent-final-performance-review.json`.
