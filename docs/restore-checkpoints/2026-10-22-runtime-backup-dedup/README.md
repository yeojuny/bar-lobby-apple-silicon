# Runtime backup duplicate selection — 2026-10-22

The user approved compact change history in place of repeated complete backups, after itemized disclosure and remote verification.

This selection removes 100 identical runtime-backup copies only. All 30 byte variants remain locally and are included as exact Git payloads. No engine backup, current build, app, test, failure capture, Markdown or patch is selected.

## Historical roles

- July/August Run55/56/58: older translation-stack promotion staging copies. These Vulkan headers are compile-time interfaces; byte-identical variants are grouped separately, never merged by filename/version label. Earlier September retirement already made these historical trees sparse.
- October R92: correctness, diagnostics, epoch accounting and timestamp experiments. The two duplicated SPIRV-Cross object files are dependency compiler output, not the MVK source differences that distinguish those experiments. Those sources/configuration/results remain intact. October R92 is distinct from the earlier September Run92/Run95 engine sequence.
- October 15 launcher: black startup and helper lifecycle fixes produced separate launcher snapshots. The selected music, Chromium notices and one byte-identical frontend JS are repeated material; unique launcher code, source maps, fixtures and the earlier failure reports remain. All engine-side launcher-source snapshots remain untouched.

The scope was narrowed using the existing cross-chat and engine-history reviews, not a claim that every historical chat or clean rebuild was reconstructed.

## Every selected group

| Group | Category | Copies retired | Bytes retired | Local copy kept |
| --- | --- | ---: | ---: | --- |
| G000 | r92-build-objects | 7 | 17077648 | `backups/runtime/r92-config-string-integration-20261009/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-msl.dir/spirv_msl.cpp.o` |
| G001 | r92-build-objects | 7 | 12648272 | `backups/runtime/r92-config-string-integration-20261009/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-glsl.dir/spirv_glsl.cpp.o` |
| G066 | early-vulkan-headers | 6 | 6592470 | `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan_hash.hpp` |
| G067 | early-vulkan-headers | 4 | 4892000 | `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan.hpp` |
| G068 | early-vulkan-headers | 4 | 9148680 | `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan_funcs.hpp` |
| G069 | early-vulkan-headers | 6 | 53321238 | `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan_structs.hpp` |
| G070 | early-vulkan-headers | 4 | 5422056 | `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan_core.h` |
| G071 | early-vulkan-headers | 4 | 7529912 | `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan_raii.hpp` |
| G072 | early-vulkan-headers | 4 | 7033244 | `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan_handles.hpp` |
| G073 | early-vulkan-headers | 1 | 1217114 | `backups/runtime/run56-20260721-before-runtime-refresh/BAR.app-runtime/moltenvk-pr2746/include/vulkan/vulkan.hpp` |
| G074 | early-vulkan-headers | 3 | 6843561 | `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan_funcs.hpp` |
| G075 | early-vulkan-headers | 1 | 1353021 | `backups/runtime/run56-20260721-before-runtime-refresh/BAR.app-runtime/moltenvk-pr2746/include/vulkan/vulkan_core.h` |
| G076 | early-vulkan-headers | 3 | 5624274 | `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan_raii.hpp` |
| G077 | early-vulkan-headers | 1 | 1753283 | `backups/runtime/run56-20260721-before-runtime-refresh/BAR.app-runtime/moltenvk-pr2746/include/vulkan/vulkan_handles.hpp` |
| G078 | release-launcher-assets | 3 | 60346554 | `backups/engine/lobby-engine-upgrade-20261016/launcher-source/out/bar-lobby-darwin-arm64/LICENSES.chromium.html` |
| G079 | release-launcher-assets | 4 | 10840000 | `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Matteo_Dell_Acqua-Game_of_Chicken.ogg` |
| G080 | release-launcher-assets | 4 | 12120340 | `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Ryan_Krause-New_Order.ogg` |
| G081 | release-launcher-assets | 4 | 7377804 | `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Ryan_Krause-The_Architect.ogg` |
| G082 | release-launcher-assets | 4 | 17021832 | `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Ryan_Krause-Friend_Or_Foe.ogg` |
| G083 | release-launcher-assets | 4 | 20059116 | `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Matteo_Dell_Acqua-From_the_Ashes.ogg` |
| G084 | release-launcher-assets | 4 | 11305224 | `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Ryan_Krause-Divergents.ogg` |
| G085 | release-launcher-assets | 4 | 10441784 | `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Ryan_Krause-Confined_Chaos.ogg` |
| G086 | release-launcher-assets | 4 | 18015776 | `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Matteo_Dell_Acqua-fooBAR_Menu_Ver.ogg` |
| G087 | release-launcher-assets | 4 | 8185628 | `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Ryan_Krause-Sanctum.ogg` |
| G088 | release-launcher-assets | 1 | 1838718 | `backups/engine/lobby-engine-upgrade-20261016/launcher-source/.vite/renderer/main_window/assets/index-DT6cqJau.js` |
| G090 | early-vulkan-headers | 1 | 1097743 | `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan_hash.hpp` |
| G091 | early-vulkan-headers | 1 | 1216426 | `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan.hpp` |
| G092 | early-vulkan-headers | 1 | 8879270 | `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan_structs.hpp` |
| G093 | early-vulkan-headers | 1 | 1351842 | `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan_core.h` |
| G094 | early-vulkan-headers | 1 | 1753171 | `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan_handles.hpp` |

