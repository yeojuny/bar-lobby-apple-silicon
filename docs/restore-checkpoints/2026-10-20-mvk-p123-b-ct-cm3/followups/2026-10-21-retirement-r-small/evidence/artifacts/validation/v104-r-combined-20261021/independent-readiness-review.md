# R+D+E1+E2+E3 independent readiness review

The frozen integrated candidate is ready for the authorized eight-session R/Combined comparison. No actionable source, integration-evidence or package-binding defect was found. This review does not claim a performance improvement. No build, test, GPU workload, app or benchmark was executed by the reviewer.

The earlier independent source review remains applicable: all four patches were replayed in memory with exact unique contexts, and Submission.mm was independently reconstructed as frozen D plus the two unchanged Q/R allocator function bodies. Freshly checked 38 production/fixture/CMake pins match the files with zero mismatches. Allocator count32, growth2MiB, available8 and idle64MiB remain; the four language flags set MVK_ENABLE_CUSTOM_DIAGNOSTICS=0. Runtime diagnostics are requested OFF in all eight plans; actual absence still requires execution receipts.

The current build and frozen Combined raw library hash are `3e7741bd33083cb287c7faba80be75489040b549811ae52d30bc7ef8b72f96ff`; the actual packaged library hash is `129e85bb9a7d1cf53a991bbeb5afbbd578b563182de86a1b60ddf57f6b195077`. Both were independently read and hashed before measurement started. R and Combined manifests each contain1194 entries, with no additions/removals and precisely three changed entries: MoltenVK, the launcher signature and CodeResources. Packaging receipts and recipe bind unchanged executable text,211 loader edges and strict deep signature verification. Full app inventory collection and signing commands were not repeated. Both apps display1.0.3 and are local v1.0.4 candidates.

| Fresh integration evidence | Observed result |
| --- | --- |
| Immutable binding-plan metadata | 432 cases |
| Actual typed descriptor/subpass parity | 20728 assertions |
| Existing descriptor preparation | 629, plus foundation-OFF134 |
| Dependency scope / prepared dependency | 524606 /4916882 |
| Changed translation units / Submission syntax | Eight configurations / two foundation configurations |
| Allocation / exact registration / diagnostics-OFF flags | 14 /416 /3 |
| Visibility preparation | 196941 /196842 /196761 across three guards |
| Actual queue emission plus current encoder block | 2097163 assertions |
| Allocator CPU ASan+UBSan / native | 1027 checks /6 cases,12 completions and12 resets |
| Vulkan integration | 15 cases each for Metal3 and Metal4 |
| Native registration / prepared ownership / compact template | 6 /3 /1 each backend |

All final corresponding build/execution receipts have exit0. Initial `gpu-validation/prepared-build.json` has exit1 from a missing MVKFoundation.h include path; its original diagnostics remain. Attempt2 adds the actual Ninja includes/defines and exits0, followed by passing native/prepared/template executions. This is a corrected fixture compilation setup failure, not a failed product execution. The current production binding plan, subpass body with frozen R legacy reference, queue-emission method plus current encoder-local barrier block, and visibility preparation template independently match the actual extracted fixture inputs byte for byte.

The selected Vulkan cases cover dynamic/push descriptors, revision changes, compatible-layout fallback, RAW/WAR including repeated barriers with a current producer, indexed/helper/partial-clear restoration, fragment textures/samplers, both resolve paths, occlusion reuse and single-use handoff. They complement the ownership/allocator cases. CPU counts are not independent whole-game scenarios and should not be summed into a universal acceptance claim. Metadata coverage is not exhaustive binder coverage; descriptor parity does not exhaust every outer extent/layer/custom sample-position configuration. Native ownership cases do not prove every concurrent schedule, race-freedom, peak-memory savings or multiplayer behavior.

The comparison preparation is bound to macOS27.2 build26B118, with R remaining the selected pointer at preparation. Planned order is Metal3 R/Combined/Combined/R, then Metal4 Combined/R/R/Combined; all eight plans request diagnostics OFF. Actual loaded runtime, real backend,900 simulation frames, hidden safe-area fullscreen, AC Low Power, thermals and protected-input preservation remain the forthcoming performance receipt review. Source/build/apps are now frozen, and no further expensive review work is required during measurement.

Machine-readable detail and input hashes: `independent-readiness-review.json`.
