# Cumulative change map

This map describes the R80 source checkpoint. Exact modifications are authoritative in the patches and per-file hashes. It does not imply a separate FPS measurement for each item.

| Layer | Preserved areas | Main source locations |
|---|---|---|
| Recoil platform baseline | SDL3/EGL bridge, Cocoa fullscreen/safe viewport and input adaptation, Apple CPU/thread support, retained compiler compatibility | `rts/System/SDLCompat`, `rts/System/Platform/Mac`, `GlobalRendering`, `SpringApp`, build files |
| Recoil common rendering | Stream-buffer completion/reuse, primitive restart preparation, pending glyph-atlas uploads, upload/worker scheduling | `StreamBuffer`, `IndexBufferRestartState`, `CFontTexture`, `ThreadPool`, `ThreadAffinityGuard` |
| Recoil Lua VBO | Direct numeric conversion into CPU storage; mixed layouts, partial upload and Download compatibility; callback deletion/engine-owned-buffer rejection | `rts/Lua/LuaVBOImpl.*`, `LuaVAOImpl.*` |
| Recoil model data | Dirty updates, upload storage lifetime, reuse of model-data snapshots and shared-memory-friendly upload preparation | `ModelsDataUploader`, `ModelsMemStorage`, `Models/3DModelVAO`, `Common/UpdateList` |
| Mesa/Zink baseline | Retained macOS/EGL and primitive-conversion behavior; reviewed NIR/NEON/index correctness changes; existing local async-wait policy | EGL sources, Zink sources, NIR, auxiliary index helpers, Mesa state tracker |
| Mesa/Zink common optimization | MVK render-pass optimization selection and replacing the unnecessary CPU wait before presentation in the supported semaphore path | `zink_screen.c`, `zink_context.c` |
| MoltenVK Metal4 | Direct command backend, recording/submission ownership separation, grouped allocator retirement, stable resource/prepared-binding caches, argument-table preparation and retained primitive conversion | `MVKMetal4Submission`, `MVKCommandBuffer`, `MVKCommandEncoderState`, descriptor/resource/queue classes |
| MoltenVK correctness | Scoped synchronization, query/timestamp dependencies, attachment preservation across pass interruptions, MSAA resolve, visibility ring handling, GPU completion and CPU submission/callback shutdown lifetimes | command/query/render-pass/queue/sync sources; Metal3 and Metal4 as applicable |
| SPIRV-Cross and retained intake | Compiler pointer/alias handling and selected integration fixes; MVK retained helper-binding restoration, dynamic primitive and shader ownership corrections | See exact dependency patch and `provenance/run95-intake.json` |

The source export was compared with the engine inventory used by r78 (whose engine is retained in r80), the r60 Mesa inventory (retained in r80), and the r80 MVK inventory. Run labels describe integration checkpoints, not three independently interchangeable versions.

## Validation reached by R80

- 112 bounded native/Vulkan/packaged graphics checks passed.
- 12 additional configurations covered actual memoryless timestamp, depth/stencil resume, MSAA resolve resume and visibility-query ring cases across applicable backends.
- Seven game runs in the recorded comparison series completed; the R80 Metal3 and Metal4 runs also passed 18 total existing Lua VBO checks.
- These results do not certify all Vulkan features, all scenes, all callback orderings, or multiplayer simulation determinism.

## Later work not included in R80

1. **Font path/cache candidate:** preserved separately; implemented and independently reviewed, CPU-validated; app integration pending.
2. **Zink copy-region tracking:** identified correctness candidates still awaiting the next implementation stage. The new region-containment fixes are not silently included in this archive.
3. **SSAO/current capability checks:** follow-up work, not part of the R80 checkpoint.
4. **Additional Metal3 async optimization:** investigation remains; no claim that all async waits can be removed.
5. **Chobby engine backport:** separate future work requiring exact room engine/content identity and cross-platform simulation checks.

## R81 font candidate details

The engine restores the originally loaded fallback filename into `FC_FILE` after querying the Fontconfig pattern. This lets archive/VFS fonts resolve again at another size while preserving explicitly registered absolute paths. Failed pattern creation/insertion is checked and untransferred patterns are released. System-discovered patterns are not rewritten.

The bundle configuration adds `fontcache` before home/XDG cache entries. Normal Recoil app startup changes to its writable data directory before font initialization, so this is the existing local cache location even with Fontconfig home access disabled. The special `--gen-fontconfig` CLI path is outside that normal startup guarantee.

CPU evidence used the actual packaged Fontconfig 2.18.3 and FreeType, selected archive CJK/emoji font data, and a VFS fixture: 53 checks including two raster sizes and injected failure cleanup; four home-on/off config cases; ASan/UBSan of the caller fixture; syntax-only compilation of the actual font source. Independent Astra XHigh review found no actionable defect in this two-file change. Actual app initialization, cache reuse, GPU atlas and UI appearance still need the planned integration run.
