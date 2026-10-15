# Performance: measured gains, tradeoffs, and limits

The cumulative Apple Silicon port has produced a substantial **observed mean-FPS improvement in a fixed BAR scene**. This is evidence about complete engine/translation-stack versions on one machine. It is not a claim that every patch helps, that Metal4 beats Metal3, or that all multiplayer modes are faster.

## What the comparable measurements show

The already published [R80 source checkpoint](https://github.com/yeojuny/bar-lobby-apple-silicon/blob/555e7c322e595c331a1b20207e78f2d58c720c01/docs/stack-records/r80-20261008/README.md#performance-evidence) includes this complete seven-arm series. Conditions: AC power, Low Power Mode enabled, reported thermal state 0, Seths Ravine Remake 1.3.1, game `test-31479-433a460`, Ultra/CUS GL4/4x MSAA/VSync off, 1432x902, 900 simulation frames, a new private Mesa cache per arm. Each row is one run in the listed order; no samples were excluded. OS/Metal caches were not cleared.

| Stack | Backend | Mean FPS | p95 ms | p99 ms |
| --- | --- | ---: | ---: | ---: |
| RUN95 + VBO | Metal3 | 36.6598 | 34.013 | 41.897 |
| r58 | Metal3 | 43.5240 | 42.646 | 49.159 |
| r58 | Metal4 | 36.6486 | 48.394 | 55.878 |
| r78 | Metal3 | 46.5778 | 28.809 | 42.000 |
| r78 | Metal4 | 41.4821 | 30.610 | 48.842 |
| r80 | Metal3 | 46.5279 | 29.055 | 42.886 |
| r80 | Metal4 | 42.0438 | 30.405 | 47.153 |

R80 Metal3 was **26.92% higher in mean FPS** than RUN95 + VBO in this series. Its p95 improved, but its p99 was slightly longer. R80 Metal4 was **9.64% below R80 Metal3**. These are whole-stack observations with one sample per arm, not isolated-patch causal effects or statistical guarantees. The same engine and Mesa were retained between r78 and r80; even there, small differences can include run-to-run variation.

A later refresh of the older Metal3 baselines, under the same named scene/quality/power settings, measured RUN95 37.0047, r58 44.1325, and r73 46.7471 FPS: **+26.33% from RUN95 to r73**. Again each baseline had one run; this is corroborating historical evidence, not another sample of the final release candidate. It must not be pooled with a different engine, power mode, duration, or window procedure. That refresh also had a pre-measurement download-index failure, which was retained in the local record and did not produce an FPS sample.

## Where the work changed

The [published source change map](https://github.com/yeojuny/bar-lobby-apple-silicon/blob/555e7c322e595c331a1b20207e78f2d58c720c01/docs/stack-records/r80-20261008/CHANGES.md) and [patches](https://github.com/yeojuny/bar-lobby-apple-silicon/tree/555e7c322e595c331a1b20207e78f2d58c720c01/docs/stack-records/r80-20261008/patches) provide attributable changes against exact upstream bases.

| Layer | Work reduced or corrected | Cost or limit to retain in the explanation |
| --- | --- | --- |
| Recoil rendering | Stream-buffer completion/reuse, primitive-restart preparation, font-atlas upload scheduling, model-data upload preparation | Buffers and pending work still require correct completion/lifetime handling; retained storage consumes memory. |
| Lua VBO uploads | Direct numeric conversion into owned CPU storage avoids an intermediate numeric array | Type/layout/bounds checks, partial uploads, callbacks, and download behavior remain necessary. |
| Mesa/Zink | Narrow presentation/submit-wait changes and supported render-pass handling | Mandatory GPU fences/semaphores remain. CPU work can move to a later wait rather than disappear. |
| MoltenVK Metal4 | Command recording/submission ownership, allocator retirement, prepared resource/binding reuse, argument-table preparation | CPU metadata, caches, locks, validation, fallback replay, and retained resources are additional costs. Their presence is not proof of a net FPS gain. |
| Correctness fixes | Query/pass preservation, resource ownership, bounds, error cleanup, and font/config handling | A correctness fix may add work or recompile a cache. It should not be marketed as a performance optimization. |

These areas changed together across integration versions. The measurements do **not** assign a percentage to each row. Existing upstream work, inherited macOS adaptations, and local work retain their attribution; the number of changed files is not the number of independent new optimizations.

## Why the release audit does not select the highest single FPS

The later Metal3 selection compared three preserved candidates twice each, using its existing private-Lobby fullscreen procedure. AC/Low Power, normal timers, CPU submit wait OFF, cost collection OFF, Ultra/4x MSAA, 1432x902, and 900 simulation frames were fixed within that six-run series. All six completed normally; no low sample was removed.

| Candidate | FPS, first / second | Mean FPS | Mean of run p95, ms | Mean of run p99, ms | Frames over 50 ms, total |
| --- | --- | ---: | ---: | ---: | ---: |
| Config fix `6085b86c` | 47.8548 / 47.6661 | 47.7605 | 27.993 | 40.914 | 4 |
| Epoch instrumentation `c2d8edcf` | 47.9572 / 47.8890 | 47.9231 | 28.420 | 41.357 | 8 |
| Later `f5d9dd5b` | 48.1464 / 47.5480 | 47.8472 | 28.611 | 42.487 | 10 |

The epoch candidate led mean FPS by **0.3405%** over 6085. Config 6085 had lower observed tail latency and fewer long frames in this small series. This explains its historical selection; it does not establish that removing later functional improvements is preferable.

The release audit now selects the **latest R4 functional base, `68cc4cd7`, with custom diagnostics excluded at compilation**. Later changes can avoid repeated allocations, redundant lookups, resource preparation, or empty work while preserving the same result. They are retained with their ownership and fallback contracts. The earlier 6085-based proposal is superseded; it remains a preserved comparison and rollback point. The rebuilt candidate has passed existing CPU/native graphics checks and ordinary launcher UI checks. Release validation found and corrected a Chobby helper startup-lifetime race; the corrected app passed both menu handoffs and the bounded default-Metal3 game smoke. These are functionality checks; no performance benefit is claimed for diagnostic removal without measurement.

Later d97 produced 48.2392 FPS in one Metal3 run. That single run does not establish stable superiority. The latest R4 candidate's comparison was stopped at the user's request before all six runs completed. Its partial, slow results are retained; neither a complete R4 performance comparison nor a causal Alt-Tab explanation has been established.

## Recent small changes are not advertised as proven gains

R1 and R2 removed redundant CPU lookups; S1 changed singleton lock storage; R5 skipped a redundant validity rescan on an exact cache hit; R4 skipped an empty indirect-resource section. Functional checks and source reasoning support the bounded changes, but FPS conclusions are separate. R2's paired Metal4 means differed by only +0.2633%; subsequent S1 and R5 series observed lower Metal4 means (-4.4262% and -3.5984%). Those comparisons do not prove stable regressions, nor do they justify excluding patch influence or declaring all changes free wins. Results from different power conditions or days are kept separate.

The precise same-app CPU-submit-wait comparison measured ON 47.873835 and OFF 47.859734 FPS (three runs each, battery/Low Power): OFF was -0.0295% in that series. The chosen default remains OFF, but it is not described as a demonstrated universal FPS improvement. Historical cost collection was OFF. In the current release candidate, the custom diagnostics collection implementation is excluded at compilation across all 50 MoltenVK production translation units. This does not claim that every upstream diagnostic, branch, or metadata field has been removed, or establish an FPS benefit.

Potential synergy between small changes remains possible. It must be evaluated in the final combined artifact; theoretical savings and isolated passing tests cannot be added into a claimed cumulative speedup.

## Publication scope

The tables document the existing work and its limits. They are not measurements of a newly rebuilt release, a clean-machine acceptance test, a power/temperature measurement, or a guarantee for Scav, Raptors, long sessions, or public multiplayer. Earlier actual multiplayer/Scav investigations are part of the project's history; they must be checked against the exact candidate, rather than erased or automatically transferred to a different binary.

The delivery is an unsigned experimental prerelease with Metal3 as the default and Metal4 as an experimental opt-in. Existing CPU/native checks, actual packaged UI selection/persistence, both Chobby menu handoffs with natural helper cleanup, and a short default-Metal3 Jade Empress game with rendered terrain/units/HUD, native exit code 0 and visible Lobby return have passed within their stated scopes. Those functional checks are not FPS measurements or full multiplayer/endurance acceptance. The source-backed helper startup race was corrected without adding a startup deadline. Previous failed and incomplete checks remain recorded; they were not turned into passing samples.

Numeric evidence and input hashes are recorded in [performance-evidence.json](performance-evidence.json). Full private gameplay logs and user settings are not part of this public export.
