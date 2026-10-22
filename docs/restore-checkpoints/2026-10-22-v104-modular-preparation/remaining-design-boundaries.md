# Remaining bounded designs

These are ready work contracts, not executable source patches. No candidate below is claimed to improve FPS or be safe to enable without its missing proof. Existing work is explicitly excluded.

## 5. Bounded negative primitive-plan summary

Primary inline first subpass only, single subpass, no multiview/suspend/resume. Planner scans at most2048 commands; conversion entries256 and scratch64MiB. Ordinary draws are still possible shader writers. Incoming pipeline/render/index state may originate before the pass.

One pass-owned immutable summary can bypass the scan only when every command in the exact bounded interval proves no conversion for its actual initial state. Unknown selects the current planner. A first-draw or last-pipeline boolean is insufficient.

| State | Required behavior |
|---|---|
| Start | Unknown; bind to precise pass interval and initial pipeline/dynamic/index signature |
| Known ordinary command | Preserve proof only for explicit recognized effects |
| Draw | Require exact pipeline, dynamic topology/restart/provoking/point state and no unproved shader effects |
| Unknown/inherited/secondary/incomplete interval | Unknown; original planner |
| Complete interval | NoConversion only if every step proved; pool reset invalidates summary |

Concrete counterexamples:

- First ordinary draw followed by a triangle fan or dynamic topology change
- An ordinary shader-writing draw before a converted indexed draw
- Same pass bytes replayed with a different inherited pipeline/index binding
- 2048-command truncation incorrectly treated as proof of a whole pass
- Creating the summary by running the same lookahead twice merely moves/adds work

Unclosed boundary: No existing cheap, authoritative per-pass state summary or measured dominant negative scanning interval is identified. Adding a generic per-command summary currently expands recording work and ABI without demonstrated net benefit.

Next evidence: Use an existing primitive-plan/recording trace to name a recurring negative interval and its initial state. Count existing scanned commands and useful conversions on that interval before choosing storage/hooks; no new broad collector suite.

Verification:

- Compare exact plan entries and fallback boundaries with baseline for fan/restart/provoking/dynamic/zero draw and unknown command sequences
- Require cancellation/pool-reuse invalidation, initial-state changes and cap exhaustion
- Actual dependency handoff and index input lifetime fixture after implementation

## 10. Allocator policy beyond completed32/Q/R

Recordings32, epoch growth2MiB, available allocator slots8, per-kind idle packs8, combined idle budget64MiB. Q quiescent reset and R idle-first selection already exist.32/64 comparison is historical work, not a new module.

Change exactly one policy bound in one patch only after existing churn/idle/retained-byte counters identify its cause. Preserve the state machine and avoid a product setting or a second implementation lane.

| State | Required behavior |
|---|---|
| Recording or unsubmitted owner | No reset; retain writer/owner identity |
| Submitted with live use | No reset/reoffer until actual retirement |
| Last use released | Existing quiescent reset rule |
| Idle available | R existing idle-first selection; same accounting |
| Poison/cancel/OOM | Existing cleanup and error contract, no speculative recycle |

Concrete counterexamples:

- Higher recording bound improves one microcase but grows transient command memory
- A low available-pool count trades reuse for repeated allocation
- Budget bytes are not physical APFS/RAM reclaim
- Resetting an ended but unsubmitted recording violates native command ownership

Unclosed boundary: No new alternative value is supported by a distinct observed churn or memory-pressure cause. An arbitrary tuning constant is not a completed optimization.

Next evidence: Read existing per-epoch reset/allocation/reuse and retained-byte observations on current R; choose one named workload and one value only if those observations explain it.

Verification:

- Existing writer/unsubmitted/cancel/poison/OOM lifecycle cases unchanged
- Matched throughput plus peak retained memory for the one value
- After native allocator retirement and only then pool reuse

## 11b. General render-pass boundary removal beyond11a

11a is a separate prepared upstream Typed buffer discard module. M4 render end currently sets fallback store actions, ends encoding, merges/satisfies dependencies, performs unsupported resolves, ends visibility work, then flushes timestamp samples in order.

Eliminate one repeated internal split only after identifying its command and proving all attachment/subresource/load-store, resource alias, sampling, query and dependency effects. Keep unknown boundaries unchanged.

| State | Required behavior |
|---|---|
| Same attachments, pure redundant state change | Candidate only if no intervening observer or encoder restriction |
| Upload/readback/sampling/alias/new producer | Required split or original synchronization |
| Visibility/query/timestamp helper | Keep helper ownership and original observation order |
| Unsupported command or cancellation | Valid store actions still required |
| Final termination without another draw | Existing end/resolve/visibility obligations still execute |