## Every retired path

### G000

Retain: `backups/runtime/r92-config-string-integration-20261009/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-msl.dir/spirv_msl.cpp.o`

SHA-256: `3917eef2a1c6210763ad7c7c1e82514be760ab94325ad4b67779409d1da8fdcc`

- `backups/runtime/r92-timestamp-resolve-reuse-app-20261010/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-msl.dir/spirv_msl.cpp.o`
- `backups/runtime/r92-runtime-correctness-20261008/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-msl.dir/spirv_msl.cpp.o`
- `backups/runtime/r92-timestamp-entry-20261010/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-msl.dir/spirv_msl.cpp.o`
- `backups/runtime/r92-cost-epoch-20261009/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-msl.dir/spirv_msl.cpp.o`
- `backups/runtime/r92-timestamp-submit-reduction-app-20261010/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-msl.dir/spirv_msl.cpp.o`
- `backups/runtime/r92-cost-instrumentation-20261009/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-msl.dir/spirv_msl.cpp.o`
- `backups/runtime/r92-cost-instrumentation-fixed-20261009/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-msl.dir/spirv_msl.cpp.o`

### G001

Retain: `backups/runtime/r92-config-string-integration-20261009/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-glsl.dir/spirv_glsl.cpp.o`

SHA-256: `16369732cad7b4dc73cbccbe68e7e6ab1d1c0bb2cf8f4841dd2f58e8bc554462`

- `backups/runtime/r92-timestamp-resolve-reuse-app-20261010/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-glsl.dir/spirv_glsl.cpp.o`
- `backups/runtime/r92-runtime-correctness-20261008/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-glsl.dir/spirv_glsl.cpp.o`
- `backups/runtime/r92-timestamp-entry-20261010/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-glsl.dir/spirv_glsl.cpp.o`
- `backups/runtime/r92-cost-epoch-20261009/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-glsl.dir/spirv_glsl.cpp.o`
- `backups/runtime/r92-timestamp-submit-reduction-app-20261010/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-glsl.dir/spirv_glsl.cpp.o`
- `backups/runtime/r92-cost-instrumentation-20261009/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-glsl.dir/spirv_glsl.cpp.o`
- `backups/runtime/r92-cost-instrumentation-fixed-20261009/builds/mvk/_deps/spirv-cross-build/CMakeFiles/spirv-cross-glsl.dir/spirv_glsl.cpp.o`

### G066

Retain: `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan_hash.hpp`

SHA-256: `f225e0fb261fd9c3c567dd596e764d598e64fbc14eb29b7ef383e5b4b10e3da5`

