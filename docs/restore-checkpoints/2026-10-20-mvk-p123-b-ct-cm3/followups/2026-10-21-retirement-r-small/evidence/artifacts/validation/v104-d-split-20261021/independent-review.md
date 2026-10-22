# Independent review — D split comparison

**No actionable finding.** The 12 actual execution receipts, summary arithmetic, split patch identities, frozen source states and recorded D restoration support the report. This review used frozen evidence only; the active source/build lane is now owned by subsequent E work and was not compared with historical D pins. No product edit, build, test, app or game execution occurred.

## Split identity and binary evidence

C is the previous typed-Buffer baseline. L contains only the lookup-aware identity insertion/registration change. S contains only the nine diagnostic-counter source changes and is compiled with diagnostics OFF. D is their prior combination; it is not an additional execution role in this 12-run matrix.

All four source snapshots C/L/S/D match each build receipt's four product-file hashes. L-from-C and S-from-C patches implement the expected independent units; S does not include lookup reuse. Each recorded sequential build succeeded. C rebuilt byte-exact to its prior raw library, and the final D restoration is recorded byte-exact to the original D raw library, with source/config restored. These are historical restoration records, not a claim about the later E-owned active lane.

The recorded section maps independently confirm that S/C differ only in `__TEXT,__stubs` and `__TEXT,__objc_stubs`; the L/D pair has the same limited difference. Ordinary text/data sections in each pair match. Empty fixup-diff evidence agrees with the report's identical dyld-fixup listing statement. Whole libraries are **not** byte-identical. S has no active new counter collection, so its measured FPS difference cannot be called active instrumentation overhead. Neither these section hashes nor this experiment establish linker stubs as the cause of a performance difference.

L and S packaging receipts each record1194 entries, three explained changes (BAR executable signature, packaged MoltenVK and CodeResources), strict deep signature success and211 closure edges. All displayed versions remain1.0.3, local v1.0.4 candidate designation.

## Actual executions and conditions

All12 receipt SHA256 values match the summary. Actual app paths and loaded MoltenVK hashes match their roles: C `c5ea9b843ba2284c410a0b83b7e2412d4cbc0446f15232b5b317eca56b79f804`, L `58f64d78861679511328731aa62f609839d35af2a30010e6f1b489d6917a68ab`, S `47e120fcdeb4476d8faf40013ac7f9162a0a6db048552d03ea81eb1a65333aa7`. Five-stack-library verification is true in each receipt. The order is Metal4 C-L-S-S-L-C, then Metal3 S-L-C-C-L-S.

Every receipt completes with graceful quit/lobby return, no remaining owned processes, protected inputs unchanged and passed power conditions. All112 observations record AC Power, Low Power Mode and thermal0. Diagnostics/queue/batch/backend-cost/trace/performance tracking are OFF. Metal4 shows one active native queue and backend proof; Metal3 requests native Metal4 OFF and shows zero native active queues.

Quality/camera/resolution/seed/workload/command/game/map evidence is identical across all12: Ultra, AA0, VSync0, Spring;1512×950 notch-safe viewport in logical1512×982 hidden SDL fullscreen; seed7654321;900 simulation frames240→1140; same benchmark command/scene; new private cold caches. Native fullscreen display/Space transition is deferred while hidden, and this is default1× rendering. Draw interval counts are not simulation-frame counts.

## Recomputed results

| Backend | C FPS mean | L FPS mean | L/C | S FPS mean | S/C |
| --- | ---: | ---: | ---: | ---: | ---: |
| Metal3 |51.6531467438|53.1319332123|+2.8629165147%|52.4129085541|+1.4708916265%|
| Metal4 |45.4844970703|44.8044147491|-1.4951958689%|44.2965698242|-2.6117189869%|

All per-run FPS, p95 and draw interval values match actual receipts; arithmetic means and change percentages match the summary and report. p95 means are arithmetic means of per-run percentiles, not pooled percentiles. Completion's report hash matches.

With n=2 per role/backend and uncontrolled OS/user background activity, these observations do not prove a general gain or statistically established regression for either split patch. The compiled-OFF S result is a useful comparison/control, not an active-counter cost measurement. Results do not support promoting L/S as a universally faster candidate or adding their percentages to historical results. Completion correctly leaves C current and candidatePromoted=false.

Source snapshots, patches, raw comparison outputs, original receipts/logs and package inventory evidence remain available. Summary records exact C/L/S/D app inventories, user/launcher preservation, D restoration, screen restoration and awake release. Its cleanup is restricted to successful cache data (72roots/3992leaves/115,427,994 logicalbytes); no physical-reclaim claim is made. This reviewer did not rerun cleanup or reconstruct apps. Later E execution is separate.
