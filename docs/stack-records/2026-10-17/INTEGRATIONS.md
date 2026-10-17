# External PR/MR integration ledger

Checked on **2026-10-17** against official GitHub/GitLab API responses. The exact included commit column is separate from the current upstream merge/head. Base ancestry is recorded in [base-pr-ancestry.json](evidence/base-pr-ancestry.json); current states in [GitHub](evidence/github-pr-status.json) and [Mesa](evidence/mesa-mr-status.json). [Complete machine-readable ledger](evidence/integrations.json).

“Merged” means the official project merged that PR/MR, not that it approved our port or every subsequent local adaptation. An open or closed-unmerged proposal can still be integrated locally. This ledger does not infer an exact-head review approval from author reputation or merge status. Reviews of the selected open PRs are recorded separately below.

## MoltenVK

| External contribution / purpose | Inclusion and exact commit(s) | Official status | Local evidence / limits |
| --- | --- | --- | --- |
| [PR #2746](https://github.com/KhronosGroup/MoltenVK/pull/2746): Update SPIRV-Cross to latest revision. | inherited in pinned base 52aa21f5; `9d5d89a2a1954ae8fe73fd2a97a4f3d862319eee` | merged 2026-06-02 | Base ancestry verified against exact merge commit; inherited upstream work, no per-PR BAR benchmark.  |
| [PR #2747](https://github.com/KhronosGroup/MoltenVK/pull/2747): Fix invalidation of cached metal textures | inherited in pinned base 52aa21f5; `7d724020575219914a28ed9fb4011ba5303fb7b5` | merged 2026-07-19 | Base ancestry verified against exact merge commit; inherited upstream work, no per-PR BAR benchmark.  |
| [PR #2775](https://github.com/KhronosGroup/MoltenVK/pull/2775): Support draw indirect count | inherited in pinned base 52aa21f5; `92a43810bfebb1b8ebcfa7cb715cfd32ee26e7c8` | merged 2026-07-24 | Base ancestry verified against exact merge commit; inherited upstream work, no per-PR BAR benchmark.  |
| [PR #2778](https://github.com/KhronosGroup/MoltenVK/pull/2778): Update dependency libraries. | inherited in pinned base 52aa21f5; `98f35743467488e380317feec591f4d33d652f5f` | merged 2026-07-19 | Base ancestry verified against exact merge commit; inherited upstream work, no per-PR BAR benchmark.  |
| [PR #2819](https://github.com/KhronosGroup/MoltenVK/pull/2819): Preserve execution dependencies across Metal encoders | inherited in pinned base 52aa21f5; `a63d486387651b4e077174995ffc49125db22636` | merged 2026-09-24 | Base ancestry verified against exact merge commit; inherited upstream work, no per-PR BAR benchmark.  |
| [PR #2823](https://github.com/KhronosGroup/MoltenVK/pull/2823): Fix Metal fence ordering for external subpass dependencies | inherited in pinned base 52aa21f5; `2bc63941b1606c4c0e5150dfbba4f1f09a39a52e` | merged 2026-09-23 | Base ancestry verified against exact merge commit; inherited upstream work, no per-PR BAR benchmark.  |
| [PR #2829](https://github.com/KhronosGroup/MoltenVK/pull/2829): Fix VkDeviceMemory imported from a MTLTexture. | inherited in pinned base 52aa21f5; `f0571d7d6ebdad9f31abcdfebb0af50b83d2dae2` | merged 2026-09-23 | Base ancestry verified against exact merge commit; inherited upstream work, no per-PR BAR benchmark.  |
| [PR #2839](https://github.com/KhronosGroup/MoltenVK/pull/2839): Retain query pools until Metal command buffer completion | inherited in pinned base 52aa21f5; `50b3cbf373f4165947e0e315c0c37cfb658dfd51` | merged 2026-09-26 | Base ancestry verified against exact merge commit; inherited upstream work, no per-PR BAR benchmark.  |
| [PR #2850](https://github.com/KhronosGroup/MoltenVK/pull/2850): Add new SPIRV-Cross options to serialization | inherited in pinned base 52aa21f5; `52aa21f54d7a84c5c441fc26359692b0980b384c` | merged 2026-09-30 | Base ancestry verified against exact merge commit; inherited upstream work, no per-PR BAR benchmark.  |
| [PR #2820](https://github.com/KhronosGroup/MoltenVK/pull/2820): Tessellation patch counts, indexed-indirect layout and temporary-buffer handling | selected initial + follow-up; `3dbe1bca0516c87076fa0ff5a9ee5b9a73f965c0`<br>`f0fff496170ec265a8be8f96a7b80e1be5a0ba0b` | open | Historical source/compiler/package checks; exact retained patch hashes in Run95 intake. Frozen selected commits, not the current floating PR head. |
| [PR #2822](https://github.com/KhronosGroup/MoltenVK/pull/2822): Restore argument-buffer bindings after helper encoders | selected exact commit; `fd8ea9dbb1963af3642d912bad651f018434c922` | open | Retained source and later packaged native graphics checks; not a guarantee of every helper/binding combination.  |
| [PR #2855](https://github.com/KhronosGroup/MoltenVK/pull/2855): Thread-safe lazy global configuration publication | selected exact commit; `6ff9f7bbd89f53234fd4e3bb26c5ef4d4be134b3` | open | Existing runtime-correctness integration/source and CPU checks; no FPS claim.  |
| [PR #2861](https://github.com/KhronosGroup/MoltenVK/pull/2861): Complete pipeline cache matching for dynamic-buffer descriptors and discrete descriptor sets | selected exact commit beyond base; `cbe497918d1d24772de4753eaa199be74fa62d07` | merged 2026-10-08 | Existing runtime-correctness integration and cache-match checks. Upstream later merged a different merge object; that does not change the frozen included commit. |

## SPIRV-Cross

| External contribution / purpose | Inclusion and exact commit(s) | Official status | Local evidence / limits |
| --- | --- | --- | --- |
| [PR #2678](https://github.com/KhronosGroup/SPIRV-Cross/pull/2678): MSL: Fix layout of struct arrays whose ArrayStride exceeds the packed struct size | inherited in aa217aeb; `94d59e564363a08b7d053692e9499d0f909c106b` | merged 2026-09-16 | Base ancestry checked; inherited shader-translation fixes.  |
| [PR #2681](https://github.com/KhronosGroup/SPIRV-Cross/pull/2681): MSL: Fix invalid pointer constructor when unrolling row-major column … | inherited in aa217aeb; `71055a8144bef210e43cc6519900079629ca7f89` | merged 2026-09-17 | Base ancestry checked; inherited shader-translation fixes.  |
| [PR #2687](https://github.com/KhronosGroup/SPIRV-Cross/pull/2687): MSL integer-to-pointer aliasing correctness | selected exact commit; `38abe362c57311a77808b7ec4d1d0d9ceb8d9370` | open | Historical two actual translator outputs matched expected MSL bytes; independent offline Metal compilation was not performed in that check.  |

## Vulkan Loader

| External contribution / purpose | Inclusion and exact commit(s) | Official status | Local evidence / limits |
| --- | --- | --- | --- |
| [PR #2050](https://github.com/KhronosGroup/Vulkan-Loader/pull/2050): Avoid enumeration/path retry infinite loops | selected exact commit; `f770ea2ec2d4777a63bdf4017d910ce613f11afd` | merged 2026-10-10 | Existing source/error-path tests and packaged loader closure. Upstream subsequently merged it; the recorded source remains the selected commit. |

## Mesa / Zink

| External contribution / purpose | Inclusion and exact commit(s) | Official status | Local evidence / limits |
| --- | --- | --- | --- |
| [MR !43541](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/43541): Preserve prior updates to source valid_buffer_range | selected, with later local range/copy corrections; `b8e600c4ac688929315662c5e9d04de54add8066` | open | Exact retained patch plus later local byte-region/hazard checks.  |
| [MR !44707](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44707): Draw preparation ordering and subsequent index bounds | selected earlier reviewed head; `2bacf9c87dcfa0a5cf10adbf371b704db449ae3a` | merged 2026-10-11 | Historical 32 index-predicate and 6 caller-ordering CPU checks. Upstream merged on 2026-10-11; current final MR head differs from our included 2bacf9c8. No claim of byte-identical final MR integration. |
| [MR !38708](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/38708): AArch64 NEON RGBA/BGRA conversion | selected exact head; `f48aff4943b17c175efbb293f4dadd2d62eab7f9` | open | Historical 24,960 actual-function CPU comparisons; author microbenchmark is not BAR FPS.  |
| [MR !43440](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/43440): Avoid unnecessary NIR algebraic matcher bookkeeping | selected exact head; `22c0155e95e22f26d1c9d4c70d2c430ac3c084b4` | closed, not merged | Historical 4,352 variable-branch cases and a negative case; not the full NIR suite. Current API state is closed with no merged_at. Closed is not merged; local inclusion is not official approval. |
| [MR !44811](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44811): Texture-instruction CSE result definition matching | selected exact commit; `ee29d6c94cdb461a1cd9b62fe6ac74e14810b5bd` | merged 2026-10-05 | Paired with !44915 in retained runtime correctness checks.  |
| [MR !44915](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44915): Texture CSE destination type rather than bit-size matching | selected exact commit; `9ce7a2ef35ae1ab06e024860a0f247962ab11b95` | merged 2026-10-07 | Paired with !44811; no BAR shader miscompile occurrence claim.  |
| [MR !45035](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/45035): Ordered/unordered Zink resource synchronization tracking | adapted selected commit + local guard; `b448ad053f2ce190a5b6b2d27b30dcbf3d45ec7d` | merged 2026-10-09 | Additional local ordered-dependency guard retained; not an unmodified MR transplant.  |
| [MR !44358](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44358): Place buffer-view cache key first | historically recorded as inherited base work; `9c95a742b585d59360e391edcef88e52fb619f9e` | merged 2026-09-10 | Inherited source attribution; no separate performance claim.  |
| [MR !44474](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44474): Replace blend/vertex-element state hashes with IDs | historically recorded as inherited base work; `f30cb8839b2fcd0903b74c659aa7d9d3d0c5045d` | merged 2026-09-16 | Preserved with local dynamic-stride handling; inherited attribution.  |

## Recoil inherited foundation and simulation changes

| External contribution / purpose | Inclusion and exact commit(s) | Official status | Local evidence / limits |
| --- | --- | --- | --- |
| [PR #2819](https://github.com/beyond-all-reason/RecoilEngine/pull/2819): Add ARM64 platform support with deterministic floating-point | inherited in lobby, chobby base; `5ed2647d2d80775c45742ab87a019a1b6e6e3983` | merged 2026-03-22 | Exact official merge/base ancestry checked. Local numeric compatibility checks remain distinct from live cross-platform acceptance. No claim that an absent base merge is automatically an absent/equivalent local correction in the other lane. |
| [PR #2886](https://github.com/beyond-all-reason/RecoilEngine/pull/2886): ARM64 platform support rework | inherited in lobby, chobby base; `74e145c7079c1e3a4d9fd5e17e3c8358325168bd` | merged 2026-03-22 | Exact official merge/base ancestry checked. Local numeric compatibility checks remain distinct from live cross-platform acceptance. No claim that an absent base merge is automatically an absent/equivalent local correction in the other lane. |
| [PR #3075](https://github.com/beyond-all-reason/RecoilEngine/pull/3075): Sim/COB: avoid UB in float-to-short angle casts (fixes arm64/x86 desync) | inherited in lobby, chobby base; `7104ab1f76d9fe6823016dcb5561e179174e39a2` | merged 2026-07-28 | Exact official merge/base ancestry checked. Local numeric compatibility checks remain distinct from live cross-platform acceptance. No claim that an absent base merge is automatically an absent/equivalent local correction in the other lane. |
| [PR #3070](https://github.com/beyond-all-reason/RecoilEngine/pull/3070): Fix demotool build and truncated sync checksum dump | inherited in lobby, chobby base; `f898efc6c31b3871cc8f60ed2c567a5de41db696` | merged 2026-06-29 | Exact official merge/base ancestry checked. Local numeric compatibility checks remain distinct from live cross-platform acceptance. No claim that an absent base merge is automatically an absent/equivalent local correction in the other lane. |
| [PR #3342](https://github.com/beyond-all-reason/RecoilEngine/pull/3342): Sim: avoid UB in float-to-short heading casts | inherited in lobby base; `da974d379b613f024859292da0e000d9d2a4280c` | merged 2026-09-11 | Exact official merge/base ancestry checked. Local numeric compatibility checks remain distinct from live cross-platform acceptance. No claim that an absent base merge is automatically an absent/equivalent local correction in the other lane. |
| [PR #3132](https://github.com/beyond-all-reason/RecoilEngine/pull/3132): fix issue where ships could get incorrect pathmap blocking zones  | inherited in lobby base; `a0d4241b10e1e2f9c250033d404ec6545fd05923` | merged 2026-09-10 | Exact official merge/base ancestry checked. Local numeric compatibility checks remain distinct from live cross-platform acceptance. No claim that an absent base merge is automatically an absent/equivalent local correction in the other lane. |

## Narrow source commit and donor adaptation

- Mesa [`07c356d5debdc3c84cfde4f5f1cc045329f26429`](https://gitlab.freedesktop.org/mesa/mesa/-/commit/07c356d5debdc3c84cfde4f5f1cc045329f26429): old-swapchain append-pointer advancement. Only this narrow change was selected; not the whole !44865 proposal.
- benbreen [`a49a8ecc5265c4dd3f8d0016d90b32e81e22c73b`](https://github.com/benbreen/RecoilEngine-AppleSilicon/tree/a49a8ecc5265c4dd3f8d0016d90b32e81e22c73b): source for r57 fence wait/model ring/worker QoS ideas and restart investigation. Our narrower restart proof, r58 lifetime/alignment fixes and later r73/r75 work are distinguished in the [origin record](../../engine-patches/2026-10-17/ORIGIN-AND-PERFORMANCE.md).

## Material status differences from older notes

- Mesa **!44707** is now merged, but our frozen included commit is the earlier reviewed `2bacf9c8…`; current final head is `37bf953a…`. The app did not update itself when the MR merged.
- Mesa **!43440** is now **closed without a merge timestamp**. Its local inclusion and historical CPU checks must not be described as official approval or upstream merge.
- MoltenVK **#2861** and Loader **#2050** were selected separately beyond their pinned bases and subsequently merged upstream; inclusion/merge object hashes remain distinct.
- The MoltenVK proposals marked inherited above supersede their old standalone backport records; they are not counted twice.
- Recoil **#3342 / #3132** are inherited in the newer Lobby base but not in the older official Chobby base. This is base ancestry, not a claim about every equivalent local correction. Keep engine identity and local numeric policy separate.

## Completeness and limits

The full [historical Run95 intake](evidence/historical-run95-intake.json) includes every retained patch filename/hash and held list at that stage. Later local R4/diagnostic-removal changes are described in [LOCAL-CHANGES](LOCAL-CHANGES.md), rather than invented PR numbers. Current source archive manifests and component base pins retain complete upstream sources; this table does not claim to list every PR ever merged into SDL, Recoil, Mesa or their dependencies. That unabridged history is identified by each immutable base and is not relabeled as local work.

No new benchmark, GPU/game run, app rebuild or upstream submission was performed for this documentation. Local validation of r73/r75 extraction is separate from historical integrated stack checks.

## Exact selected-commit approval observations

The [official review API responses](evidence/selected-open-pr-reviews.json) were checked on 2026-10-17 for the selected open MoltenVK #2820/#2822/#2855 and SPIRV-Cross #2687 proposals. No `APPROVED` review for the exact frozen integrated commit IDs was returned. That is a literal review observation, not a conclusion that no maintainer ever reviewed related code. These selected commits were integrated on the basis of local review/authorization and scoped checks; they are not advertised as officially approved or merged. No external approval is claimed for the r73/r75 extraction.