- `backups/runtime/run56-20260721-before-approved-pr2775/candidate-moltenvk-pr2746/include/vulkan/vulkan_hash.hpp`
- `backups/runtime/run56-20260721-before-approved-pr2775/staged-moltenvk-pr2746/include/vulkan/vulkan_hash.hpp`
- `backups/runtime/run56-20260721-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan_hash.hpp`
- `backups/runtime/run56-20260721-before-runtime-refresh/BAR.app-runtime/moltenvk-pr2746/include/vulkan/vulkan_hash.hpp`
- `backups/runtime/run58-20260823-before-runtime-refresh/candidate/moltenvk-pr2746/include/vulkan/vulkan_hash.hpp`
- `backups/runtime/run58-20260823-before-runtime-refresh/active/moltenvk-pr2746/include/vulkan/vulkan_hash.hpp`

### G067

Retain: `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan.hpp`

SHA-256: `1b381bb1c00c36006ea5d8cb4cce6435702c6e30be784b3420d2edaf1911b1e1`

- `backups/runtime/run56-20260721-before-approved-pr2775/candidate-moltenvk-pr2746/include/vulkan/vulkan.hpp`
- `backups/runtime/run56-20260721-before-approved-pr2775/staged-moltenvk-pr2746/include/vulkan/vulkan.hpp`
- `backups/runtime/run58-20260823-before-runtime-refresh/candidate/moltenvk-pr2746/include/vulkan/vulkan.hpp`
- `backups/runtime/run58-20260823-before-runtime-refresh/active/moltenvk-pr2746/include/vulkan/vulkan.hpp`

### G068

Retain: `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan_funcs.hpp`

SHA-256: `6beb302c8f8ab26afc4056718f63087f3829f65467a0628ee142844043992136`

- `backups/runtime/run56-20260721-before-approved-pr2775/candidate-moltenvk-pr2746/include/vulkan/vulkan_funcs.hpp`
- `backups/runtime/run56-20260721-before-approved-pr2775/staged-moltenvk-pr2746/include/vulkan/vulkan_funcs.hpp`
- `backups/runtime/run58-20260823-before-runtime-refresh/candidate/moltenvk-pr2746/include/vulkan/vulkan_funcs.hpp`
- `backups/runtime/run58-20260823-before-runtime-refresh/active/moltenvk-pr2746/include/vulkan/vulkan_funcs.hpp`

### G069

Retain: `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan_structs.hpp`

SHA-256: `03d0b7a96fb43ac05b98d829054de685eb148a2facce2e284a4c13fedb997ef4`

- `backups/runtime/run56-20260721-before-approved-pr2775/candidate-moltenvk-pr2746/include/vulkan/vulkan_structs.hpp`
- `backups/runtime/run56-20260721-before-approved-pr2775/staged-moltenvk-pr2746/include/vulkan/vulkan_structs.hpp`
- `backups/runtime/run56-20260721-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan_structs.hpp`
- `backups/runtime/run56-20260721-before-runtime-refresh/BAR.app-runtime/moltenvk-pr2746/include/vulkan/vulkan_structs.hpp`
- `backups/runtime/run58-20260823-before-runtime-refresh/candidate/moltenvk-pr2746/include/vulkan/vulkan_structs.hpp`
- `backups/runtime/run58-20260823-before-runtime-refresh/active/moltenvk-pr2746/include/vulkan/vulkan_structs.hpp`

### G070

Retain: `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan_core.h`

SHA-256: `a7ac0d7e35e77f642c175af5d36729cfdae2d626d2aaa9145c030a42bd44edc6`

- `backups/runtime/run56-20260721-before-approved-pr2775/candidate-moltenvk-pr2746/include/vulkan/vulkan_core.h`
- `backups/runtime/run56-20260721-before-approved-pr2775/staged-moltenvk-pr2746/include/vulkan/vulkan_core.h`
- `backups/runtime/run58-20260823-before-runtime-refresh/candidate/moltenvk-pr2746/include/vulkan/vulkan_core.h`
- `backups/runtime/run58-20260823-before-runtime-refresh/active/moltenvk-pr2746/include/vulkan/vulkan_core.h`

### G071

