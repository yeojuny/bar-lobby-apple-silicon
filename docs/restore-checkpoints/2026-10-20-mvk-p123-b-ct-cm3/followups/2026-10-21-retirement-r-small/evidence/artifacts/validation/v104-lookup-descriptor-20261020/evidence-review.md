# Independent evidence review — lookup/descriptor candidate

**Result: no remaining arithmetic or evidence-interpretation defect in the final diagnostic summary, subject to the limits below.** Source/product/fixture hashes still match the six reviewed pins. This reviewer read existing output and performed small JSON/hash calculations only; no build, test, app/game execution or product edit was performed. The ongoing final C-versus-candidate performance sessions were not inspected or disturbed.

## Related validation evidence

- Eight syntax cases pass: two affected implementation files × diagnostics ON/OFF × foundation ON/OFF.
- Existing allocation CPU suite: 14 cases pass under the recorded ASan/UBSan build. Production-linked exact registration fixture: 410 assertions pass. Collector: 44 CPU assertions, collector size 206,520 bytes (<256 KiB); both compilation modes' OFF flag cases pass.
- Native registration suite: six cases pass, including state rejection, generic/typed residency retirement, heap/view and independent owner. Selected prepared cases: three pass; the common descriptor-template case passes once each on Metal3 and Metal4.
- The initial prepared fixture compile failed because MVKFoundation.h was absent from the include search path. The corrected command adds the existing build's includes/defines and passes. The original compile failure remains recorded; this was not a product behavior failure or a suppressed runtime assertion.
- The prepared/template selected fixtures report zero for all nine new counters. They support their selected output/lifetime cases but do **not** dynamically cover all new recording partial/group snapshot branches. Those branches were source-reviewed; current BAR observations also report zero group partial and group snapshot outcomes. No broad claim that every counter branch was exercised is warranted.
- Release restoration receipt reports the release raw dylib byte-exact to its saved OFF output, and all four CMake language flags restored to MVK_ENABLE_CUSTOM_DIAGNOSTICS=0. This review reads that receipt and validates current source pins; it does not repeat the large binary build/hash operation.

## Diagnostic selection and arithmetic

Three actual BAR.app sessions completed normally, collector OFF/ON/OFF, protected inputs unchanged, no remaining owned processes, AC+Low Power contract passed. Only the ON run supplies the descriptor counters.

Raw output contains 67 queue-bin rows: 31 fully-contained nonempty encoding-delivery bins are eligible, the first 20 under the selection rule are used, 11 eligible later bins are retained as unselected, and 36 outside/empty rows are excluded. The final summary now records all populations. The initial summary omitted the later 11 from its selection accounting; root preserved that initial file and corrected only the selection metadata. Selected rows/totals/ratios are unchanged. Every selected row lies within the recorded host benchmark bounds and the raw queue has invalid_encoding=0.

Recomputed totals from the selected rows:

- Group checks 1,886,293 = recording full hits 1,654,897 + preparations 231,396. Group snapshot full, recording partial and group snapshot partial are all zero. Full fraction is 87.7327647402%; the remaining 12.2672352598% are whole binding-list walk groups, **not slow-payload counts**.
- Binding visits 776,730 = buffer hits 28,451 + texture hits 2,885 + per-binding snapshot hits 10,894 + slow successes 734,500. This equality holds per selected row as well as in aggregate. Slow success is 94.5631042962% of **visited bindings**, after full-group skips, not of all potential bindings or CPU time.
- Residual visits are zero. Slow descriptor resource slots read are 1,456,088; they are actual CPU object-slot reads, include null, and do not denote unique resources, GPU accesses or removable reads.
- Encoding counts use delivery-time bins. Being fully contained does not convert them into exact simulation-frame attribution or make CPU/GPU timing columns the time spent in these binder branches. Adjacent queue timing statistics cannot assign cost to the new counters.

OFF FPS is 40.3489 and 42.5663; ON is 44.1332. ON is +6.4538% versus the OFF mean and exceeds both OFF runs; the two OFF values differ by 5.4956%. These three samples do not isolate collector overhead or prove it is free/beneficial. Runtime OFF on the diagnostic compilation also does not equal the release-OFF binary. Use only the separate release-OFF C/candidate comparison to assess the shipped candidate's FPS.

## What follows from this evidence

The actual BAR path shows that full-group caching already skips most groups and that the remaining visited bindings mostly take the slow-success path. This justifies selecting **slow descriptor preparation for a narrower source/design investigation** rather than immediately expanding recording ownership, allocator policy, passes or synchronization.

Precomputing immutable descriptor-layout interpretation in the existing bind script is a plausible small candidate: resolve only layout-fixed facts once, while preserving variable descriptor counts, payload range checks, descriptor revisions, pool incarnations, live guards, resource proofs, GPU retention/residency and drawable conditions at their required times. The current counts do not establish how much time layout interpretation costs, why particular cache/snapshot attempts miss, whether layout interpretation rather than resource validation dominates, or the resulting FPS benefit. Precomputed layout metadata would not itself remove the 1,456,088 payload reads. A concrete patch requires source inspection of already-cached metadata and a separate output-preserving validation plan; it is not yet an evidenced performance win.

Root/direct/implicit/vertex, allocator, pass/sync costs and detailed miss reasons remain outside this diagnostic. Zero observations in one scene do not justify removing or weakening snapshot/partial paths. The registration lookup optimization's own opportunity frequency is also not counted by these descriptor fields.
