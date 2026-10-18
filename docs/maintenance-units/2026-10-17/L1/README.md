# L1: protect WSI surface-list lookup and lazy creation

The complete [patch](change.patch) applies [2d3e7b9b](https://github.com/KhronosGroup/Vulkan-Loader/commit/2d3e7b9bae969ebd662a2df36ec4251848aab435): eight exact official production added lines and57 exact official regression added lines in the existing threading target. The port's VK_USE_PLATFORM_MACOS_MVK legacy early-return context, handle conversion, prior surface create/destroy locks and earlier unit changes remain. Both post-acquire return statements release the recursive loader lock.

Five related cases passed against final production Loader BUILD_TESTS OFF: two ordinary mock threading cases and three selected WSI normal/error cases, using the actual new raw Loader. No sanitizer ran and the new stress case was not shown failing before the fix. These results are not proof of race freedom, every interleaving, GPU/window behavior or app/game/FPS/MP acceptance.

The queried surface stays alive until all workers join; separate batches of70 other surfaces exercise shared-list growth/destruction. This does not permit querying and destroying the same surface concurrently. Product C/ASM flags/link command and1015 export names/dependencies/install name remain exact. Cache values match, but bytes differ: ENABLE_LIVE_VERIFICATION_TESTS changed BOOL to UNINITIALIZED while its value stayed OFF.

See [manifest](manifest.json), [validation](validation.json), [applied audit](applied-audit.json) and [recipe](recipe.md). Reconstruct public port Loader -> L5 -> L4 -> L1; keep separate SDL S1/S2 and C1 f52facf7 identity unchanged. This source checkpoint updates no app, existing tag, Release, Homebrew or V1.
