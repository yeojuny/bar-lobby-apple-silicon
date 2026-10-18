# S2 cumulative source recipe

1. Obtain the public candidate.4 source asset and verify its outer SHA256 `65e29a1b17c7d434fa6a4c97b5040a0236f1edb36d869f0b18c6fb27f70c792e`. Read `BAR-0.17.0-candidate.4-sources/archives/sdl3-4a17e772.tar.gz` and verify its SHA256 `a0d0c257c748660936e2b19c561e338ba8198982c44b9e9dfbaf4312c515197f`. The nested component root is `sdl3-4a17e772` and retains the port property corrections.
2. Apply the **complete S1 patch** from commit `11bb59e12b0d4d7a7c8175fd21cd9d574e660867`, SHA256 `1639ed588fef528ccc1b676872c847e807a1e597cbd74b7b341216d51debcfda`, at strip level 1 with no fuzz. Its URLs/postimages are pinned in `manifest.json`.
3. Verify all S2 preimages. `SDL_getenv.c` and `testautomation.c` match the original port archive; `testautomation_stdlib.c` must have S1 postimage SHA256 `60c240c1cb452536716dc7d2896839ff95612fefac92efcaf2aa92ba6b2c3c77`. Apply the complete S2 three-file patch at strip level 1 with no fuzz and verify every postimage. Do not apply S2 directly to the original Stdlib file or replace S1 with pristine upstream.
4. Reuse the exact S1 build configuration/input recipe. The existing optional test-only `CMAKE_DISABLE_FIND_PACKAGE_FFmpeg=ON` setting is retained; S2 did not reconfigure or install dependencies. Build the existing SDL shared and testautomation targets:

```sh
cmake --build "$WORKSPACE/build/run95-sdl-20261002" --target SDL3-shared testautomation --parallel 3
```

The actual before/after commands are in `validation.json`. Each mandatory test used the rebuilt existing runner and exact lowercase `--no-init`, with process-only `DYLD_PRINT_LIBRARIES=1` to establish raw-library binding:

```sh
DYLD_PRINT_LIBRARIES=1 "$WORKSPACE/build/run95-sdl-20261002/test/testautomation" --no-init --filter stdlib_environmentAllocations --seed S2ENVFIXEDSEED
DYLD_PRINT_LIBRARIES=1 "$WORKSPACE/build/run95-sdl-20261002/test/testautomation" --no-init --filter stdlib_getsetenv --seed S2ENVFIXEDSEED
DYLD_PRINT_LIBRARIES=1 "$WORKSPACE/build/run95-sdl-20261002/test/testautomation" --no-init --filter stdlib_stepUTF8 --seed S2ENVFIXEDSEED
```

Before the production fix, environment assertions were 56 passed/1 failed of 57, skipped=0. After the fix: environment failure/cleanup 57/57, existing get/set environment 53/53, and cumulative S1 UTF-8 117/117; **227 passed, zero failed, mandatory selected skips=0**. The allocation hooks stay within the existing CPU-only test runner and forward to the saved allocator family. Different option capitalization or a non-CPU invocation is not certified by these receipts.

This is the recorded macOS/pthread component check, not a portable copied CMake cache, new standalone harness, app/game acceptance or automatic-termination instruction. No OS-level pthread_mutex_init failure, global-singleton concurrency or other-platform behavior is newly certified.
