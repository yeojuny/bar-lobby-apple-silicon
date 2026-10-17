# Runtime stack and integrated patches — candidate.5

The packaged route is **ARM64 Recoil OpenGL → Mesa/Zink → Vulkan Loader → MoltenVK → Metal**. Electron provides the launcher. SDL3 provides native macOS window/input/event integration through Cocoa and the existing EGL/CAMetalLayer bridge. SDL3 does not translate OpenGL to Metal. This runtime does not require an X11 server or XQuartz installation; X11 is the display system and XQuartz its macOS implementation. SDL2 is not the active window backend, even though historical/unused targets or compatibility names may still mention it. This app is separate from any native Metal4 renderer project.

## Exact shipped source baseline

Development version labels describe pinned source snapshots, not a claim to package today's upstream stable release. All corresponding source archives accompany this release; unchanged graphics/AI libraries retain their candidate.4 hashes. The build-context manifest and native correspondence take precedence over historical folder labels and old notice annotations.

| Component | Included version / exact source |
| --- | --- |
| Launcher | bar-lobby `e2c45c8fcb5461acb3232539493be15cd0fda7ec` with this fork's macOS integration; Electron44.7.2, Node22.18.0 build tooling |
| Lobby engine | Recoil `01efdf43121dfd40d105649ef7eb89a8804662d9` with local integration; exact sync `2026.09.01-24-g01efdf4 master` |
| Chobby engine | Official `2026.07.04` identity; source base `de69361239d8c8b1012dba3f5aa3122954ea4da3` with local macOS fixes; never aliased to the newer Lobby engine |
| Mesa / Zink / EGL | `26.3.0-devel`, base `45019c28811991cc02f87f0360235b8e4c369155`, plus selected patches and local correctness fixes |
| MoltenVK | `1.4.3` source base `52aa21f54d7a84c5c441fc26359692b0980b384c`, plus retained patches and the local experimental Metal4 path; shipped build revision `0e7c41b9` is a local build identity, not an upstream Git commit |
| Vulkan Loader | `1.4.365` source base `b82e310e99c20bfac8dd3123c9e939f81ce54b89` plus selected fixes |
| Vulkan Headers | `1.4.365`, `c46850864f4661461b0f6cb9922c058ffea4915e` |
| SDL3 | Header version `3.5.0` development snapshot `4a17e772ea9a4ff77dd10fa6ea6f45fc6731eb01`, plus the reviewed local property/error-path correction |
| SPIRV-Cross | `aa217aeb6c9f0ace7a0ab233b28807edf45eb165` plus pinned #2687 |
| SPIRV-Tools / Headers | `ba9a9e32160e2500ce1e48cc563a8fedaf596e6e` / `2b7475f6d664efbad4d4315c94ecec9640831e5b` |
| Audio | OpenAL Soft1.25.2, source `8d2d2e2ed1f51df960e7eb4bb26b64625c873c0d`, using the normal macOS audio backend |

## Upstream changes already present in the chosen MoltenVK base

GitHub merge metadata and ancestry to pinned `52aa21f5` were rechecked on2026-10-17. These are inherited upstream work, not newly authored by this fork and not newly added in candidate.5:

