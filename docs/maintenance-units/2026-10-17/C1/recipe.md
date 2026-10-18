# C1 exact source/build and fixture recipe

Verify the public candidate.4 source companion (374939453 bytes), SHA256 `65e29a1b17c7d434fa6a4c97b5040a0236f1edb36d869f0b18c6fb27f70c792e`. Read `BAR-0.17.0-candidate.4-sources/archives/moltenvk-68cc-functional-diagnostics-off.tar.gz`; verify 8142625 bytes and SHA256 `7ce7b6fee52a78cedae5ec55bb8e8076763393cefcff0b5656d0d49d8ce4c56c`. From its `moltenvk-68cc-functional-diagnostics-off/External/SPIRV-Cross` directory, verify all seven preimages, apply complete C1 change.patch at strip level1 without fuzz and verify every postimage. This base includes #2687 and existing MVK port corrections; pristine upstream is insufficient. Keep separate accepted SDL S1/S2 and Loader L5/L4 patch chains.

## Complete canonical payload

The whole payload below is also embedded as object and exact UTF-8 string in manifest.json. Parse and serialize with `json.dumps(payload,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode("utf-8")`. Hash the serialized bytes without BOM, newline, code fences or path substitution.

```json
{"CrossBaseCommit":"aa217aeb6c9f0ace7a0ab233b28807edf45eb165","CrossNamespace":"MVK_spirv_cross","actualC1InputSHA256":{"reference/opt/shaders-msl/vert/float-math.invariant-float-math.vert":"c0f18ed6fa2a253f2d2f02ec6f38d9a0b768e217117a9c2c20bd8dd8556d6a85","reference/opt/shaders-msl/vert/no-contraction.vert":"d74d90024deb933bdeda847f454c6c68ccbdbceff2377505afc42370a98d4fa8","reference/shaders-msl-no-opt/asm/comp/compilation-loop-edge-case.spv16.asm.comp":"35a025152e272e8e6ec9c308c5886547a857f2fef3cecb0cf76ff888ba3c9ac5","reference/shaders-msl-no-opt/comp/precise-non-square-matrix.comp":"0769b7455524c563a9e0a9dd2a4f1a341ce50ddfc8e4d7ffb7a931a446f5b593","reference/shaders-msl/vert/float-math.invariant-float-math.vert":"d211fd1d616276853838d064a9e0590291fdd37d7871be51cdecb32df50b6349","reference/shaders-msl/vert/no-contraction.vert":"c5e0bdf9837c976c74adf2fbc25856cae22832a9a87f1fec9e2e05467f6ef01b","spirv_msl.cpp":"d74136375bbd7d644df9d52aeca42fc4bc7d157eb22043474c827c292dc5e10e"},"parentMVKBuildDigest":"0e7c41b9","preservedBuildConditionValues":{"CMAKE_BUILD_TYPE":"Release","CMAKE_CXX_COMPILER":"/usr/bin/c++","CMAKE_CXX_FLAGS":"-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0","CMAKE_CXX_FLAGS_RELEASE":"-O3 -DNDEBUG","CMAKE_C_COMPILER":"/usr/bin/cc","CMAKE_C_FLAGS":"-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0","CMAKE_C_FLAGS_RELEASE":"-O3 -DNDEBUG","CMAKE_LINKER":"/usr/bin/ld","CMAKE_OBJCXX_COMPILER":"/usr/bin/c++","CMAKE_OBJCXX_FLAGS":"-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0","CMAKE_OBJCXX_FLAGS_RELEASE":"-O3 -DNDEBUG","CMAKE_OBJC_COMPILER":"/usr/bin/cc","CMAKE_OBJC_FLAGS":"-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0","CMAKE_OBJC_FLAGS_RELEASE":"-O3 -DNDEBUG","CMAKE_OSX_ARCHITECTURES":"arm64","CMAKE_OSX_DEPLOYMENT_TARGET":"27.0","CMAKE_OSX_SYSROOT":"","MVK_BUILD_METAL4_FOUNDATION":"ON","MVK_BUILD_SHADER_CONVERTER_TOOL":"OFF","MVK_CONFIG_LOG_LEVEL":"info","MVK_EXCLUDE_CEREAL":"OFF","MVK_EXCLUDE_SPIRV_TOOLS":"OFF","MVK_USE_METAL_PRIVATE_API":"ON"},"preservedCrossPreimageWith2687SHA256":"98d3a9ef64004796014bab6b5325a389756f0ba571c0a86793c6513e3fa90ff7","schema":"bar-mvk-c1-source-build-identity-v1","selectedC1Commit":"300681bbcb8365a8d1eacdacdbdd0249bbf1d6b1"}
```

