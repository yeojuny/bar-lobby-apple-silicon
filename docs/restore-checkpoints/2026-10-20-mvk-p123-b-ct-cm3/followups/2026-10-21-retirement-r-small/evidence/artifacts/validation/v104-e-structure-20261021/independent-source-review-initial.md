# Independent initial source review — E1/E2/E3 and allocator count64

Reviewed the frozen four patches, proposal, root grant, nine currently applied E32 product hashes, related unchanged registration/allocator/descriptor definitions, and installed SDK Metal descriptor headers. The current source hashes match E32-application/proposal exactly at this review. No product/fixture/build edit, compilation, GPU or app/game execution was performed.

**No actionable source defect found in this initial pass. Validation and final-pin review remain pending.** In particular E2 default parity and E3 actual applied execution paths require the owner's related checks, rather than inference from a successful build.

## E1 immutable binding interpretation

The plan captures layout-fixed scalar metadata only. The pipeline owns its retained pipeline layout/set layouts; the plan's layout pointer selects the fast metadata path and is not resource ownership or a cache incarnation. Both current common layout and descriptor-set layout must equal it. Different compatible layout objects select the existing current-layout interpretation path with its binding-index check. The plan's fixed/variable/inline count logic is equivalent to MVKDescriptorBinding::getDescriptorCount; the actual variable count remains runtime data. CPU stride is a small fixed descriptorCPUSize and fits its uint32 field.

The payload base/size/range, descriptor revision/incarnation, immutable sampler range, current descriptor object reads, live guards, proofs, retention/residency and drawable conditions remain live. No pointer from a descriptor set or native resource is captured. Existing binding order/dedup and direct/dynamic binding code are unchanged. Structural size/locality cost and runtime benefit remain unmeasured; the slot reads are preserved.

## E2 typed render-pass descriptor

The patch extracts the existing attachment population into one typed implementation. Legacy wrappers alone retain the existing private dither/OpenGL calls; Metal4 does not acquire these flags. Native rendering creates one fresh MTL4 descriptor and passes it to the existing retention/native-encoder body. Foundation guards enclose native overloads/types. The visibility initialization function is templated without moving or duplicating its side effects: native/legacy clear, fences, failure path, endCurrentMetalEncoding and markInitialClearEncoded remain in the same order. Handoff epoch capture remains before populate; an initial-clear encoder transition still invalidates it normally. Sample positions are set once in the common population path, replacing the prior second native copy.

Removed copying previously transferred all color/depth/stencil attachments and scalar/default fields, including array length, default samples, visibility type/buffer, rasterization map, imageblock/threadgroup/tile values. Most are now defaults of the actual MTL4 object; SDK declarations alone do not prove equality to the old legacy-to-native result. The owner must compare actual object defaults and property values (including unused attachments), and exercise visibility/resolve/suspend/resume/multiview/query behavior. Until that evidence arrives, this initial review does not close E2 correctness acceptance. No definite default mismatch is asserted.

## E3 same-active-compute prior-queue coverage

The new subtraction occurs after recordConsumption and conservative-source addition, only for the actual active compute encoder and Dispatch/Blit destinations. The pure helper preserves each destination/source pair. Memory obligations require emitted memory coverage; execution-only emitted coverage cannot satisfy a new memory obligation. Emitted memory also satisfies execution-only requirements. Only actual barrier callbacks add emitted coverage.

The prior-pass prefix cannot gain a new producer while that same compute encoder remains active. Current-encoder producers continue through _metal4EncoderDependencies and barrierAfterEncoderStages; setMetal4Barrier's local RAW/WAR/WAW path is unchanged. endCurrentMetalEncoding clears emitted coverage after ending the pass and merging local outputs, and beginMetal4Recording clears it. Prepared logical consumption remains recorded even when a duplicate native call is removed. Source/destination OR cross-pair invention, future deferral, cross-queue reuse, query completion and retirement are not introduced. Actual emission/reset/local-hazard cases still need the selected production-linked/native tests.

## Allocator32/64 boundary

The frozen E64 patch changes one constant, maxAllocatorEpochRecordings32→64, in otherwise identical E32. Growth2MiB, available8 and idle64MiB limits remain fixed. End-of-recording count/growth sealing and exclusive writer/last-live-use reset election, reset outside locks, poison/discard and publication rules are unchanged. This permits longer count-bound epochs and may change memory residence/churn; it is an experiment, not an unconditional gain. Root's newer grant explicitly cancels the allocator collector and authorizes direct E32/E64 comparison, superseding the design report's earlier diagnostic-first allocator deferral. No collector is part of these patches.

## Remaining handoff

Review final source/fixture/app pins and any implementation repairs against the hashes in the JSON receipt. Check actual E2 default/property parity, E1 fallback/current-payload output, E3 visibility/local-hazard/reset/summary output, and native allocator bounds/completion/cancellation. App packaging and final C/E32/E64 measurements are separate later evidence. This review does not claim GPU correctness or FPS acceptance.
