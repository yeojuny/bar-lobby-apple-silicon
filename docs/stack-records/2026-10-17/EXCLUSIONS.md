# Excluded, deferred and reference-only work

These records explain what was investigated without labeling it as shipped. Upstream status may change independently; inclusion is determined by the frozen source, not by an MR later closing or merging.

| Proposal | Local inclusion decision / distinction |
| --- | --- |
| Mesa !40962 | Excluded from the retained stack. Per-renderpass deferred submission is not the same as accepted presentation or semaphore changes. |
| Mesa !34957 | Base-instance lowering removal not selected. |
| Mesa !44865 whole proposal | Not adopted wholesale. Only independent old-swapchain append-pointer commit `07c356d5debdc3c84cfde4f5f1cc045329f26429` was selected. Later !44973 investigation does not mean the whole bundle entered this app. |
| Mesa !40265 and broad threaded-context/upload changes | Not selected by the retained intake. |
| Mesa !45022 / !44948 / !45026 / !45029 / !44498 / !45034 / !43297 | Investigation records are not proof of integration; none is added by this documentation publication. |
| MoltenVK #2837 | Descriptor invalidation/helper restoration contract was unresolved in the intake; not selected. |
| MoltenVK #2831 | Proposed temporary-pool lifetime work not accepted as an implemented fix here. |
| MoltenVK #2853 entire bundle | Not adopted wholesale; the separate local shader-library owning-copy correction is included and attributed separately. |
| MoltenVK #2854 | Not selected in the retained intake. |
| cereal #758 | Not selected; do not infer it from a cereal dependency update. |
| SDL #14244 | Proposed caller failure cleanup was not adopted as written; local property correction is a different change. |
| SDL #15279 | SDL_GPU Metal latency work is outside the active OpenGL/Zink/MoltenVK renderer. |
| SDL #10549 / #15992 / #16432 | Investigated window/animation API proposals, not active backend changes. |
| SPIRV-Tools #6920 / #6916 / #6902; SPIRV-Headers #630 / #603 / #604 | Investigated dependency candidates; no inclusion claim beyond the exact pinned snapshots. |
| Recoil #2921 platform sync workflow | Upstream reference/test methodology; exact ancestry shows this merge is not in either selected engine base. It does not certify macOS multiplayer here. |
| Historical Run96 / Mesa !40962 experiments | Retained failures/experiments are not the current selected runtime. |
| Retired SDL_GPU WIP55 / separate native Metal4 project | Separate work; neither is silently substituted into this port or changed by this publication. |

Historical approval/author screening decisions are retained as history, not represented as current official approval. The original [Run95 intake](evidence/historical-run95-intake.json) preserves its retained/held lists and exact patch hashes; its “source-only” phase status is historical and does not describe the later packaged release.