- [#2746](https://github.com/KhronosGroup/MoltenVK/pull/2746): SPIRV-Cross dependency update.
- [#2747](https://github.com/KhronosGroup/MoltenVK/pull/2747): cached Metal texture invalidation fix.
- [#2775](https://github.com/KhronosGroup/MoltenVK/pull/2775): indirect draw-count support.
- [#2778](https://github.com/KhronosGroup/MoltenVK/pull/2778): dependency library update.

The retained runtime directory name `moltenvk-pr2746` is historical. It is not the MoltenVK version or a complete integration ledger.

## Selected integrations beyond the pinned bases

“Integrated locally” is distinct from upstream merge approval. We retain reviewed commit content and local adaptations, not floating PR heads. GitHub status below was checked on2026-10-17; later upstream changes do not silently enter this app. Mesa MR rows record selected work and exact integrated commits without claiming their current upstream approval status.

| Included work | Purpose and inclusion boundary |
| --- | --- |
| MoltenVK [#2822](https://github.com/KhronosGroup/MoltenVK/pull/2822) | Restore argument-buffer bindings after helper encoders; retained reviewed `fd8ea9dbb1963af3642d912bad651f018434c922`. Upstream still open at this check. |
| MoltenVK [#2820](https://github.com/KhronosGroup/MoltenVK/pull/2820) | Tessellation patch counts/indexed-indirect layout and temporary-buffer fixes; reviewed `3dbe1bca0516c87076fa0ff5a9ee5b9a73f965c0` plus `f0fff496170ec265a8be8f96a7b80e1be5a0ba0b`. Upstream still open. |
| MoltenVK [#2861](https://github.com/KhronosGroup/MoltenVK/pull/2861) | Complete matching of dynamic-buffer descriptors/discrete sets in pipeline cache; integrated `cbe497918d1d24772de4753eaa199be74fa62d07`. Upstream merged after our pinned base. |
| MoltenVK [#2855](https://github.com/KhronosGroup/MoltenVK/pull/2855) | Thread-safe lazy global configuration publication; integrated `6ff9f7bbd89f53234fd4e3bb26c5ef4d4be134b3`. Upstream still open. |
| SPIRV-Cross [#2687](https://github.com/KhronosGroup/SPIRV-Cross/pull/2687) | Correct MSL integer-to-pointer alias handling; integrated `38abe362c57311a77808b7ec4d1d0d9ceb8d9370`. Upstream still open; actual built translator outputs were checked historically. |
| Vulkan Loader [#2050](https://github.com/KhronosGroup/Vulkan-Loader/pull/2050) | Avoid physical-device-group enumeration/path retry loops; integrated `f770ea2ec2d4777a63bdf4017d910ce613f11afd`. Upstream now merged; original later populate-error behavior is preserved. |
| Mesa [!43541](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/43541) | Retained valid-range copy correction, alongside local range tracking. |
| Mesa [!44707](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44707) | Draw preparation/index-bound ordering; `2bacf9c87dcfa0a5cf10adbf371b704db449ae3a`. |
| Mesa [!38708](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/38708) | ARM64 NEON RGBA/BGRA conversion; `f48aff4943b17c175efbb293f4dadd2d62eab7f9`. CPU conversion savings do not establish game FPS gains. |
| Mesa [!43440](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/43440) | Avoid unnecessary NIR matcher bookkeeping; `22c0155e95e22f26d1c9d4c70d2c430ac3c084b4`. |
| Mesa [!44811](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44811) / [!44915](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44915) | Texture CSE component/type hash and equality correctness; `ee29d6c94cdb461a1cd9b62fe6ac74e14810b5bd` plus `9ce7a2ef35ae1ab06e024860a0f247962ab11b95`. |
| Mesa [!45035](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/45035), adapted | Zink ordered/unordered synchronization tracking, based on `b448ad053f2ce190a5b6b2d27b30dcbf3d45ec7d`; an additional local guard preserves ordered-access dependencies. This is not the unmodified MR. |
| Mesa [07c356d5](https://gitlab.freedesktop.org/mesa/mesa/-/commit/07c356d5debdc3c84cfde4f5f1cc045329f26429) | Narrow old-swapchain append-pointer fix; the whole !44865 proposal was not adopted with it. |

## Local work and acceptance boundaries

Local changes also include equivalent NoGS/CUS presentation, GL capability checks separate from API-version reporting, VBO/VAO validation and GPU lifetime ownership, buffer-copy byte-range tracking, dynamic triangle-fan handling, shader-library owning-copy protection, target-screen fullscreen/safe-area handling, AI JsonCpp symbol isolation and configured Apple-linker fixes. The experimental Metal4 path has additional command recording/replay/resource and timestamp-boundary changes; it is not a guarantee of higher FPS or lower power. Metal3 remains the default. CPU submit wait and custom cost collection remain OFF; custom MoltenVK diagnostics are compiled out while required functional accounting remains.

Candidate.5 adds the hardware-string, Options recognition, diagnostic-output and owned-default maintenance described in the main release notes. It does not rebuild the graphics stack or update these upstream pins. Historical measurements are whole-stack observations, not per-PR benefit estimates. Source/CPU checks do not prove all GPU behavior, full MP/replay synchronization, audible sound, endurance or other-Mac acceptance. Candidate.5 has no fresh app/menu/game run. Read the current source companion manifest/build context for complete file-level correspondence; this is a curated integration ledger, not every commit inherited from upstream.
