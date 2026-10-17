# Local changes, costs and validation

## Foundation versus local work

The port builds on Recoil/Spring, BAR, Mesa/Zink, MoltenVK, SDL, shader tools and their contributors. The existing ARM64 deterministic floating-point foundation is upstream work, not a new invention by this project. Earlier macOS baseline work and external integration records retain attribution. The cumulative source patches are not a count of independently authored optimizations.

The r57 engine optimization investigation explicitly studied [benbreen's Apple Silicon Recoil port](https://github.com/benbreen/RecoilEngine-AppleSilicon/tree/a49a8ecc5265c4dd3f8d0016d90b32e81e22c73b). Fence polling, model-ring depth and worker QoS ideas retain that origin. Our restart adaptation used a narrower sentinel proof. r58 added local stream lifetime/cleanup/alignment fixes; r73/r75 later reduced Lua upload preparation. [Detailed chronology and performance evidence](../../engine-patches/2026-10-17/ORIGIN-AND-PERFORMANCE.md).

## Local change map

| Area | Local implementation/adaptation | Cost or acceptance boundary |
| --- | --- | --- |
| SDL3/Cocoa/EGL | Native window/context ownership, target-screen safe-area/fullscreen handling, input/audio migration | Target-screen handling is functional code, not expendable diagnostic instrumentation. Different-display acceptance must be scoped to actual evidence. |
| SDL properties | Invalid property-ID pointer checks and exactly-once cleanup after allocation failure | Three-line correction beyond the pinned development source; historical public-API and property tests, no standalone FPS gain. |
| Shared Recoil renderer | Stream slot completion/lifetime, aligned byte stride, model upload preparation, index-restart proof, VBO/VAO layout and callback ownership checks | Required GPU waits retained; larger rings, CPU shadows and staging have memory costs. |
| Lua VBO preparation | r73 direct numeric iteration, r75 typed instance upload | No zero-copy claim; no isolated FPS gain. Later safety checks retained in split patches. |
| Fonts | Owning fallback paths, Fontconfig cache routing, deferred atlas upload preparation | Cache/font correctness and deferred work retain resource lifetime requirements. |
| Equivalent NoGS / CUS | Family-specific mesh/instancing paths, GS support separate from OpenGL/GLSL version, current content/engine ABI adaptation | No blanket effect disabling; synced game content and official engine identities remain separate. |
| Mesa/Zink | macOS drawable/EGL adaptations, dynamic primitive handling, device-loss cleanup, valid byte-range/copy tracking, narrowly supported presentation/submit paths, additional ordered-dependency guard | Local code differs from some selected MR heads; required semaphore/fence/hazard handling stays. !40962 excluded. |
| MoltenVK common correctness | Dynamic fan/topology handling; shader-library owning-copy protection; query/pass/attachment/MSAA/visibility and callback lifetimes as applicable | Owning-copy fix may trigger later recompilation; correctness work is not automatically faster. Not every path is exhaustively GPU-certified. |
| Experimental MoltenVK Metal4 | Command recording/replay/submission ownership, allocator retirement, resource/binding preparation reuse, timestamp entry-boundary work and later small R1/R2/S1/R5/R4 changes | Additional CPU state, locks, staging and fallback remain real costs. Metal4 does not guarantee higher FPS or lower power. |
| Numeric compatibility / SHIELD | Retained ARM64/x86 conversion and compiler policy, simulation identities preserved per lane | Numeric fixtures do not replace fresh cross-machine multiplayer/replay acceptance of every release. |
| AI integration | BARb/CircuitAI JsonCpp C++ symbol isolation and configured Apple linker fixes | AI logic/C interfaces retained; loader success is not complete AI gameplay or determinism acceptance. |
| Launcher lifecycle | Download/checksum write ownership, shutdown close/drain, Chobby handoff/concurrent preparation and setting/display migration | Correct ownership may retain waits; no automatic termination of user manual games. |
| Candidate.5 maintenance, unpublished app | CPU;RAM hardware metadata, Options recognition, diagnostic output/default cleanup and conservative Darwin disk-path fallback | Not a graphics-stack update, no fresh candidate.5 game/FPS claim, final release still held. |

## Existing evidence and this publication

Historical integrated checks include Lua/VBO sanitizers, native resource lifetime fixtures, selected shader translations, packaged native graphics checks, both-lane launcher/menu checks and scoped game captures. The existing full VBO fixture was rerun for the patch extraction and passed 2,024 cases / 41,666 assertions. The separated file projection passed 1,218 cases / 24,860 assertions. This publication did not build a native app, run a game/GPU benchmark, install an app, alter settings, or obtain a new independent reviewer/upstream approval.

The user confirmed manual play before candidate.4 publication; the final link-only Chobby engine correction subsequently passed CPU/loader/package checks and was not graphically rerun. No fresh full multiplayer/replay sync, energy/temperature, endurance, clean-machine or different-Mac acceptance is implied. Developer ID signing/notarization remains unavailable.

## Existing performance evidence

The historical Metal3 mean-FPS series rose from 36.6598 (RUN95+VBO) to 43.5240 (r58) and 46.5279 (r80): approximately +18.72% by r58 and +26.92% cumulatively. One run per version, combined engine/Mesa/MVK changes and uncontrolled global cache/background conditions prevent per-patch causal claims. r58 had worse tail times in that series. [Complete retained results, including slow/incomplete later comparisons](../../release-readiness/2026-10-15/PERFORMANCE.md).
