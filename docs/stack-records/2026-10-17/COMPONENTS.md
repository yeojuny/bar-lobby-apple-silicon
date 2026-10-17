# Exact components, development versions and dependency inputs

This inventory describes the published candidate.4 source/runtime baseline. Unpublished candidate.5 adds macOS maintenance and does not silently update these graphics pins. Historical Run56/Run92 paths and PR-named directories are not current version declarations.

| Component | Included version / channel | Exact upstream source | Local scope |
| --- | --- | --- | --- |
| Launcher | bar-lobby snapshot | [`e2c45c8fcb5461acb3232539493be15cd0fda7ec`](https://github.com/beyond-all-reason/bar-lobby/commit/e2c45c8fcb5461acb3232539493be15cd0fda7ec) | Local macOS integration; public fork master is a documentation/source publication identity, not the upstream base. |
| Lobby engine | 2026.09.01-24-g01efdf4 master | [`01efdf43121dfd40d105649ef7eb89a8804662d9`](https://github.com/beyond-all-reason/RecoilEngine/commit/01efdf43121dfd40d105649ef7eb89a8804662d9) | Development engine lane; local rendering/platform fixes. |
| Chobby engine | 2026.07.04 | [`de69361239d8c8b1012dba3f5aa3122954ea4da3`](https://github.com/beyond-all-reason/RecoilEngine/commit/de69361239d8c8b1012dba3f5aa3122954ea4da3) | Official multiplayer identity retained; different source lane and local macOS fixes. |
| Mesa / Zink / EGL | 26.3.0-devel | [`45019c28811991cc02f87f0360235b8e4c369155`](https://gitlab.freedesktop.org/mesa/mesa/-/commit/45019c28811991cc02f87f0360235b8e4c369155) | Development snapshot plus selected MR commits and local changes; not a released stable Mesa build. |
| MoltenVK | 1.4.3-derived | [`52aa21f54d7a84c5c441fc26359692b0980b384c`](https://github.com/KhronosGroup/MoltenVK/commit/52aa21f54d7a84c5c441fc26359692b0980b384c) | Pinned main plus retained PR content/local Metal4 backend. Local revision 0e7c41b9 is NOT an upstream commit or official Metal4 release. |
| Vulkan Loader | 1.4.365 | [`b82e310e99c20bfac8dd3123c9e939f81ce54b89`](https://github.com/KhronosGroup/Vulkan-Loader/commit/b82e310e99c20bfac8dd3123c9e939f81ce54b89) | Pinned source plus selected #2050; app-local loader/ICD closure. |
| Vulkan Headers | 1.4.365 | [`c46850864f4661461b0f6cb9922c058ffea4915e`](https://github.com/KhronosGroup/Vulkan-Headers/commit/c46850864f4661461b0f6cb9922c058ffea4915e) | Build headers; a header version does not prove runtime feature support. |
| SDL3 | 3.5.0 development snapshot | [`4a17e772ea9a4ff77dd10fa6ea6f45fc6731eb01`](https://github.com/libsdl-org/SDL/commit/4a17e772ea9a4ff77dd10fa6ea6f45fc6731eb01) | Local property failure-path correction. Active backend is SDL3, not SDL2 or SDL_GPU. |
| SPIRV-Cross | pinned main snapshot | [`aa217aeb6c9f0ace7a0ab233b28807edf45eb165`](https://github.com/KhronosGroup/SPIRV-Cross/commit/aa217aeb6c9f0ace7a0ab233b28807edf45eb165) | Plus selected #2687; shader translation, not a separate renderer. |
| SPIRV-Tools | pinned source snapshot | [`ba9a9e32160e2500ce1e48cc563a8fedaf596e6e`](https://github.com/KhronosGroup/SPIRV-Tools/commit/ba9a9e32160e2500ce1e48cc563a8fedaf596e6e) | Dependency pin; no extra optimizer PR implied by investigation records. |
| SPIRV-Headers | pinned source snapshot | [`2b7475f6d664efbad4d4315c94ecec9640831e5b`](https://github.com/KhronosGroup/SPIRV-Headers/commit/2b7475f6d664efbad4d4315c94ecec9640831e5b) | Matched SPIR-V build definitions. |
| MoltenVK cereal dependency | pinned source snapshot | [`a56bad8bbb770ee266e930c95d37fff2a5be7fea`](https://github.com/USCiLab/cereal/commit/a56bad8bbb770ee266e930c95d37fff2a5be7fea) | Separate from the Recoil engine cereal submodule; #758 was not adopted. |
| OpenAL Soft | 1.25.2 source snapshot | [`8d2d2e2ed1f51df960e7eb4bb26b64625c873c0d`](https://github.com/kcat/openal-soft/commit/8d2d2e2ed1f51df960e7eb4bb26b64625c873c0d) | Normal macOS audio backend in manual/product launch. Validation null-backend settings are not product defaults. |
| Bundled pr-downloader source | Chobby 8263d01 source input | [`8263d01`](https://github.com/beyond-all-reason/pr-downloader) | Abbreviated source identifier from the complete source companion archive name; not substituted for either engine gitlink. Archive hash is authoritative. |

## Launcher dependencies and build tooling

Electron **44.7.2** and Node **22.18.0** build tooling are retained, alongside axios **1.20.0**, DOMPurify **3.4.16**, ws **8.21.0**, fast-xml-parser override **5.7.0**, and the newer official content/Tachyon/replay dependencies. Version ranges in package.json are not the installed versions. The [complete lockfile entry catalog](evidence/launcher-lock-packages.json) contains all **1,149** package entries, preserving resolved versions, integrity and dev/optional flags. It includes build-time packages and is not a count of shipped runtime modules. The full package-lock.json remains in the source repository.

## Every upstream engine submodule pin

The following table includes all 18 Lobby and 17 Chobby base gitlinks, read from their exact upstream trees. It records upstream base pins, **not a claim of byte-identical unmodified packaged sources**: local AI linking/JsonCpp isolation, numeric/SHIELD changes and other adaptations are documented separately. The standalone packaged downloader also has its own source input. [Machine-readable complete trees](evidence/engine-base-submodules.json).

| Submodule | Lobby base | Chobby base |
| --- | --- | --- |
| `AI/Skirmish/BARb` | `f4a6ca3ae096631894e194cfa9b4e8e53f4fb78c` | `e6b33037dfbe81f2b0eb289f884ed90a1718eec0` |
| `AI/Skirmish/CircuitAI` | `e51ba92b7fff269aff8bb1d706217862f51d7bc2` | `edc74149c281e2140f28c091ed74310c11611cc7` |
| `rts/lib/RmlUi` | `2230d1a6e8e0848ed87a5761e2a5160b2a175ba4` | `2230d1a6e8e0848ed87a5761e2a5160b2a175ba4` |
| `rts/lib/cereal` | `d1fcec807b372f04e4c1041b3058e11c12853e6e` | `d1fcec807b372f04e4c1041b3058e11c12853e6e` |
| `rts/lib/entt` | `b4e58bdd364ad72246c123a0c28538eab3252672` | `e4ccb878f47245a319704912435d3c89f34ad6be` |
| `rts/lib/fastgltf` | `eebda658317cd907d6cdf9c9ed7e40b96e8453dd` | `eebda658317cd907d6cdf9c9ed7e40b96e8453dd` |
| `rts/lib/fmt` | `407c905e45ad75fc29bf0f9bb7c5c2fd3475976f` | `407c905e45ad75fc29bf0f9bb7c5c2fd3475976f` |
| `rts/lib/gflags` | `33bb3461e10864b5406353d3a1fb7ff34c2314b8` | `33bb3461e10864b5406353d3a1fb7ff34c2314b8` |
| `rts/lib/lunasvg` | `f8aabfb444bb37f69df7290790f57e4a27730a93` | `f8aabfb444bb37f69df7290790f57e4a27730a93` |
| `rts/lib/mimalloc` | `7b7fca4b7013d77e356d96e055fec309cb3cbbd6` | `7b7fca4b7013d77e356d96e055fec309cb3cbbd6` |
| `rts/lib/monocypher` | `1830c06d5910fba451cec329c8f30f348fc607db` | `not present` |
| `rts/lib/nowide` | `de3bb558ebe3dd6d22a03b4beb92fbe05470ca1c` | `de3bb558ebe3dd6d22a03b4beb92fbe05470ca1c` |
| `rts/lib/simdjson` | `0c0ce1bd48baa0677dc7c0945ea7cd1e8b52b297` | `0c0ce1bd48baa0677dc7c0945ea7cd1e8b52b297` |
| `rts/lib/sse2neon` | `8721e9799e0d01b80ba8e8e34636cb49997560c2` | `8721e9799e0d01b80ba8e8e34636cb49997560c2` |
| `rts/lib/streflop` | `570f86fb616a20179914aa7fc9645e683a3f5b4d` | `570f86fb616a20179914aa7fc9645e683a3f5b4d` |
| `rts/lib/tracy` | `5d542dc09f3d9378d005092a4ad446bd405f819a` | `5d542dc09f3d9378d005092a4ad446bd405f819a` |
| `tools/pr-downloader` | `185cfba7fda4dc683acec8b2ecbd15838d3022f5` | `09a1f37c77a014f24c3116ac7b7d2e318d0ce0de` |
| `tools/unitsync/python` | `8dfe0bcb867150c4d83e6f691e44dc7a55fda21c` | `8dfe0bcb867150c4d83e6f691e44dc7a55fda21c` |

## Native libraries, source recipes and release source archives

The matching source companion includes eleven archives. The [complete source manifest](evidence/source-companion-manifest.json) records every archive member inventory file and source/build-support artifact hash. Download the [published candidate.4 corresponding sources](https://github.com/yeojuny/bar-lobby-apple-silicon/releases/download/v0.17.0-candidate.4/BAR-0.17.0-candidate.4-sources.tar.gz), rather than GitHub's launcher-only automatic source ZIP.

| Archive | Entries | SHA-256 |
| --- | ---: | --- |
| `archives/mesa-zink-68cc-input.tar.gz` | 12909 | `9ca8ac89e3e4e23c23cb50d7b009a8e8cc2e27b06f7154e3ef717b38261fe3fd` |
| `archives/vulkan-loader-68cc-input.tar.gz` | 292 | `68269a49344a1b2fd318f56828c0ca7104ef08ea3144e4fe97ac93061e8c7420` |
| `archives/vulkan-headers-c4685086.tar.gz` | 89 | `9ac18f85038eec76851fe05d3e31828107bb7d4c362ab09dcec850c77747e4a7` |
| `archives/sdl3-4a17e772.tar.gz` | 2392 | `a0d0c257c748660936e2b19c561e338ba8198982c44b9e9dfbaf4312c515197f` |
| `archives/pr-downloader-chobby-8263d01.tar.gz` | 245 | `c8b29ef73b6c143b7779022bcb1516bfa27f0cea381d494a5b8774750564be10` |
| `archives/openal-soft-8d2d2e2e-populated.tar.gz` | 465 | `e661285a9f1365758eab1499db4a4ce779f73c63f978ac5648d2c35d53a5caef` |
| `archives/moltenvk-68cc-functional-diagnostics-off.tar.gz` | 7246 | `7ce7b6fee52a78cedae5ec55bb8e8076763393cefcff0b5656d0d49d8ce4c56c` |
| `archives/launcher-overlay-and-profile-inputs.tar.gz` | 105 | `67ba4ac6fdf949a729ad7320eeb2fd2ba589259df3cf1b2477d4a7acbc935e82` |
| `archives/bar-launcher-0.17.0-candidate.4.tar.gz` | 826 | `0f65891b89548f5952fc3bd424084cebb8799ceb10d00d09c8d3ede9c7d2e7c5` |
| `archives/recoil-lobby-01efdf4-candidate.4.tar.gz` | 9220 | `57288b4efda03924c21a16901c175fd27a53d84a1e66a40eb7fabcaaac8dad66` |
| `archives/recoil-chobby-2026.07.04-candidate.4.tar.gz` | 8936 | `6294bd446b3e70338f40d34a15bc63cf4882cceb2e46088856447169828683d4` |

The 16 native source/build recipe records below are also retained in that companion. Their names and hashes are listed in [native-recipe-index.json](evidence/native-recipe-index.json). A build recipe can describe an input rather than a runtime library; entries marked version-reference-only must not be presented as complete corresponding sources.

| Recipe/version | Role |
| --- | --- |
| `dependency-recipes/devil-1.8.0_6.rb` | corresponding-build-recipe |
| `dependency-recipes/fontconfig-2.18.3.rb` | corresponding-build-recipe |
| `dependency-recipes/gcc-16.2.0.rb` | corresponding-build-recipe |
| `dependency-recipes/gettext-1.0.rb` | corresponding-build-recipe |
| `dependency-recipes/jasper-4.2.9.rb` | corresponding-build-recipe |
| `dependency-recipes/jpeg-turbo-3.2.0.rb` | corresponding-build-recipe |
| `dependency-recipes/libogg-1.3.6.rb` | corresponding-build-recipe |
| `dependency-recipes/libtiff-4.7.2.rb` | corresponding-build-recipe |
| `dependency-recipes/libvorbis-1.3.7.rb` | corresponding-build-recipe |
| `dependency-recipes/little-cms2-2.19.1.rb` | corresponding-build-recipe |
| `dependency-recipes/minizip-1.3.2_1.rb` | corresponding-build-recipe |
| `dependency-recipes/p7zip-16.02_3.rb` | corresponding-build-recipe |
| `dependency-recipes/version-reference-only/freetype-2.15.0.rb` | version-reference-only |
| `dependency-recipes/version-reference-only/libpng-1.6.59.rb` | version-reference-only |
| `dependency-recipes/version-reference-only/xz-5.8.4.rb` | version-reference-only |
| `dependency-recipes/zstd-1.5.7_1.rb` | corresponding-build-recipe |

[Native build cache/command/flag evidence](evidence/native-build-inputs.json) retains the recorded compiler and configuration provenance; [effective MoltenVK build record](evidence/mvk-effective-build.json) pins the local revision, arm64 Release build, deployment target **27.0**, Metal4 foundation/private-API options and custom diagnostics OFF. This is the actual recorded target, not a compatibility promise for older macOS versions.

The [complete notices archive](https://github.com/yeojuny/bar-lobby-apple-silicon/releases/download/v0.17.0-candidate.4/BAR-0.17.0-candidate.4-notices.tar.gz) retains component copyrights/licenses. The recipe catalog includes historical build provenance and does not prove an independent clean-machine rebuild.
