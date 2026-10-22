# Independent source review — combined lookup/descriptor candidate

Reviewed the exact four product files and two extended existing fixtures pinned by `review-pins.json`, against the retained `before/` bytes and `combined.patch`. This reviewer performed source inspection and hash verification only. No build, test, game, app, profile, product or fixture edit was performed.

**Result: no actionable source findings.** This is source-review clearance for the pinned patch, not gameplay, lifetime race-freedom, FPS, or measurement acceptance. Root owns execution and observed output checks.

## Lookup reuse

- `try_emplace_after_lookup` returns a present entry without clearing flags or consuming a cached node. An absent key uses the prior cold `try_emplace` or the same cached-node insertion body. Generic `try_emplace` retains the existing cold fast path and delegates its warm lookup result to the shared body. Cache limits, clear/reset and swap semantics do not change.
- The sole new production call consumes `found` in `addResourceWithKind` after phase/nil/device/type validation and under the same submission mutex. No intervening identity-map mutation or unlock occurs. The insertion result is used after possible rehash, rather than the prior iterator.
- `retainUnique` shares its existing GPU-retention/statistics body. Existing generic callers remain supported. `addResident` shares its existing device-residency lease/stable-buffer/dynamic-residency body. Operation-only identity does not imply GPU retention or residency. The resident hit path is unchanged.
- Texture ownership/drawable processing remains after registration. Identity fields are written before drawable retention can add another map identity. No new recording-spanning cache, ownership shortcut, mutex, capacity change or retirement rule is introduced.

## Nine diagnostic counters

- All nine new fields, binder increments, serializer references and saturation-merge references are enclosed by `MVK_ENABLE_CUSTOM_DIAGNOSTICS`. OFF source preprocessing removes the added fields and binder counting expressions. Existing 53-field instrumentation is unchanged.
- `groupRecordingPartial` is counted only for an actual retained partial result under the existing `stats && before.setMask` denominator. Lookup's complete results carry no partial proof. Snapshot counters use the same denominator and only count successful replay; full versus partial is selected from the returned residual list before moving the proof.
- `bindingVisits` counts every `prepareBinding` entry. Buffer-cache hit, existing texture-cache hit, per-binding snapshot hit and slow success are mutually exclusive success returns. Inline/zero-count/no-stride successes are counted; error returns are not turned into successes. Thus the partition equality requires an error-free measured interval, as the design specifies.
- `bindingResidualVisits` increments immediately before residual-list calls and is a subset of visits. It is not an additional population to sum with visits.
- `bindingSlowResourceSlots` increments only after each actual descriptor-object `memcpy`; null values are legitimate reads. Failed bindings may contribute reads before failure, so this field is not a success count or unique-resource count.
- The existing field array supplies both text and JSON serialization; all nine fields are present exactly once. Existing merge uses saturating addition for each. No clock, log, allocation, lock, owner validation or cache API was added to the binder increments.

## Fixture review and remaining execution responsibility

The existing allocation fixture now exercises the exact lookup-aware overload for cold insert/duplicate, warm fresh flags, same-address reuse, bounded node reuse, transfer via swap, cached-node non-consumption on duplicates and node exhaustion. Initial generic insertion coverage remains. The existing collector fixture adds all-nine sum/delivery-bin and saturation checks; these synthetic merge values are not binder control-flow evidence.

Root must verify actual ON/OFF compilation/field removal, collector size/serialization, the existing production-linked registration cases, actual binder Vulkan output/paths, and real BAR diagnostic equations. The reviewer did not run those checks or inspect future results. Source guards establish the intended OFF behavior; compiled artifact and runtime acceptance remain separate evidence.

No FPS benefit or remaining bottleneck is inferred by this source review. A later source change requires re-binding or re-review.
