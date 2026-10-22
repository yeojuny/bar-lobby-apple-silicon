# Independent Q validation/package readiness review

**Ready for root's matched C/Q Metal3/4 comparison, with no actionable blocking finding.** Root should freeze source/build/fixtures before performance and run no concurrent build/GPU fixture work. This review reads existing outputs and verifies hashes only; no build/test/GPU/app execution or product edit occurred. C remains current until actual results justify another selection.

## Code and identity

The final11 product pins exactly match the previously reviewed Q source. The product delta remains a single releaseAllocatorLocked hunk over byte-exact rebuilt C: at zero remaining users, no writer and normal Appendable state with ended recordings, elect the existing Resetting/outside-lock reset/reoffer path. Count32, growth2MiB, available8, idle64MiB and all poison/GPU/unsubmitted/writer lifetime rules remain fixed. D/E1/E2/E3/count64 are absent from Q.

Q-build succeeds and records rawSHA256 `685f3f3b6901e12ff781e0c2bbd797953737f851b2193d665f8cbf86740ac3bd`. The retained raw file independently hashes to this value. Actual packaged MVK independently hashes to `3f7ae550916228c89eec51f3f1741e54b5fbe62929e03a22038158d7ba076dd6`, matching Q-package. Package source-patch hash matches Q-from-C.patch, and all source/fixture pins match current files. The unchanged CMakeCache hashes to the before receipt, and C/CXX/OBJC/OBJCXX compiler flags all explicitly set diagnostics0.

C and Q recorded inventories each have1194 entries and differ only in the packaged MVK, BAR executable signature and CodeResources. Engine/launcher-content components remain equal in the manifests. Q package records211 closure edges and strict deep signature success; this reviewer reads those existing validation results and does not rerun signing/loader checks. Both display1.0.3, local v1.0.4 candidate.

## Actual related execution evidence

CPU run uses the existing production-linked fixture with ASan/UBSan and quiescent-policy mode;916 checks pass, comprising the existing count32/growth/open-cancel policy suite plus seven new quiescent scenarios. It covers cold reservation nonreset, one/multiple ended-unsubmitted owner retirement, GPU completion while a newer writer is open, out-of-order outstanding GPU uses, reset outside poolMutex with reentry unable to take Resetting storage, retained native-capacity idle-budget rejection and poisoned discard. It does not infer GPU completion from recording end.

Native run passes five cases with Metal API Validation: quiescent epoch fill/signal/tail/guard replay, blocked/cancelled resource packs, poisoned pool, independent multiple submissions and blocked event lifetime. The replay explicitly uses resetAtQuiescence=true and reaches12 actual completions with12 resets, while requiring one allocator/primary/tail pack reuse, exact output guard bytes, terminal old-wrapper detach and idle memory bounds. This proves selected native lifetime/output behavior, not BAR reset frequency or memory/FPS improvement.

The original native test file was updated after the tested selected-native harness was generated: its general main now passes true, and the reset failure message is policy-specific. The tested derived main already passed true, and no tested condition, loop, wait, output, reset expectation or product byte changed through those later textual edits. The final fixture pin accurately records that source state; another GPU repetition would add no distinct execution coverage for these changes. Historical count-based behavior remains available through the helper's defaultfalse mode when intentionally validating C.

## Scope and decision

Source review covered reset election/accounting/window/reentry/poison and multiple GPU/unsubmitted/writer ownership; these selected executions supply the related dynamic evidence. A full unrelated render/descriptor suite, or E1/E2/E3 retest, is not required for this allocator-only C delta and was not claimed.

More frequent quiescent resets can add CPU cost. A native reset can preserve allocated heap capacity, so no physical memory reduction, allocator net benefit or guaranteed speedup is established. Actual C/Q comparison must bind role-specific loaded runtime hashes and use the same AC+LowPower/private cold-cache/hidden safe-fullscreen scene. n=2 and background-load limits should remain explicit. Existing historical timestamp/sample-exit uncertainties are not closed by these selected successes.
