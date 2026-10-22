# Independent R readiness review

**Ready for root-owned Q-R-R-Q Metal4 comparison, with no actionable blocker.** Final source/fixture identity, related correctness evidence and signed-package binding agree. Reviewer read records and performed bounded hash/JSON checks only; no product/fixture edit, build/test/GPU/app execution, or whole-app inventory/hash repetition occurred. Stop owner builds/GPU correctness work before performance and keep source/apps frozen.

## Final identity and package

All38 review-pins match actual source/build-cache/fixture files. The final11 product pins remain the source-reviewed R state; Q→R still changes only takeAllocatorLocked selection/removal, preserving the previous Q last-use reset and all ownership/accounting rules. R-from-Q.patch hash matches the package receipt.

R's retained raw library independently hashes to2567b8f7428fb27d4a13638765ea5807fda47ca915b099f5ddd0f24d18dba024 and actual packaged MVK to8f8010bdcb59397564c21c80ad2eb87fb4690b45e6def36478db7e11fc781462, matching the successful incremental build/package records. Diagnostics compile0 and the unchanged cache/compiler policy remain bound by review pins. Q/R recorded inventories each contain1194 entries; only packaged MVK, BAR executable signature and CodeResources differ. Package records strict deep signature success and211 dependency closure edges. Signing/loader checks were not rerun by this reviewer. Version remains1.0.3, local v1.0.4 candidate.

## Related correctness outputs

The existing production-linked CPU fixture under ASan/UBSan passes1027 checks in idle-first-policy mode. It retains Q's count/growth/quiescent cases and adds the four natural multi-epoch cases reviewed in independent-source-review: back-busy/older-idle selection, most recent eligible idle and accounting, all-busy exact LIFO, already-idle-back fast path, and pending GPU/unsubmitted ownership protection. These are actual helper/ownership implementations with CPU receivers, not BAR frequency/timing measurements.

The same expanded CPU fixture against exact frozen Q successfully compiles, then fails as expected at check938: “most recent idle epoch wins over newest busy epoch.” This negative control distinguishes the intended policy; it is not an unexplained product failure. The prior Q policy still passes the preceding boundary behavior up to the new selection expectation. Root moved exact preimage bytes to a header-free include location after an initial duplicate-declaration compile error; sibling headers are unchanged Q/R bytes. The preserved first compiler failure is separate from the successful policy oracle.

Native Metal validation passes six cases, comprising the previous five Q lifetime/replay cases plus the new idle-selection GPU replay. The existing quiescent replay records12 completions/12 resets. The added case creates independent concurrent writer epochs, preserves an ended/unsubmitted recording at the busy back, retires selected idle storage independently, validates reset count2 as a selection witness, checks output/guard bytes before submitting the preserved stream, then submits it later and verifies both streams. It does not weaken blocked/cancel/poison/multiple-submission/event ownership or completion checks. Native pass counts establish selected correctness behavior, not actual BAR idle-choice frequency or speed/memory benefit.

## Preserved preparation failures and scope

The first package attempt referred to a JSON receipt instead of Q's app path and stopped before app creation. The oracle's first compile mixed snapshot and active sibling headers and stopped on duplicate declarations. preparation-corrections.json and original logs preserve both; corrected attempts are bound to the same product patch. No failed runtime was relabeled as a success.

The change is native Metal4 allocator selection; unchanged legacy Metal3 execution does not call this policy. A bounded Metal4-only Q-R-R-Q experiment is a reasonable next performance check, and a full unrelated renderer/M3/FPS suite adds no distinct acceptance evidence to this isolated change. There is no obligation to report a gain if the bounded scan offsets any opportunity.

OS context records macOS27.2 build26B118. Human observation of a recent RC update is kept as an observation; the build number alone does not prove channel or explain FPS movement. Pin the same OS before/after this within-session comparison and do not pool historical all-time FPS into a causal policy estimate.

Q is now the human-selected current baseline. R may avoid extending live epochs when an unused one exists, but the metadata scan adds up to the fixed available8 bound under the existing mutex. No new wait/reset/capacity/ownership shortcut was introduced. Actual opportunity, long-term memory/churn and stable FPS benefit remain unmeasured; root's upcoming actual app comparison is separate evidence.