Concrete counterexamples:

- Same framebuffer pointer but different subresource or alias backing
- No next draw after a split still requires final attachment content and queries
- Moving timestamp flush before resolve/visibility changes query result meaning
- Merging a pass across an upload can expose stale vertex/index data

Unclosed boundary: No specific BAR redundant split with all observers accounted for is identified.11a reducing the upstream split cause is an untested hypothesis, so rerank afterward instead of adding general merging now.

Next evidence: Use an existing pass trace to name boundary command, exact before/after attachments, backing lifetimes, load/store actions and intervening observers. Inspect after11a activation.

Verification:

- Existing suspend/resolve/visibility/alias native fixtures with the exact boundary
- No-final-draw and cancel/unsupported-command store behavior
- M3 unchanged path plus M4 relevant behavior

## 12. Intermediate MSAA resolve deferral

Existing internal private backing with storeOverride and resolve but without combined StoreResolve already selects Store; the final native pass resolves. Memoryless, format capability and depth/stencil swizzle determine different actions. AA Off is not proof of single-sample offscreen attachments.

Pre-classify one proven internal multisample split and its final consumer before native encoder creation. Keep all samples in a surviving private backing and resolve at its required observation/final boundary. No blanket Store-only override.

| State | Required behavior |
|---|---|
| Clean or already resolved | No deferred obligation |
| Multisample writes | Dirty samples; preserve backing and final resolve owner |
| Internal split with no observer and private stable backing | Potential deferred resolve |
| Sampling/readback/alias/export/query-visible boundary | Resolve before the observer |
| Final end, including no further draw | Exactly one required final resolve; no lost obligation |
| Memoryless/unknown/depth-stencil unsupported combination | Existing path |

Concrete counterexamples:

- Omitting intermediate resolve then never starting another encoder loses final output
- Memoryless backing cannot survive a plain Store/Load policy
- Resolve target sampled between fragments requires intermediate value
- Depth-only versus stencil-swizzled views cannot share guessed store rules
- An extra final encoder may cost more than a deferred resolve saves

Unclosed boundary: No observed repeated eligible offscreen MSAA split with complete consumer/backing lifetime is identified; current narrow no-combined optimization already exists.

Next evidence: Identify exact sample count, actual override backing storageMode, resolve format capability and final/intermediate observers for one current BAR split; align with11b.

Verification:

- Existing suspend-resolve cases including no-final-draw
- Memoryless/private, combined/no-combined, color/depth/stencil cases
- Aliasing/readback/visibility and unchanged one-unbroken-pass regression

## 13. Redundant dependency edge beyond completed E3

Existing stage-pair source/visibility masks are grouped only for identical source requirements. satisfy follows actual emission. Prepared prefixes carry consumed destination obligations through incoming entry/outgoing exit. E3 compute coverage is a completed experimental/Combined candidate, not active in frozen R unless explicitly composed. R DependencyScopes has no satisfyAlreadyEmitted.

Remove one named redundant edge only when a previously issued edge provides equivalent ordering and memory visibility for every affected destination, with no intervening producer/incarnation change. Preserve semantic timeline/event signals and native retirement.

| State | Required behavior |
|---|---|
| New producer or resource incarnation | Add outstanding dependency |
| Actual issued barrier | Satisfy exactly its source/destination/visibility coverage |
| Equivalent later request, no new producer | Potential redundant edge |
| Unknown stages/cross-queue/host/query observation | Original conservative edge |
| Poison/cancel/error | Cleanup and waiting threads still reach terminal condition |
| Address/allocator reuse | Completion proof mandatory regardless of CPU worker idle time |

Concrete counterexamples:

- Same source stages but different destination stages
- Execution ordering without required memory visibility
- A new producer after the supposed covering barrier
- Address reuse after a CPU callback but before GPU retirement
- Removing a semantic signal because its consumer was not observed in one sample

Unclosed boundary: No exact remaining redundant edge, alternate issued coverage and critical-path interval have been established. Suppressing waits by category would violate the current correctness model.

Next evidence: Name one edge tuple (queue/epoch, producer, consumer, stage scopes, visibility, resource incarnation, host/query/signal consumers) from existing dependency evidence; close every state transition before code.

Verification:

- Existing queue-barrier-reuse, counter-completion and timeline fixtures
- Cross-queue/host/query/address-reuse and poison/cancel cases
- Compare emitted edge coverage and actual native output; source proofs alone are insufficient

