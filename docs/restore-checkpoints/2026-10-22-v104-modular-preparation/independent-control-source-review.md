# Independent source review: modules 02, 03 and 09

Status: source capsules accepted for staged preparation; no blocking source finding. These are unapplied proposals, not activated products or established performance improvements.

## 02 — immutable layout predicate

The postimage computes exactly the prior ANY-Vulkan-flags/four-buffer-type predicate after populate and Vulkan flags merge, inside the existing construction loop. Its false value is monotonic; sorting and later GPU/CPU packing do not change that predicate. Empty layouts remain true, zero-count bindings still participate, and pipeline/set/layout guards remain. Foundation OFF has neither the member nor its work. This changes layout ABI when enabled, so activation must rebuild all dependents. Actual BAR early-prefix reach remains an effect gate, not a reason to call the capsule unsafe.

## 03 — owned prefix chain

The retaining branch saves the original successor before detaching the current node and appending it to the exclusively owned replay chain. Final release clears head/tail and disables retention before any command may return to a pool; releaseCommands already saves its successor before a pool can overwrite _next. Restore splices the prefix ahead of the ordinary suffix, preserves the suffix tail, clears replay ownership, then clears preparation. Reset/clear and timestamp-activation paths preserve their previous order.

The live encoder does read `_lastMultiviewPassCmd->_next` during multiview rewind. The safety argument is encode-before-transfer for a complete staged render pass, not a claim that no other reader exists. The source patch preserves this order. The CPU fixture tests chain ownership/restore and simulates traversal; it does not execute the real multiview encoder or prove native failure recovery. Those remain activation checks.

## 09 — immutable entry during unlocked callback

Replay takes a strong immutable CPU entry under the cache lock and invokes retain outside it. Miss erases only when the map still contains that exact entry, so a replacement with the same revision is preserved; Failed leaves the entry unchanged. Current native validation and submission ownership still occur in replayMetal4Resource under its respective live guard. Cache clear/replacement can no longer destroy an entry in use by a callback.

Remember checks resource admissibility and the map limit before make_shared. The Entry constructor delays moving the resource vector until allocation has succeeded. A bad_alloc preserves the old map and already acquired native ownership. A later map-node allocation failure may consume the optional input vector before discarding it, which is allowed by this rvalue-only cache API; it does not release the recording's native retention. The map remains bounded to 64, but concurrently replayed replaced entries add temporary CPU memory beyond that map bound. Reference counts, allocations and contention tradeoffs remain unmeasured. External object lifetime and legal descriptor-update synchronization are still caller obligations.

## Existing root receipts read

Root CPU receipts report ASan+UBSan: layout 9,798 checks, chain 17,908, snapshot 49 plus six concurrent schedules; all exited zero. The combined control overlay reports full-source syntax for four translation units at Foundation 0/1, eight exits zero. These are recorded CPU/syntax qualification only; I did not rerun them, compile, use GPU or change active files.

All module manifests, exact payload bytes and forward/reverse patch digests were read and cross-checked. Related baselines were read directly. No blocking findings; native/backend/app/performance acceptance remains pending the explicit execution stage.
