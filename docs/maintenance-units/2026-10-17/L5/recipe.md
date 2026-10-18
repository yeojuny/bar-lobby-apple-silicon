# L5 public source and test recipe

1. Obtain the public candidate.4 source companion at the URL in `manifest.json`; verify outer SHA256 `65e29a1b17c7d434fa6a4c97b5040a0236f1edb36d869f0b18c6fb27f70c792e` and 374939453 bytes.
2. Read `BAR-0.17.0-candidate.4-sources/archives/vulkan-loader-68cc-input.tar.gz`; verify SHA256 `68269a49344a1b2fd318f56828c0ca7104ef08ea3144e4fe97ac93061e8c7420` and 1869775 bytes. Use its `vulkan-loader-68cc-input` component root, preserving the port's existing #2050 corrections. Verify all four preimages, apply the complete `change.patch` at strip level 1 without fuzz, and verify all four postimage hashes. Do not replace it with a production-only patch.
3. Retain the S1/S2 SDL public checkpoint chain separately. L5 is the first Loader unit and imports no later Loader/Cross fixes.

## Existing test-only dependency

The Loader's existing `scripts/known_good.json` declares GoogleTest **v1.14.0**, resolved to **f8d7d77c06936315286eb55f8de22cd23c188571**. Source URL: https://codeload.github.com/google/googletest/tar.gz/f8d7d77c06936315286eb55f8de22cd23c188571 . Verify the existing 868904-byte archive SHA256 **7ff5db23de232a39cbb5c9f5143c355885e30ac596161a6b9fc50c4538bfbf01**. Its archive root is `googletest-f8d7d77c06936315286eb55f8de22cd23c188571`.

The tested source is already connected at `$WORKSPACE/build/run95-loader-20261002/_deps/googletest` through `GOOGLETEST_INSTALL_DIR`. HQ verified all 245 source files against that archive. The dependency is for the existing test framework only; its archive is not copied or redistributed by this source checkpoint. Preserve its existing license. No automatic dependency update or new clone is part of this recipe.

## Recorded build and run sequence

Exact executed argument arrays and environment are in `validation.json`. Reuse the existing arm64 Loader build/toolchain configuration. The recorded preparation enables the existing official tests with local GoogleTest, `UPDATE_DEPS=OFF`, `ENABLE_LIVE_VERIFICATION_TESTS=OFF`, Apple clang++/ld and PRE_TEST discovery, then builds `vulkan test_regression test_icd_version_2` with parallelism 3. This test mode temporarily defines `SHOULD_EXPORT_TEST_FUNCTIONS`; it is **not** the accepted final production raw.

After applying L5, the same build is returned to production and rebuilt:

```sh
cmake -S "$WORKSPACE/build/run66-vulkan-loader-src-20260903" -B "$WORKSPACE/build/run95-loader-20261002" -DBUILD_TESTS=OFF -DUPDATE_DEPS=OFF
cmake --build "$WORKSPACE/build/run95-loader-20261002" --target vulkan --parallel 3
```

The sole post-fix run uses the already built official regression executable and mock ICD, process-only `DYLD_PRINT_LIBRARIES=1`, and this filter:

```sh
DYLD_PRINT_LIBRARIES=1 "$WORKSPACE/build/run95-loader-20261002/tests/test_regression" '--gtest_filter=CreateDevice.DeviceGroupPNextRestoredOnFailure:CreateDevice/DeviceGroupPNextRestore.*:EnumeratePhysicalDeviceGroups.OneCall:EnumeratePhysicalDeviceGroups.TwoCall:CreateDevice.ConsecutiveCreateWithoutDestruction' --gtest_color=no
```

The executed command also selected an XML evidence destination; its complete array is recorded in `validation.json`. The selected cases cover exact upstream rejection, 12 success/failure and valid-chain-layout combinations, existing core/KHR group enumeration, and consecutive no-group creation/cleanup. Before fix: 13 cases/5 expected failures in official test-export mode. Final production raw: **16 passed, zero failed/disabled/errors**, no test-export define, original product flags/link command and 1,015 export names preserved. Final raw SHA256 is `ad67a255b194f1ed9e3d8b8eb5cfd39850256290954d78ca4f195e6fcbf22822`.

These are mock-driver CPU checks of the selected lower-CreateDevice error path; they do not claim other early returns, real GPU/game/FPS/MP acceptance or an updated app. No product harness, app launch or automatic termination is part of L5.
