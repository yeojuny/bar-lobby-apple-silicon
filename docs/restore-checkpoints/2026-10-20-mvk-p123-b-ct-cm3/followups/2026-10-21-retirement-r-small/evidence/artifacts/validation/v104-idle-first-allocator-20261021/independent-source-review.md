# Independent R source review — Q plus idle-first allocator selection

**No actionable source finding.** Actual11 product pins match R-source-pins; the frozen Q snapshot matches before.productPins. Q→R differs in exactly one product file, with the saved R-from-Q.patch identical to an independent diff. The delta is confined to takeAllocatorLocked selection/removal; the remaining accounting/ownership body is unchanged. No product/fixture edit, build/test/GPU/app execution occurred. Execution/package acceptance remains pending root's evidence.

## Selection and locking

The empty list returns before size−1. The existing back-idle case remains O1. If back has liveUses, the loop tests previous indices in reverse down to0, selecting the first zero-live-use epoch; size1 busy safely falls back without looping. If all are busy, selected stays the old back. The existing maxAvailableAllocatorEpochs8 bounds the scan to available entries. This preserves last-vector-order selection among eligible idle entries, not a new time-based sorting policy.

The caller still holds poolMutex and has checked poison, and writer/liveUses/state/available membership are mutated under that mutex throughout existing code. Scanning shared_ptr::operator-> does not copy owners or call Metal. An available epoch is already invariantly nonnull, Appendable and writer-free. R does not infer that a busy epoch is complete or make a new epoch available. Resetting/Sealed/DiscardOnly entries remain excluded by existing offer/removal paths.

`epoch` is moved out before backfill. For non-back selection, the target slot is empty before the last shared_ptr is moved into it. pop_back removes a moved-null slot. For back selection pop likewise removes a moved-null slot. Thus this does not destroy a native epoch object under poolMutex or introduce an extra ownership copy/destruction window. There is no new allocation, lock, atomic or wait.

## Accounting and lifetime

Existing assertions and idleBytes subtraction use the selected epoch itself. Its idleCharge is cleared, available becomes false, writer becomes true, liveUses increments and allocatorReused increments once. Other epochs' accounting and ownership are untouched; relocation changes only vector membership positions. Selection of an idle epoch correctly removes its nonzero idle charge, while busy fallback retains the prior zero-idle-charge behavior. No duplicate reference remains in the pool.

No reset/completion/cancellation path changes. Q's last-use reset still requires liveUses0/no writer and uses Resetting/outside-lock reset/poison+budget checked reoffer. Pending GPU or ended-unsubmitted owners keep their bytes, and concurrent reserved/open writers retain exclusive service. Count32/growth2MiB/available8/idle64MiB stay fixed. R may avoid extending a busy epoch when a ready idle one exists; it does not guarantee earlier GPU completion, lower peak memory, less churn or higher FPS. The added mutex-held scan can cost more when all entries are busy; actual opportunity/benefit is still unmeasured.

## Related fixture source review

Four CPU policy cases are added on top of the existing count/growth/quiescent suites. They create distinct epochs with actual simultaneous writer reservations and real end/release paths, rather than fabricating available entries:

- Busy newest entry plus two older idle entries: select newest available idle, remove only its charge, reserve one writer/use, increment reuse once, preserve other identities; the next selection uses the remaining idle and checks unique membership after release.
- All busy: preserve exact prior back/LIFO and all prior live owners.
- Back already idle: preserve fast-path identity.
- Pending GPU plus an ended-unsubmitted later owner: select separate idle storage with no busy reset; GPU completion alone cannot reset the remaining owner; its final release resets once.

The native allocatorIdleFirstGPUReplay creates two open streams to force separate epochs, releases/reset one, then ends the retained unsubmitted stream as the newest available. A newly begun stream must use the idle epoch: its retirement producing reset count2 while the older stream remains owned discriminates R from Q's busy-back selection. The test checks exact output/guard bytes before later submitting the retained stream, then verifies both writes and shared idle budget. The old Q-selection policy would fail the selection observation rather than pass through a helper-only assertion. The existing general native main adds this case without weakening the prior quiescent fill/signal/tail checks.

No required extra renderer/full-game suite follows from this isolated selection change. Root should execute the related production CPU/native suites, bind final product/fixture hashes and signed package, and accurately distinguish correctness acceptance from an eventual performance benefit. The newly human-selected current baseline is Q; old C/Q decisions were historical and are not reimposed by this review.
