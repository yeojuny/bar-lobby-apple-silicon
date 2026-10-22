# Group locator on both baselines: independent final readiness review

Both R+group-locator and R+D+E1+E2+E3+group-locator pass the bounded source, validation and package-evidence review. No actionable defect was found. Both new apps are ready as comparison candidates; original R remains selected. Active source/build is R+group-locator. FPS benefit remains unmeasured.

Reviewed final report SHA256: `063890c0f7152c4dc4041a753f51000dbacdfa48bee707db489b3311b29a0aab`. This review performed read-only source/evidence/hash comparisons and wrote only review files. No build, test, GPU workload, app, benchmark or cleanup was executed by the reviewer.

| Evidence | R+locator | Combined+locator |
| --- | --- | --- |
| Actual-header/frozen-reference CPU ASan+UBSan | 46,290 checks pass | 46,290 checks pass |
| Test-only hot lookup hash calls | 1,200→0 | 1,200→0 |
| Cache metadata size | 40→136 bytes | 40→136 bytes |
| Native sequential recording/output/lifetime | One selected case passes | One selected case passes |
| Vulkan descriptor revision, compatible layout, fragment texture/sampler | Three each on M3 and M4 pass | Three each on M3 and M4 pass |
| Incremental MoltenVK build/foundation-OFF syntax | Exit0/0 | Exit0/0 |
| Package inventory / closure / strict deep signature | 1,194 /211 /pass | 1,194 /211 /pass |

The independent source review remains applicable. Each variant changes only GroupCache inside MVKMetal4PreparedResource.h relative to its own baseline. Frozen11-file source snapshots match variant pins, all38 current source/fixture/build pins match R+locator, and current raw build matches its R raw library. The variant source-pin maps differ from their respective frozen baseline maps only in the changed header. Both next headers contain the same new class and preserve their original D/E1/E2/E3 and Q/R allocator differences. The reviewed CPU fixture hash is `554fce2fa266714bab05c083544a9427b15973302a3f8911b32b91d72e940a9d`.

All final CPU/build/native/Vulkan/foundation receipts for both variants have exit0. CPU logs report matching complete/partial returns and callback counts,46290 checks,1200→0 test-hasher calls and metadata40→136 bytes. The50000-step trace and targeted lifetime/boundary cases are covered by the already reviewed fixture. Generated native and Vulkan fixtures preserve the exact existing source prefixes and select only the intended cases. Metal4 Vulkan logs show active native queues and retired completed submissions; Metal3 logs record native=0 without active native Metal4 queue messages. Native sequential output uses Metal API Validation and confirms recording-end metadata release and a new-recording miss. Its synthetic CPU proof token does not certify resource provenance.

Raw and actual packaged MoltenVK hashes were independently checked:

- R raw `58a5dbd37015cae8de285032d0e7d4a5c39988ed85a3e194730fb64f741d4f6a`; packaged `348663cdb393dbc0d2a94305ae00faeebd78b2aa8604b89f17adcdd55260751b`.
- Combined raw `94255e91bb29ef62b646bcf1cdc0bba6138e6e13fdb821096a72ca5fe0fbb31f`; packaged `772042e655d17f2e957230c83b0a2ec186c2c34c0ed76838fd53c6e6ae5db490`.

Both new inventory manifests contain exactly the same1194 entries as their corresponding frozen parent, with no added/removed paths. Precisely three entries change: MoltenVK, launcher re-signing and CodeResources. Packaging receipts/recipe bind unchanged launcher executable text, parent byte-exact preservation,211 closure edges and strict deep signatures. Full-app hashing/signing commands were not repeated. Both apps display1.0.3 and remain local v1.0.4 candidates. Diagnostics compile0, fixture runtime diagnostic flags OFF and allocator32/growth2MiB/available8/idle64MiB remain. No new product instrumentation exists.

The selected candidate JSON directly equals the pre-task R state. Root completion checks preserve actual profiles and launcher HEAD/index/status. There were zero BAR app/game sessions and no FPS comparison in this task. The observed hash-operation reduction does not quantify runtime benefit;96 bytes per recording plus branch/clear/space costs mean neither FPS nor net-memory improvement is established. Selected GPU coverage does not establish complete conformance, all concurrent schedules, race-freedom, MP or other-Mac acceptance.

Cleanup evidence is consistent: six successful standalone executables and six dSYM roots total12 roots,24 leaves and13,151,781 logical bytes. The reviewer independently summed nested manifest leaf sizes/counts, checked associated build receipts and observed all selected roots absent. Physical reclaim is unmeasured. Raw libraries, old/new apps, product/test/generated sources, recipes, successful logs/results and Markdown remain. Original completed cleanup selections were not repeated. The final report accurately distinguishes this bounded implementation/qualification from unmeasured FPS benefit.

Machine-readable input hashes and per-variant evidence are saved in `independent-readiness-review.json`.