Retain: `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan_raii.hpp`

SHA-256: `5336b82c63b6229ff9d05229df44817c9b8533b0e63da5aed435f18399222f1b`

- `backups/runtime/run56-20260721-before-approved-pr2775/candidate-moltenvk-pr2746/include/vulkan/vulkan_raii.hpp`
- `backups/runtime/run56-20260721-before-approved-pr2775/staged-moltenvk-pr2746/include/vulkan/vulkan_raii.hpp`
- `backups/runtime/run58-20260823-before-runtime-refresh/candidate/moltenvk-pr2746/include/vulkan/vulkan_raii.hpp`
- `backups/runtime/run58-20260823-before-runtime-refresh/active/moltenvk-pr2746/include/vulkan/vulkan_raii.hpp`

### G072

Retain: `backups/runtime/run56-20260721-before-approved-pr2775/active-moltenvk-pr2746/include/vulkan/vulkan_handles.hpp`

SHA-256: `1bfbf0d70d5f6a0a623f5803e3d25fc6ec98095e8ea459c087d2ae28d2ff8cd9`

- `backups/runtime/run56-20260721-before-approved-pr2775/candidate-moltenvk-pr2746/include/vulkan/vulkan_handles.hpp`
- `backups/runtime/run56-20260721-before-approved-pr2775/staged-moltenvk-pr2746/include/vulkan/vulkan_handles.hpp`
- `backups/runtime/run58-20260823-before-runtime-refresh/candidate/moltenvk-pr2746/include/vulkan/vulkan_handles.hpp`
- `backups/runtime/run58-20260823-before-runtime-refresh/active/moltenvk-pr2746/include/vulkan/vulkan_handles.hpp`

### G073

Retain: `backups/runtime/run56-20260721-before-runtime-refresh/BAR.app-runtime/moltenvk-pr2746/include/vulkan/vulkan.hpp`

SHA-256: `839d1f45927a564871222daba2447e176eeff932784e6b2689dec25d9b2ad729`

- `backups/runtime/run56-20260721-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan.hpp`

### G074

Retain: `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan_funcs.hpp`

SHA-256: `d0fcfa8215ef7b6633968c7b223ebb04a35d342af19241ce31d92f5004ee77d2`

- `backups/runtime/run56-20260721-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan_funcs.hpp`
- `backups/runtime/run56-20260721-before-runtime-refresh/BAR.app-runtime/moltenvk-pr2746/include/vulkan/vulkan_funcs.hpp`
- `backups/runtime/run55-20260705-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan_funcs.hpp`

### G075

Retain: `backups/runtime/run56-20260721-before-runtime-refresh/BAR.app-runtime/moltenvk-pr2746/include/vulkan/vulkan_core.h`

SHA-256: `682de8fb5d47f9839d62732975e8c7d54f8d2e8c178d79977d698e34ebc64da9`

- `backups/runtime/run56-20260721-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan_core.h`

### G076

Retain: `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan_raii.hpp`

SHA-256: `dfeab55cafc27992cb6d88dd9ce266b565206ed19a7dc1b8f1d5dddf3c0396f1`

- `backups/runtime/run56-20260721-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan_raii.hpp`
- `backups/runtime/run56-20260721-before-runtime-refresh/BAR.app-runtime/moltenvk-pr2746/include/vulkan/vulkan_raii.hpp`
- `backups/runtime/run55-20260705-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan_raii.hpp`

### G077

Retain: `backups/runtime/run56-20260721-before-runtime-refresh/BAR.app-runtime/moltenvk-pr2746/include/vulkan/vulkan_handles.hpp`

SHA-256: `833e1857e81fd3d554643a283b91c5ab880cf06adaae4924da77d0bf41a8c56b`

- `backups/runtime/run56-20260721-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan_handles.hpp`

### G078

Retain: `backups/engine/lobby-engine-upgrade-20261016/launcher-source/out/bar-lobby-darwin-arm64/LICENSES.chromium.html`

SHA-256: `3375e2a9bd7bc631738fde10be6548a76efe8cf5e4b8826b8140ba8b0c4d6353`

