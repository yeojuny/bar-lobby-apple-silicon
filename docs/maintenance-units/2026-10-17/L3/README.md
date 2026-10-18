# L3: common debug callback traversal locking

Guard the common debug messenger/report-list walk and callback dispatch with the Loader lock, including loader_log paths before stderr filtering. Remove redundant submit-terminator locking in the same atomic unit. This contains the exact ordered official pair `e38751a7c03588c2f1fec742f611cbafff864158` and `73cf5326e8c87d7922b235666198988064b0f294`; no partial pair was built or accepted.

The complete [patch](change.patch) includes63 official logging-loop test additions plus51 test-only observation additions in the existing threading target. Final production checks pass23 cases:10 unit-specific and13 cumulative L1/L2 on raw SHA256 `61ff2158bcf1169dd08c4e8a84c3e1aa53cbf6a76b6e40dbaa1e1fa65911cc12`. Both stderr filter modes observe64 actual callbacks; the matching stderr message counts are0 when off and64 when on. Callback userdata survives all joins and observer destruction, with no Vulkan API reentry from the callback.

[Manifest](manifest.json), [recipe](recipe.md), [validation](validation.json), and [applied audit](applied-audit.json) record the exact public-base reconstruction, pre/post hashes and final binary binding. Flags/link, cache values/types,1015 export names, dependencies and install name remain preserved. Cache byte identity is not claimed.

macOS uses a recursive mutex; the first change alone is not asserted to inevitably deadlock. Filtering stderr off still reaches the helper lock, so no speed/FPS/energy benefit is claimed. Ordinary mock stress does not establish sanitizer-backed race freedom, all callback/layer lock interactions or global deadlock freedom. No GPU/window/app/game/FPS/MP/endurance acceptance is included.

This is the eighth and final source checkpoint. It does not publish a new app, Release, Homebrew update or V1 package.