Canonical bytes:2153. SHA256: `f52facf761992e8d64a3e3c18bfa108565364fb5416b5708b5aeec5e3d26bb3a`. First eight lowercase hex digits produce **MVK_GIT_REV=f52facf7**, replacing0e7c41b9. The payload binds prior revision, actual seven postimages, #2687 preimage, Cross base/selected commit, namespace and preserved compiler/numeric/MVK conditions.

Use the existing source/build lane, keeping every other recorded condition:

```sh
cmake -S "$WORKSPACE/build/run66-moltenvk-src-20260903" -B "$WORKSPACE/build/metal4-mvk-20261002" -DMVK_GIT_REV=f52facf7
cmake --build "$WORKSPACE/build/metal4-mvk-20261002" --target MoltenVK --parallel 3
```

Final raw SHA256 `6973721f4bc0b63d3e00a969eb65836cc2eab4e2dc988f24a5489c48c13233f6`; MSL archive `5c1c6653d57b58b17d6668309d858013cf90df62b6dbcffa58aecdbacaba638d`; generated mvkGitRevDerived.h `d4b37774cbc39879e58edc90b60628273be33aa50b1d620d97a50dfcb725b9e7`. Only the root MVK_GIT_REV cache value changes; all142 production compile commands remain exact.

Unchanged initPipelineCacheUUID consumes this revision in the first four big-endian bytes for matching device/features. Static source/header/raw embedding was checked. No GPU UUID query, user-cache read/deletion or automatic app launch is implied; Cross edits do not automatically update the revision.

## Official tools and actual checks

Use existing test_shaders.py cross_compile_msl, runner SHA256 `4498d20d1ee78c2a95d67a0c1c7c0c703088054d864d42373789644f938dba05`, iterations1. validation.json records all eight fixture input/expected/output hashes and per-case command arrays, including SPIR-V1.6, optimized/nonoptimized, MSL version and invariant options. The post-change translator is relinked against current MSL/GLSL/Core/Reflect archives in MVK_spirv_cross; its exact relink argv and archive hashes are recorded there. CLI-only C++/HLSL/utility support is not added to MoltenVK.

SPIRV-Tools source pin: `ba9a9e32160e2500ce1e48cc563a8fedaf596e6e`. Already-declared test-only glslang: `31b9aacfaf3adf9c514f53d0f43f390a578f00f1`, source URL `https://codeload.github.com/KhronosGroup/glslang/tar.gz/31b9aacfaf3adf9c514f53d0f43f390a578f00f1`, archive SHA256 `11d455eb87549488e4dbd85d40f088e3084e25b95a48d936bc9150932239e2e8` (4647618 bytes), ENABLE_OPT OFF. Reuse the existing build dependency cache; no new global compiler/SDK, product harness, benchmark or archive redistribution. Exact executed tool SHA256 pins:

- `spirv-cross`: `180a84e30574034030df07c5c6ed0b3c3a703d63788ff88a3fd2f1b68d4dd335`
- `glslang`: `9fdc555360439260a7d6229fda8dc9ed95c087e6fc041f7b24c92218add11cee`
- `spirv-as`: `6a673b48ca0fa15182a1fed295434facfd3a077cf537bba5ebce22fa3f97f97e`
- `spirv-val`: `ac327a413d3dad970698a432a11251b1378bb47377e2bb1a6c259ae01a8bddba`
- `spirv-opt`: `b2c59999b5ccd67848252209682161a30569a7c6504dae3d17f0aefbfe72e39c`

Before C1 all eight outputs matched old references; six captured pre-C1 outputs differ from the new C1 expectations while both alias outputs still match. After C1 six required expected outputs and two alias outputs match byte-exactly, with SPIR-V validation. These checks do not execute Metal compilation or prove GPU negative-zero arithmetic, BAR shader reachability, FPS/energy/game/MP/endurance or app acceptance. Native symbol-name4482/dependency/install-name checks are bounded evidence, not a general GPU ABI claim. Source publication does not update a frozen/installed/public app, tag, V1 Release or Homebrew.
