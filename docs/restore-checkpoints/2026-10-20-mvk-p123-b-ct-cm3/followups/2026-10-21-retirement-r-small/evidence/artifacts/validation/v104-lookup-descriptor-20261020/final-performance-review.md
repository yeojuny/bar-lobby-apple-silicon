# Independent final performance review

**Eight successful matched release-OFF sessions support “no FPS benefit established; keep C as current and preserve D as a comparison candidate.”** No additional build, test, app or game run was performed by this reviewer. This review concerns the completed performance evidence, not concurrent cleanup execution.

## Independent recomputation

| Backend | C mean FPS | D mean FPS | D versus C | C mean per-run p95 ms | D mean per-run p95 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Metal3 | 55.3588428497 | 54.7832927704 | -1.0396714413% | 26.3509998322 | 25.4184999466 |
| Metal4 | 49.6362075806 | 49.0089950562 | -1.2636189487% | 27.4955005646 | 27.4430007935 |

Means were independently recomputed from each actual execution receipt and agree with `comparison-summary.json`. These are arithmetic means of two per-run summaries per app/backend. The p95 means are not pooled percentiles and do not establish a lower-tail improvement.

| Actual order | Backend | App | FPS | Draw interval samples |
| ---: | --- | --- | ---: | ---: |
| 1 | metal3 | C | 54.60126495 | 1636 |
| 2 | metal3 | D | 53.55722809 | 1614 |
| 3 | metal3 | D | 56.00935745 | 1678 |
| 4 | metal3 | C | 56.11642075 | 1681 |
| 5 | metal4 | D | 49.08364868 | 1471 |
| 6 | metal4 | C | 50.16812515 | 1503 |
| 7 | metal4 | C | 49.10429001 | 1471 |
| 8 | metal4 | D | 48.93434143 | 1466 |

C and D both display version 1.0.3 and are local v1.0.4 candidates. C is `artifacts/runtime/v104-typed-buffer-callers-candidate-20261020/BAR.app`; D is `artifacts/runtime/v104-lookup-descriptor-release-20261020/BAR.app`. D contains the combined lookup-aware registration change plus the nine-counter source instrumentation, with diagnostics compiled OFF for this comparison.

## Identity and conditions

- Actual loaded-runtime receipts verify all five stack libraries. C's packaged MoltenVK SHA256 is `c5ea9b843ba2284c410a0b83b7e2412d4cbc0446f15232b5b317eca56b79f804`; D's is `05ca8f27796bad7e75211259a2df909295e62a8c3cb8db344996356c3990e237`. The hashes are consistent across all four sessions per role and match their package evidence. Receipt SHA256 values match the final summary.
- Every session reports diagnostics OFF, including batch/queue/backend-cost statistics, tracing and performance tracking. The preparation requests no CPU sampler. This comparison uses release-OFF apps, separate from the diagnostic OFF/ON/OFF runs.
- Metal4 sessions show one active native queue and positive completed-submission counts. Metal3 sessions request USE_METAL4=0 and show zero native Metal4 active queues. D's `legacyParentIdentityVerified=false` means D differs from the prior parent hash; it is not itself backend-failure evidence. Actual D runtime identity is checked directly by its new expected hash.
- Quality, camera, resolution, seed, workload, command, game and map data are exactly equal across all eight benchmark receipts: Ultra, MSAA0, VSync0, Spring; seed7654321; `luarules benchmark armbull armbull 80 8 1400`; Seths Ravine Remake1.3.1. Every run uses 900 simulation frames,240→1140. Draw interval samples are the separate counts shown above.
- All eight start a new private cold cache with zero pre-existing entries. Actual SDL fullscreen and hidden flags are present; logical container1512×982 and notch-safe viewport1512×950. SDL defers native display/Space transition while hidden. This is default1× hidden rendering, not proof of a visible exclusive/physicalRetina fullscreen workload.
- All73 power observations pass AC Power and Low Power Mode; every recorded thermal state is0. These checks do not establish that OS/user background work was absent.
- All eight receipts complete normally with graceful quit and lobby return, no remaining owned processes, protected inputs unchanged, and passed power contract. The actual order matches the prepared C-D-D-C for Metal3 and D-C-C-D for Metal4. There was no automatic retry or app promotion.
- Current pointer still selects C. Six reviewed source/fixture pins are unchanged. The final summary records exact app inventories, user-profile/source pins and launcher HEAD/index/status before/after.

## Interpretation

D's mean FPS is about1% lower on both backends in this small n=2 sample. C's two Metal4 values exceed both D values, while Metal3 ranges overlap. This does not prove statistical regression, distinguish background drift from code-layout effects, or establish the registration optimization's own dynamic frequency. It does establish that this comparison did not demonstrate the intended FPS gain, so promoting D as a faster current candidate would be unsupported.

The completed diagnostic investigation remains useful for choosing a smaller next design. Its counts must not be treated as timed bottleneck percentages or used to convert this negative/uncertain FPS result into a claimed win. Historical FPS was not pooled. Existing unrelated timestamp-fixture and earlier sampled-exit uncertainties are not resolved by these normal runs.
