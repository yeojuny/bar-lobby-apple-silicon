# Independent pre-rerun Q execution integrity review

**Interim integrity review complete; final performance judgment is pending the user's new full Metal3 rerun.** The earlier main selection was original post-confirmation Metal3 arms5–8 plus fresh Metal4 arms1–4. Root will now preserve that combined comparison as reference and use fresh Metal4 plus the newly requested fresh Metal3. Do not treat this document as the final latest performance sign-off.

No product/fixture edit, build/test/GPU/app run or whole-app hash repetition was performed. The checks below were completed before the new Metal3 run; this record only writes small text/JSON metadata during preparation.

## Existing execution and selection integrity

The original bounded matrix completed8 sessions and fresh Metal4 completed4, all normal, no automatic retry/promotion. The preceding user's report of overlapping work is preserved in human-background-interference.json. At that observation, old Metal4 arms1–3 results were already known; the record does not claim those older values were blinded. User then confirmed work finished at1792598586430ms. human-idle-confirmation.json fixes the subsequent selection rule before the first Metal3 benchmark even starts: retain original Metal3 arms5–8 only if measured windows begin after confirmation, add fresh Metal4 C-Q-Q-C, and retain the old Metal4 four as confounded reference. No FPS threshold appears in the selection rule or analyze-idle.py.

The first original Metal3 host was initializing when confirmation arrived, but its900-frame measurement starts49,186ms later. All eight selected benchmark starts are after confirmation: offsets49,186;166,873;283,904;401,106;562,715;679,006;797,483;915,658ms. Recording initialization before confirmation is not hidden, and a later measurement start does not prove absence of prior-startup or OS background effects. It does satisfy the explicitly registered measured-window rule.

The selected receipt set exactly equals original Metal3 arms5–8 plus all four fresh Metal4 arms, without dropping either role's slower run. All12 actual receipts remain preserved. All12 run statuses, actual app/loaded MoltenVK role hashes, actual Metal3/4 queue evidence, diagnostics OFF, same quality/camera/scene/seed/private cold-cache/hidden fullscreen conditions and900 simulation frames240→1140 were checked. Primary eight receipt hashes and plan/host hashes agree. Per-run FPS/p95 and frame interval counts agree with actual benchmark output. Original mixed/reference summary values agree with original receipts.

Actual loaded MVK is C c5ea9b843ba2284c410a0b83b7e2412d4cbc0446f15232b5b317eca56b79f804 versus Q3f7ae550916228c89eec51f3f1741e54b5fbe62929e03a22038158d7ba076dd6. Native Metal4 proves active queues/completed work; legacy Metal3 has native selection OFF and zero active native queues. Q's allocator policy is Metal4-specific, so a Metal3 FPS difference is not evidence of executing quiescent reset on Metal3.

Every receipt reports graceful quit/lobby return/no remaining owned processes/protected inputs unchanged. AC+LowPower/thermal0 holds for110 observations over all12 sessions:74 original and36 fresh Metal4. The former primary-eight subset has72 observations. Screen idle and awake assertion restoration are recorded for both phases. Cleanup72roots/3994leaves/115,439,644logicalbytes is cumulative over all12 sessions, not just primary eight, and no physical storage reclamation is inferred.

## Pre-rerun arithmetic, now reference pending fresh Metal3

Earlier selected Metal3 C52.6037197113 versus Q48.8348712921 gives−7.1646044042%; fresh Metal4 C46.5681266785 versus Q46.9515056610 gives+0.8232647733%. Per-run arithmetic means and change formulas match the existing summary. Per-run p95 means are not pooled percentiles. No causal/stable gain, causal Metal3 allocator regression, peak-memory net benefit, MP or other-Mac proof follows from n=2 with uncontrolled background load.

Root's source/readiness review already binds Q's single hunk, CPU916/native5, signed1194-entry/211-closure package and count/growth/budget preservation. Those are not rerun here. C remains current and Q remains experimental. The existing completion/report hash was valid when checked; root then appended the C-maintenance/limits paragraph and announced pre-rerun report hash a0f454bde880d34b44fb5bc7bfc6f470ccde88545a8f95794b639638c5dbbf7e. Final latest report and all new Metal3 receipts must be rebound on handoff.