- `backups/runtime/release-candidate-20261015/launcher-before-startup-fix/out/bar-lobby-darwin-arm64/LICENSES.chromium.html`
- `backups/runtime/release-candidate-20261015/launcher-before-helper-fix/out/bar-lobby-darwin-arm64/LICENSES.chromium.html`
- `backups/runtime/release-candidate-20261015/launcher-first-shipping-frontend/out/bar-lobby-darwin-arm64/LICENSES.chromium.html`

### G079

Retain: `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Matteo_Dell_Acqua-Game_of_Chicken.ogg`

SHA-256: `2498a2d1b301708edd0b23e51f05fb1a676ed1f6ed596aef060ac6959f19c187`

- `backups/runtime/release-candidate-20261015/launcher-before-startup-fix/.vite/renderer/main_window/assets/Matteo_Dell_Acqua-Game_of_Chicken-CQxv4JWk.ogg`
- `backups/runtime/release-candidate-20261015/launcher-before-helper-fix/.vite/renderer/main_window/assets/Matteo_Dell_Acqua-Game_of_Chicken-CQxv4JWk.ogg`
- `backups/runtime/release-candidate-20261015/launcher-generated-before-release/.vite/renderer/main_window/assets/Matteo_Dell_Acqua-Game_of_Chicken-CQxv4JWk.ogg`
- `backups/runtime/release-candidate-20261015/launcher-first-shipping-frontend/.vite/renderer/main_window/assets/Matteo_Dell_Acqua-Game_of_Chicken-CQxv4JWk.ogg`

### G080

Retain: `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Ryan_Krause-New_Order.ogg`

SHA-256: `650282c068e3b49408898a27eaaa9a7fcc25c2076c51d7a2771d4afb81433eec`

- `backups/runtime/release-candidate-20261015/launcher-before-startup-fix/.vite/renderer/main_window/assets/Ryan_Krause-New_Order-B7fVbW6K.ogg`
- `backups/runtime/release-candidate-20261015/launcher-before-helper-fix/.vite/renderer/main_window/assets/Ryan_Krause-New_Order-B7fVbW6K.ogg`
- `backups/runtime/release-candidate-20261015/launcher-generated-before-release/.vite/renderer/main_window/assets/Ryan_Krause-New_Order-B7fVbW6K.ogg`
- `backups/runtime/release-candidate-20261015/launcher-first-shipping-frontend/.vite/renderer/main_window/assets/Ryan_Krause-New_Order-B7fVbW6K.ogg`

### G081

Retain: `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Ryan_Krause-The_Architect.ogg`

SHA-256: `2062a39585deeeccd3ca98628a1e905c9b04221cb27efa57cab775c40da4f094`

- `backups/runtime/release-candidate-20261015/launcher-before-startup-fix/.vite/renderer/main_window/assets/Ryan_Krause-The_Architect-Ch3j-6Ih.ogg`
- `backups/runtime/release-candidate-20261015/launcher-before-helper-fix/.vite/renderer/main_window/assets/Ryan_Krause-The_Architect-Ch3j-6Ih.ogg`
- `backups/runtime/release-candidate-20261015/launcher-generated-before-release/.vite/renderer/main_window/assets/Ryan_Krause-The_Architect-Ch3j-6Ih.ogg`
- `backups/runtime/release-candidate-20261015/launcher-first-shipping-frontend/.vite/renderer/main_window/assets/Ryan_Krause-The_Architect-Ch3j-6Ih.ogg`

### G082

Retain: `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Ryan_Krause-Friend_Or_Foe.ogg`

SHA-256: `aeeff15344c2d2d486d450dbe5d6f598faddf662b44421fdcc528a95c1eb8588`

