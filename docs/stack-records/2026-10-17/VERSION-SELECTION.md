# Why versions are mixed: ahead, behind and separate branches

Observed on **2026-10-17**. The published candidate.4 stack combines verified upstream snapshots, selected later commits, and local patches. It is not a single chronological checkout of every project. Some differences are intentional compatibility choices; some are unreviewed maintenance work, not proof that an older version is best.

The numerical column below compares the **original base pin** to the official default branch. It does **not** subtract selectively included changes or measure the complete patched binary. Commit counts are not missing-bug counts, performance scores or a patch-equivalence test. [Exact API comparisons](evidence/current-upstream-comparisons.json).

## Both engine lanes and each primary component

| Component | Selected base | Current official default head | Graph relationship / reason |
| --- | --- | --- | --- |
| Launcher | `e2c45c8f` | `e2c45c8f` | [same upstream base](https://github.com/beyond-all-reason/bar-lobby/compare/e2c45c8fcb5461acb3232539493be15cd0fda7ec...e2c45c8fcb5461acb3232539493be15cd0fda7ec). Base equals current upstream default. Newer local dependency pins and macOS adaptations remain beyond it. |
| Lobby engine | `01efdf43` | `01efdf43` | [same upstream base](https://github.com/beyond-all-reason/RecoilEngine/compare/01efdf43121dfd40d105649ef7eb89a8804662d9...01efdf43121dfd40d105649ef7eb89a8804662d9). Base equals current upstream default; our rendering/platform patches are additional local work. |
| Chobby engine | `de693612` | `01efdf43` | [diverged: default-only 117, selected-base-only 5](https://github.com/beyond-all-reason/RecoilEngine/compare/de69361239d8c8b1012dba3f5aa3122954ea4da3...01efdf43121dfd40d105649ef7eb89a8804662d9). Separate published multiplayer contract/branch. Preserve identity and validated compatibility rather than aliasing the newer Lobby engine. |
| MoltenVK | `52aa21f5` | `5189f8de` | [8 newer upstream commits after base](https://github.com/KhronosGroup/MoltenVK/compare/52aa21f54d7a84c5c441fc26359692b0980b384c...5189f8de86ec365860f63bf1da736815cfaea5cd). Retain the verified base plus selected later fixes and the local Metal4 backend. One later pipeline-cache fix is already selectively included; other changes need separate qualification. |
| Vulkan Loader | `b82e310e` | `4224768e` | [19 newer upstream commits after base](https://github.com/KhronosGroup/Vulkan-Loader/compare/b82e310e99c20bfac8dd3123c9e939f81ce54b89...4224768e1844d31f37c5d96b15433eaf46c7bede). Pinned Loader/Headers pair with selected enumeration-loop fix. Later locking/parsing/cJSON/error cleanup changes have not all received local semantic review. |
| Vulkan Headers | `c4685086` | `acbb9391` | [1 newer upstream commits after base](https://github.com/KhronosGroup/Vulkan-Headers/compare/c46850864f4661461b0f6cb9922c058ffea4915e...acbb9391c0a597272800cd3f4363661c00a27c77). The only current-base difference touches .github/workflows/ci.yml for Windows MSVC setup. No additional Vulkan API declarations in this comparison. |
| SDL3 | `4a17e772` | `5ebc96f9` | [91 newer upstream commits after base](https://github.com/libsdl-org/SDL/compare/4a17e772ea9a4ff77dd10fa6ea6f45fc6731eb01...5ebc96f97c3a459284f1572e29cd151f24e4a09c). Retain the tested SDL3/Cocoa/EGL integration and local property fixes. Official latest properties file still differs by the same three local corrections. |
| SPIRV-Cross | `aa217aeb` | `300681bb` | [1 newer upstream commits after base](https://github.com/KhronosGroup/SPIRV-Cross/compare/aa217aeb6c9f0ace7a0ab233b28807edf45eb165...300681bbcb8365a8d1eacdacdbdd0249bbf1d6b1). Pinned compiler plus #2687. The one later upstream commit preserves negative zero in precise multiplication; not yet included and worth a focused shader-correctness review. |
| SPIRV-Tools | `ba9a9e32` | `71f287f1` | [61 newer upstream commits after base](https://github.com/KhronosGroup/SPIRV-Tools/compare/ba9a9e32160e2500ce1e48cc563a8fedaf596e6e...71f287f18ed78d496e724fbfb1c3feae3a2af75a). Retained paired tool/header inputs; previous call-path audit found optional diagnostic disassembly use, not a demonstrated live draw-speed gain from new optimizer proposals. Later changes remain review debt. |
| SPIRV-Headers | `2b7475f6` | `86f980c7` | [3 newer upstream commits after base](https://github.com/KhronosGroup/SPIRV-Headers/compare/2b7475f6d664efbad4d4315c94ecec9640831e5b...86f980c731e62ae4eaf383d320449d71687936bf). Matched build definitions retained. Later grammar/capability changes require relevance/coherence review. |
| MoltenVK cereal dependency | `a56bad8b` | `22a1b369` | [3 newer upstream commits after base](https://github.com/USCiLab/cereal/compare/a56bad8bbb770ee266e930c95d37fff2a5be7fea...22a1b369f39be918ca79206a83c4facd759f9105). Three later commits touch two CI files and tuple.hpp LLVM20 compilation. This comparison does not show a new runtime serialization algorithm. |
| OpenAL Soft | `8d2d2e2e` | `a70d4116` | [147 newer upstream commits after base](https://github.com/kcat/openal-soft/compare/8d2d2e2ed1f51df960e7eb4bb26b64625c873c0d...a70d4116118cdf6bc7ac58fe6ae7a805c7205c50). Preserved source/binary across the graphics campaign; 147 later upstream commits have not all been semantically audited for this port. Not a claim that the old version is intrinsically better. |
| Mesa / Zink / EGL | `45019c28` / 26.3.0-devel | `335d5698` | Later upstream work exists; exact count is **not established** because the official GitLab comparison timed out. Selected later MRs and local changes remain present. Retaining the tested graphics integration is distinct from auditing all later Mesa commits. |

The standalone downloader source input `8263d01` is separate from either engine's downloader gitlink. Its corresponding source archive/hash is recorded in [COMPONENTS](COMPONENTS.md); no fresh exact default-branch distance is asserted here. All inherited submodules and all launcher lock entries remain listed there.

## Why Chobby is not simply “117 commits behind”

The selected Chobby base and current Recoil default branch have **117 default-only commits and 5 selected-branch-only commits**. The branches diverged. Those five are not five new local inventions. The published Chobby lane retains its reviewed `2026.07.04` multiplayer identity; the Lobby lane uses `2026.09.01-24-g01efdf4 master`. Updating one to the other is a compatibility decision involving simulation/peer identity, not a graphics-library refresh. This explains the frozen release contract; it is not a new live-room version survey.

The two base trees also have distinct BARb, CircuitAI, entt and downloader gitlinks; Monocypher is present in the newer Lobby base only. The other 13 base gitlinks match. Those source-tree differences are preserved with explicit lanes; they must not be collapsed into one “latest engine” claim.

## r73 and r75: checked in both published engine source archives

| Source | Direct Lua-number upload (r73) | Typed instance helper (r75) | Relevant functions |
| --- | --- | --- | --- |
| Published candidate.4 Lobby | Present; no numeric staging vector in Upload | Present; no uint32 repacking in the instance overloads | Reference implementation |
| Published candidate.4 Chobby | Present | Present | Upload, UploadImpl, both instance overloads and UploadInstanceData all byte-identical to Lobby |
| Current official Recoil default `01efdf43` | Original intermediate vector remains | Original uint32 repacking remains | Does not contain these two local implementations |

[Function-scoped source/hash evidence](evidence/both-engine-upload-paths.json). A vector used by Download is a separate API requirement and must not be mistaken for an Upload staging array. This establishes source inclusion and exact function identity, not a new runtime invocation count, benchmark or multiplayer result. Earlier r73 work was originally Lobby-only; the current published source comparison now verifies both lanes.

## Dependencies intentionally ahead of the selected official launcher

| Package | Official selected source lock | Our source lock | Why retained |
| --- | --- | --- | --- |
| electron | 37.3.1 | 44.7.2 | Previously updated locally and retained during official launcher integration, rather than downgraded. |
| axios | 1.13.5 | 1.20.0 | Previously updated locally and retained during official launcher integration, rather than downgraded. |
| dompurify | 3.2.6 | 3.4.16 | Previously updated locally and retained during official launcher integration, rather than downgraded. |
| ws | 8.18.3 | 8.21.0 | Previously updated locally and retained during official launcher integration, rather than downgraded. |
| fast-xml-parser | 5.3.6 | 5.7.0 | Previously updated locally and retained during official launcher integration, rather than downgraded. |

These are **actual locked versions** against official launcher `e2c45c8f`, not a comparison of version ranges or a claim to have the newest npm releases. fast-xml-parser is a nested override under `@extractus/feed-extractor`. [Exact package comparison](evidence/launcher-package-selection.json). Version numbers alone do not establish compatibility, safety or performance.

## Later fixes already selected beyond older bases

| Component | Selected beyond-base work | What the older base number hides |
| --- | --- | --- |
| MoltenVK | #2820 initial/follow-up, #2822, #2855, #2861, local command-backend/lifetime/resource preparation changes | The original52aa21f5 pin does not describe the whole patched implementation. #2861 content is already selected even though its later upstream merge object is different. |
| Mesa | !43541, !44707, !38708, !43440, !44811, !44915, adapted !45035 and narrow07c356d5, plus local range/order/display work | The source is not vanilla45019c28. Some selected proposals are still unmerged or later changed upstream. |
| Vulkan Loader | Selected #2050 enumeration retry correction | The originalb82e310e pin does not mean the known enumeration-loop fix is absent. Later related merge changes still need separate comparison. |
| SPIRV-Cross | Selected #2687 alias correction | The originalaa217aeb base has an additional retained local integration, while a different later main fix is still missing. |
| SDL3 | Local property query/assignment pointer and exactly-once cleanup corrections | Compared with the current official head, these same three source-line corrections remain only in our packaged source. A newer whole SDL version must not discard them. |
| Recoil | r58 lifetime/alignment, r73/r75 and later rendering/platform/numeric compatibility adaptations | The upstream base identity is retained for its lane while local graphics fixes are additional. Local code is not official upstream approval. |

[Exact selected commits and official status](INTEGRATIONS.md). The selected MoltenVK patch count and base distance must not be added into a fabricated “net ahead” number.

## Concrete follow-up priorities, based on this comparison

1. **SPIRV-Cross:** the sole newer main commit changes MSL precise-multiply helpers from positive-zero accumulation to negative-zero accumulation, preserving signed-zero behavior. This is shader-translation correctness, not a CPU simulation change or a demonstrated BAR FPS gain. Preserve #2687 while reviewing it.
2. **Vulkan Loader:** later commits include device creation/destruction callback locking, debug messenger/surface-list locking, settings path parsing, cJSON updates and device-group pNext restoration on failure. The metadata identifies review candidates; equivalent local behavior and actual applicability have not all been checked. Do not label all19 commits irrelevant or all19 fixes missing.
3. **SDL3 / OpenAL:**91 and147 later commits respectively warrant a bounded source review. SDL's175 changed paths include multiple platform/device families; counts alone cannot identify a Mac BAR benefit. Preserve the verified local SDL property corrections.
4. **MoltenVK:**8 later commits include the already-selected pipeline-cache fix, new depth-clip-enable support and contribution/deprecation documentation changes. This does not imply eight missing runtime fixes; extension support and existing local handling need their own review.
5. **Lower immediate runtime priority:** the one Vulkan-Headers change is Windows CI only. The three cereal changes are CI and an LLVM20 tuple-header compilation fix. SPIRV-Tools/Headers changes need their linked-call-path and dependency-pair review before attributing a rendering benefit.

[Commit/file census](evidence/followup-commit-census.json) is metadata, not a semantic audit of all326 later commits in those five repositories. [Small source diffs](evidence/small-followup-diffs.json) cover the Headers/Cross/cereal observations; [SDL properties diff](evidence/sdl-properties-followup.diff) compares the published source with the current official source. No app/library rebuild, installation, game, benchmark or new instrumentation was performed.

## Apparent mismatches caused by publication and historical names

| Item | Actual meaning |
| --- | --- |
| Public source tagcandidate.4 vs newer master | The immutable release tag identifies the frozen app source. Master subsequently contains unpublishedcandidate.5 maintenance and documentation commits. Newer master is not a newer released app. |
| Published app/Homebrew candidate.4 vs installedalpha.3 / workspaceRun95 | Different retained roles/artifacts; preserving the ordinary app was explicitly requested. GitHub documentation publication does not install or promote an app. |
| Prepared candidate.5 | Local CPU/package-qualified maintenance; final release still held for version naming. |
| Working checkout HEAD6a3b vs public documentation/source commits | The dirty working checkout/index was deliberately preserved; public snapshots were committed with an alternate index. HEAD alone is not the complete current source content. |
| Foldersrun91-recoil-src-694e9df7 / run66-mesa-src-20260903 | Historical lane names; current source pins/manifest and binary-source correspondence take precedence. |
| Versions2026.07.04 / 2026.09.01-24… | Engine/peer identities, not a total ordering of all file changes or the last local build date. |

There is a valid compatibility reason for keeping separate engine lanes. That does not excuse stale graphics/dependency review or unclear publication labels. Those are maintenance work to track explicitly, rather than claim every frozen version is an optimal long-term choice.
