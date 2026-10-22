# Independent Q source review

**No actionable source finding.** The actual11 product-file pins match Q-source-pins. C→Q differs in exactly one product file and one hunk: releaseAllocatorLocked elects the existing reset path for a genuinely unused Appendable epoch with ended recordings, as well as the existing Sealed case. This source review does not certify tests, packaging, GPU output or performance; root executes those stages. Reviewer performed no product/fixture edit, build/test/GPU/app run.

## Baseline and pin binding

The root grant authorizes C plus quiescent reset only. Frozen previous-E64 snapshot11 files match their initial pins; that source state remains recoverable and is not confused with current Q. Recorded C rebuild succeeds with rawSHA256 ed983a2648efe352336ca0896e4682d7d9a61e02b56347a5d2680b8f8795ac9f, exact to frozen C. Q uses baseline C, without D lookup/diagnostics or E1/E2/E3/count64 additions. All other10 selected product files match retained C bytes. No allocator constant is changed: count32, growth2MiB, available8 and idle64MiB stay fixed.

## Reset election and ownership

The original live-use decrement and phase transition run under poolMutex. An open Recording use is first discarded; Reserved/Recording releases drop their exclusive writer. If any live use remains, the function returns before the new condition. Consequently submitted GPU users, ended/unsubmitted users and a newer open/reserved writer retain the same memory and prevent reset. The no-writer assertion remains before election.

At liveUses0, poison transitions the epoch to DiscardOnly before the new condition, so poisoned memory does not enter the reset/reoffer path. The added branch requires Appendable and recordings>0. A cold Reserved rollback has recordings0 and still offers empty storage without reset; open cancellation remains DiscardOnly. A Reserved rollback of an epoch with previously ended bytes may elect reset only when every older user has also released, which is safe genuine quiescence rather than new-work completion inference.

Existing availability removal runs before the state becomes Resetting. It removes exactly one available entry and its idle charge. The electing use still owns the epoch through outside-lock finishRelease. No taking thread can borrow Resetting storage; its availability is false. The previous Sealed reset path's per-use resetElected flag ensures a single election, including batched releaseAllocatorUses of shared epochs.

The native reset and allocatedSize query remain outside the pool/group/child locks. finishRelease then locks the pool, checks no writer/no users/Resetting, increments reset statistics once, updates allocated/reset baseline bytes and recordings0, and applies the existing poison/availability/idle-memory budget rules before publication. Later release of ownership/native objects remains outside the locks. The patch does not weaken primary/tail feedback or submit scheduling gates, notification/callback ownership, record cancellation, or command-buffer disposal. Unsubmitted ended-state teardown uses the same existing reset ordering as the prior Sealed path.

The reset itself does not prove memory was physically freed. Native retained heap capacity remains charged by existing idle accounting; the growth threshold is not an absolute total-memory cap. More quiescent resets may reduce old command-byte accumulation but also add CPU work; FPS and net memory effects require separate measurements.

## Related fixture review

The CPU fixture changes introduce a reset callback on the existing native receiver and seven related scenarios while retaining the prior count/growth boundary suite:

1. Cold reservation rollback has no reset, followed by one ended recording resetting below count32.
2. Two ended/unsubmitted users defer reset until the last owner.
3. Completed GPU work cannot reset a newer open writer on the same epoch.
4. Out-of-order GPU completion defers reset until the last outstanding use.
5. Reentry during native reset sees poolMutex unlocked, Resetting/unavailable old storage, and takes an independent epoch.
6. Oversized retained native capacity cannot bypass idle budget after reset.
7. Poison discards without reset/reoffer.

The fixture's quiescent-policy mode runs these plus the existing actual production count/growth/open-cancellation tests. These are meaningful ownership/accounting assertions, not a separate implementation of the new policy.

The native epoch replay adds an optional resetAtQuiescence argument. Defaultfalse retains historical count-bound expectations; Q's optional mode uses12 real fill/signal/guard/pack-reuse iterations and expects one reset at each proven quiescent retirement. The timing of waits/guards/native completion is not weakened. It supports a distinct Q native validation without rewriting C's old expectation. Test output has not been accepted by this source review; root must verify actual run records and final hashes.

## Remaining handoff

Review related CPU/native outputs, final product/fixture pins, raw/package identity, diagnostics0, strict signature/dependency closure, then root-owned C/Q Metal3/4 matched comparison. C remains current pending evidence. No existing historical timestamp or sampled-exit issue is resolved by this small change.