- `backups/runtime/release-candidate-20261015/launcher-before-startup-fix/.vite/renderer/main_window/assets/Ryan_Krause-Friend_Or_Foe-CkjqHNiF.ogg`
- `backups/runtime/release-candidate-20261015/launcher-before-helper-fix/.vite/renderer/main_window/assets/Ryan_Krause-Friend_Or_Foe-CkjqHNiF.ogg`
- `backups/runtime/release-candidate-20261015/launcher-generated-before-release/.vite/renderer/main_window/assets/Ryan_Krause-Friend_Or_Foe-CkjqHNiF.ogg`
- `backups/runtime/release-candidate-20261015/launcher-first-shipping-frontend/.vite/renderer/main_window/assets/Ryan_Krause-Friend_Or_Foe-CkjqHNiF.ogg`

### G083

Retain: `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Matteo_Dell_Acqua-From_the_Ashes.ogg`

SHA-256: `4ef6c3e71fe078ee4da41aa2eaeab2dbead09829471e0b00c0980414730b5aee`

- `backups/runtime/release-candidate-20261015/launcher-before-startup-fix/.vite/renderer/main_window/assets/Matteo_Dell_Acqua-From_the_Ashes-BAVdXUYL.ogg`
- `backups/runtime/release-candidate-20261015/launcher-before-helper-fix/.vite/renderer/main_window/assets/Matteo_Dell_Acqua-From_the_Ashes-BAVdXUYL.ogg`
- `backups/runtime/release-candidate-20261015/launcher-generated-before-release/.vite/renderer/main_window/assets/Matteo_Dell_Acqua-From_the_Ashes-BAVdXUYL.ogg`
- `backups/runtime/release-candidate-20261015/launcher-first-shipping-frontend/.vite/renderer/main_window/assets/Matteo_Dell_Acqua-From_the_Ashes-BAVdXUYL.ogg`

### G084

Retain: `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Ryan_Krause-Divergents.ogg`

SHA-256: `3cc8b837aef8bf7a8e1b081ccfdf72fdb583a712c995628c8ad20ed49017c1a8`

- `backups/runtime/release-candidate-20261015/launcher-before-startup-fix/.vite/renderer/main_window/assets/Ryan_Krause-Divergents-DLSHhG7D.ogg`
- `backups/runtime/release-candidate-20261015/launcher-before-helper-fix/.vite/renderer/main_window/assets/Ryan_Krause-Divergents-DLSHhG7D.ogg`
- `backups/runtime/release-candidate-20261015/launcher-generated-before-release/.vite/renderer/main_window/assets/Ryan_Krause-Divergents-DLSHhG7D.ogg`
- `backups/runtime/release-candidate-20261015/launcher-first-shipping-frontend/.vite/renderer/main_window/assets/Ryan_Krause-Divergents-DLSHhG7D.ogg`

### G085

Retain: `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Ryan_Krause-Confined_Chaos.ogg`

SHA-256: `f419ea46356c6d21315a41050655fd0c4992c9a1ef4d040c8a39178a0e976609`

- `backups/runtime/release-candidate-20261015/launcher-before-startup-fix/.vite/renderer/main_window/assets/Ryan_Krause-Confined_Chaos--vFJayge.ogg`
- `backups/runtime/release-candidate-20261015/launcher-before-helper-fix/.vite/renderer/main_window/assets/Ryan_Krause-Confined_Chaos--vFJayge.ogg`
- `backups/runtime/release-candidate-20261015/launcher-generated-before-release/.vite/renderer/main_window/assets/Ryan_Krause-Confined_Chaos--vFJayge.ogg`
- `backups/runtime/release-candidate-20261015/launcher-first-shipping-frontend/.vite/renderer/main_window/assets/Ryan_Krause-Confined_Chaos--vFJayge.ogg`

### G086

Retain: `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Matteo_Dell_Acqua-fooBAR_Menu_Ver.ogg`

SHA-256: `323ca21c8d8a1f4083641f3d90aa310fcaec7cbe7ff82eef1b61bce897af526f`

