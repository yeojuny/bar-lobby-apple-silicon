# Independent review of remaining design boundaries

Accepted as detailed scope/ownership/state/verification contracts, not executable implementations. The five entries5,10,11b,12,13 explicitly report sourceCodePrepared=false and name the missing change unit. No safe, evidence-supported extra one-line product change is established by these inputs.

5 correctly binds a negative primitive summary to an exact interval and initial pipeline/dynamic/index state. Current admission is primary inline first/single subpass, non-multiview and nonsuspending/resuming; scan2048, entries256, scratch64MiB match source. Ordinary shader-writing draws, dynamic topology/index/restart/provoking and unknown command boundaries prevent guessing from a first draw. A summary must replace work rather than run equivalent scans twice. No cheap authoritative summary owner/hook is yet identified.

10 matches the32/2MiB/available8/per-kind8/idle64MiB bounds. Q/R and the historical64 test are excluded from new work. Existing stats describe logical allocator/cache bookkeeping, not automatically measured physical GPU-memory savings. A new named value and churn cause remain absent; ownership, writer and real retirement cannot be relaxed to create a candidate.

11b preserves the real render-end sequence: store fallback, actual end, dependency merge/satisfaction, software resolves, visibility helper, then timestamp flush. Same framebuffer identity alone cannot prove a redundant boundary.11a is a separate Typed storage-discard capsule; any reduction in upstream pass splitting is explicitly an untested hypothesis.

12 correctly retains the already implemented backing+storeOverride+resolve+no-combined Store rule rather than claiming it as new. Current AA Off does not prove offscreen sample count. An exact eligible split, surviving backing and final/observer resolve owner are still needed. No-final-draw and memoryless cases forbid blanket Store-only suppression; extra final encoders can erase the expected gain.

13 preserves source/destination and memory visibility separately, actual emission before satisfy, fresh producers/incarnations, prepared incoming/outgoing obligations and semantic event/retirement ownership. The revised text correctly says E3 is a completed experimental/Combined candidate and is absent from frozen R unless explicitly composed; R lacks satisfyAlreadyEmitted. No remaining exact redundant edge/covering issued edge has been named. Worker idle time is not a GPU dependency proof.

The source pins match the examined files. The requested correction about E3 history versus active R and the11a hypothesis is present in both Markdown and JSON. These design contracts are useful queue entries; a later cue resumes their named design/evidence step and does not apply nonexistent patches. A final user-facing statement must distinguish the prepared code capsules from these five design-only entries, rather than saying all13 are implemented or safe to enable.

No blocking finding against the design documents. No implementation approval, GPU correctness, profitability or exhaustive-search claim is inferred. Reviewer performed reads and saved this review only; no new sampling, tests, build, GPU, app, benchmark, source edit, remote operation or cleanup.
