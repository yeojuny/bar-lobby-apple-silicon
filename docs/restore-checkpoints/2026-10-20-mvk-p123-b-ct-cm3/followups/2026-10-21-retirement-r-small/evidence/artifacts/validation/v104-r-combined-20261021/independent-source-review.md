# Independent Combined source review — R+D+E1+E2+E3

**No actionable source finding; integration validation/package acceptance remains pending.** This reviews the applied composition, rather than substituting the earlier individual candidate results for the new combined candidate. Reviewer performed no product/fixture edit, compilation, test/GPU/app execution.

## Independent composition verification

Actual11 product files match combined-source-pins. Starting from the retained R preimage, this reviewer independently replayed all four frozen patches in memory, requiring a unique exact old/context sequence for each hunk. D17/E1 4/E2 13/E3 2 hunks each matched without fuzz, and every recorded stage-before/stage-after hash and final actual-source hash agreed. This is separate from trusting root's application assertions.

All nine existing E32 frozen source pins match the corresponding final Combined files, including allocator count32 in Submission.h. PreparedResource.h is the exact reviewed D version. Submission.mm is byte-exact to the frozen D file after replacing only its takeAllocatorLocked and releaseAllocatorLocked functions with the exact R preimage bodies. Those two functions are independently byte-exact to R. Thus D's registration/statistics changes and Q/R's allocator changes compose in distinct source regions; the source was not overwritten by a stale D/E snapshot.

The count64 patch is excluded. Count32/growth2MiB/available8/idle64MiB remain fixed. The existing diagnostics9 fields and counting expressions stay compile-guarded; requested final compile/runtime OFF is a later build/package/runtime evidence gate. No new collector, frame-owner policy, lock or global cache was added.

## D registration plus Q/R allocator contract

Known identity-map lookup is consumed after phase/nil/device/type validation in the same submission mutex section. The shared retainUnique/addResident body preserves operation versus GPU ownership, resident flags, device leases, stable-buffer fallback and texture/drawable processing. No iterator escapes or crosses identity mutation; drawable retention may rehash only after the stored identity fields are consumed as before.

Q last-user reset remains unchanged: only liveUses0/no writer/normal Appendable with ended bytes or Sealed elects Resetting. Poison/open cancellation and cold Reserved behavior, outside-lock reset and budget-checked reoffer remain identical. R's bounded idle-first choice uses the existing pool mutex, no shared_ptr scan copy or native call, exact all-busy back fallback and unchanged selected-epoch accounting. Neither D registration nor descriptor metadata can authorize early GPU allocator reset or bypass a new recording's retain/residency.

The registration map belongs to a recording/resource pack; its host/node reuse still clears old ownership flags. Allocator-epoch reuse is separate native command storage whose last-use proof remains unchanged. D lookup reuse does not treat native pointer identity as cross-recording ownership, and Q/R do not keep old map proof alive.

## E1 current payload and layout compatibility

The exact reviewed E1 preparation is immutable layout interpretation. Both common/set layout pointer equality select the fast path, with compatible different objects using the original current-layout fallback. Runtime variable count, CPU payload/base/size/64-bit range, descriptor revision/incarnation, immutable sampler bounds, live membership/owner proof and native ownership all remain live. Metadata sharing is not GPU storage sharing. The added binding script payload size/locality cost remains a performance question, not a guaranteed benefit.

D typed registration/known lookup occurs only after the binder's existing live guard/proof decisions. The prepared metadata does not replace those decisions. Q/R quiescent allocator reset cannot invalidate layout metadata because metadata neither refers to allocator command bytes nor owns native resources.

## E2 typed pass and E3 queue/local barrier boundary

The exact E32 E2 code fills fresh native render-pass descriptors through the shared typed attachment/outer-body paths. Legacy private dither/OpenGL calls remain legacy-only; visibility initialization and native retain/error/clear/end/mark order are unchanged. Captured handoff epoch remains before population; visibility compute helper opening/ending a pass still invalidates it normally. Removed duplicate sample-position setup and prior descriptor default parity still require actual current integration evidence, not old success counted anew.

E3 subtraction remains restricted to actual active compute encoder Dispatch/Blit destinations. It runs after logical prepared-consumption recording and conservative source addition, requires emitted memory coverage for memory obligations, preserves destination/source pairs and adds coverage only after actual queue emission. Encoder-local barriers and local output scopes are unchanged; begin/end recording/encoder clears coverage. Visibility/query helpers may end encoders but cannot carry old coverage across that boundary.

Q/R reset requires all native users/writers finished and therefore cannot reuse command bytes while the encoder-local proof is valid. R merely chooses a safe available epoch; it does not prolong E3 coverage or substitute an allocator address for the encoder/recording boundary. No pass merge, resolve elision, semaphore/query completion weakening or resource lifetime shortcut appears in this composition.

## Integration handoff

Root should freshly extract/link the related existing fixtures from this applied production source, including D registration/state/map boundaries; current metadata/compatible-layout/revision; descriptor-default/visibility/resolve; queue-emission/local hazard/reset/summary; and native allocator idle-first/quiescent/blocked/cancel output. Current Combined Vulkan M3/M4 output cases must link its actual new raw library. Reusing already-extended fixture definitions is appropriate; reusing an old generated .inc/output as if newly executed Combined is not.

Prior individual source/validation reviews explain the bounded contracts but do not close this combined build/runtime gate. Signed package and eight actual R-versus-Combined app sessions remain later evidence. Preserve R/C/Q recovery and official game/sync/AI/display identities; this source composition changes only the specified MVK implementation files.