- `backups/runtime/release-candidate-20261015/launcher-before-startup-fix/.vite/renderer/main_window/assets/Matteo_Dell_Acqua-fooBAR_Menu_Ver-BUBvhsAK.ogg`
- `backups/runtime/release-candidate-20261015/launcher-before-helper-fix/.vite/renderer/main_window/assets/Matteo_Dell_Acqua-fooBAR_Menu_Ver-BUBvhsAK.ogg`
- `backups/runtime/release-candidate-20261015/launcher-generated-before-release/.vite/renderer/main_window/assets/Matteo_Dell_Acqua-fooBAR_Menu_Ver-BUBvhsAK.ogg`
- `backups/runtime/release-candidate-20261015/launcher-first-shipping-frontend/.vite/renderer/main_window/assets/Matteo_Dell_Acqua-fooBAR_Menu_Ver-BUBvhsAK.ogg`

### G087

Retain: `backups/engine/lobby-engine-upgrade-20261016/launcher-source/src/renderer/assets/audio/music/Ryan_Krause-Sanctum.ogg`

SHA-256: `4888a65f89692a97dcb2edd6bbc82523b505f6226ef7beb19a5c6abc804523d0`

- `backups/runtime/release-candidate-20261015/launcher-before-startup-fix/.vite/renderer/main_window/assets/Ryan_Krause-Sanctum-DIgDMcHu.ogg`
- `backups/runtime/release-candidate-20261015/launcher-before-helper-fix/.vite/renderer/main_window/assets/Ryan_Krause-Sanctum-DIgDMcHu.ogg`
- `backups/runtime/release-candidate-20261015/launcher-generated-before-release/.vite/renderer/main_window/assets/Ryan_Krause-Sanctum-DIgDMcHu.ogg`
- `backups/runtime/release-candidate-20261015/launcher-first-shipping-frontend/.vite/renderer/main_window/assets/Ryan_Krause-Sanctum-DIgDMcHu.ogg`

### G088

Retain: `backups/engine/lobby-engine-upgrade-20261016/launcher-source/.vite/renderer/main_window/assets/index-DT6cqJau.js`

SHA-256: `5818db1d46ab48a8e5bbd1584af751b859a3c4ae0f8f5ffde7de3e309cad77a8`

- `backups/runtime/release-candidate-20261015/launcher-before-helper-fix/.vite/renderer/main_window/assets/index-DT6cqJau.js`

### G090

Retain: `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan_hash.hpp`

SHA-256: `aba9ea7039eee141cecf9602be7d0fb74fcbb1bd40dcbab6c372753dd008034c`

- `backups/runtime/run55-20260705-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan_hash.hpp`

### G091

Retain: `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan.hpp`

SHA-256: `87c040ca098d2638660eb7f85e5144cd7637fe7f93ab3b20b9b42400390aa899`

- `backups/runtime/run55-20260705-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan.hpp`

### G092

Retain: `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan_structs.hpp`

SHA-256: `c019e177b6a00ebf6d8fbc7e9d18b081f1b2826d2b23ab25f81c5220dd7f8915`

- `backups/runtime/run55-20260705-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan_structs.hpp`

### G093

Retain: `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan_core.h`

SHA-256: `ba593c093dfd634f691e11099378847ce9b6a5cd0002835cf809239945753b58`

- `backups/runtime/run55-20260705-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan_core.h`

### G094

Retain: `backups/runtime/run55-20260705-before-runtime-refresh/app-runtime/moltenvk-pr2746/include/vulkan/vulkan_handles.hpp`

SHA-256: `f7f5c1313e6250b3d53a097492e02ead1c7fb58fd57b47a1d97776c2957b080e`

- `backups/runtime/run55-20260705-before-runtime-refresh/candidate-runtime/moltenvk-pr2746/include/vulkan/vulkan_handles.hpp`

## Recovery and qualification

The adjacent manifest connects each retired path to its unchanged local canonical and to exact Git payload bytes. From a checkout of this checkpoint, use restore.py with a new empty destination. It writes the retired workspace-relative paths under that destination and never overwrites an existing file. This restores only the listed entries, not a complete historical app/build.

All selected historical trees keep their prior unrelated contents. The source-map pair is excluded because it contains a private absolute source path. No private profile, account, process dump or replay data is published.

Before deletion: publish the exact commit, anonymously fetch all selected public payloads/manifest/helper and verify hashes/modes, then recheck original copies and retained canonicals. Space accounting separates logical removed bytes from observed whole-volume available-space changes.
