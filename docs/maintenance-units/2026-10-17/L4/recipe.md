# L4 cumulative public source and verification recipe

1. Verify the public candidate.4 source companion: 374939453 bytes, SHA256 `65e29a1b17c7d434fa6a4c97b5040a0236f1edb36d869f0b18c6fb27f70c792e`. Read member `BAR-0.17.0-candidate.4-sources/archives/vulkan-loader-68cc-input.tar.gz` and verify its SHA256 `68269a49344a1b2fd318f56828c0ca7104ef08ea3144e4fe97ac93061e8c7420` and 1869775 bytes. The component root is `vulkan-loader-68cc-input`.
2. Apply the complete public L5 patch from commit `a190072b355b145da241821c33210890b70a890a`, SHA256 `d144ecc2f6b8ef15f6f8d0ac2e900664e6f1d2ca897e396a63e3ea691493943c`, retaining its caller-chain restoration and existing test/mock support.
3. Verify the four L4 preimages in `manifest.json`; apply **the complete atomic L4 change.patch** at strip level 1 without fuzz and verify all postimage hashes. Never publish/build only the first upstream fix as L4. Preserve the separate accepted SDL S1/S2 source chain.

## Existing dependency and test modes

Reuse the existing declared GoogleTest v1.14.0 exact commit `f8d7d77c06936315286eb55f8de22cd23c188571` from its already connected `$WORKSPACE/build/run95-loader-20261002/_deps/googletest`. Source URL and archive SHA256 `7ff5db23de232a39cbb5c9f5143c355885e30ac596161a6b9fc50c4538bfbf01` are pinned in `manifest.json` and the public L5 recipe. No dependency update, archive copy, extraction or download is repeated for this unit.

Exact executed argument arrays/environment are in `validation.json`. Existing test mode uses BUILD_TESTS ON, local GOOGLETEST_INSTALL_DIR, UPDATE_DEPS OFF, live verification OFF, Apple clang++/ld and PRE_TEST discovery in the same Loader build. Build only affected existing `test_fuzzing`, `test_regression` and required existing mock targets. Run the existing `test_fuzzing` with `--gtest_filter=SettingsPathDiscovery.*` in its private writable fixture cwd/TMPDIR and process-only DYLD_PRINT_LIBRARIES=1: **three helper cases passed** against the test-only helper-export raw. This direct helper is not run or exported in production.

Then restore the same build to production and rebuild:

```sh
cmake -S "$WORKSPACE/build/run66-vulkan-loader-src-20260903" -B "$WORKSPACE/build/run95-loader-20261002" -DBUILD_TESTS=OFF -DUPDATE_DEPS=OFF
cmake --build "$WORKSPACE/build/run95-loader-20261002" --target vulkan --parallel 3
```

The existing public-API test executable then runs against the actual final production raw, helper export absent:

```sh
DYLD_PRINT_LIBRARIES=1 "$WORKSPACE/build/run95-loader-20261002/tests/test_regression" '--gtest_filter=SettingsXDG/SettingsPathListIntegration.*:SettingsFile.FileExist:SettingsFile.SettingsInUnsecuredLocation:SettingsFile.SupportsMultipleSettingsSimultaneously:SettingsFile.AdditionalDrivers:SettingsFile.ExclusiveAdditionalDrivers' --gtest_color=no
```

The actual invocation records its XML destination and isolated existing mock-driver/layer fixtures. **Nine final production API cases passed, zero failures/disabled/errors**. Four cover XDG_CONFIG_DIRS/XDG_DATA_DIRS later-only versus first-and-later settings; five preserve existing priority/additional/exclusive-driver behavior. Final raw SHA256 `3124b06d6ce0341332a3a41c45431ef05f241b8bb92123c5e3f3e8649ecc8046`; public exports 1,015 and dependency/install-name records remain exact.

## Corrections, metadata and limits

The initial API fixture omitted an independently discoverable regular driver after overriding XDG lists. That missing-driver failure is retained, not counted as the functional regression. The corrected fixture supplies its regular mock ICD through the existing environment-manifest mechanism; before the fix, the two later-only cases demonstrably kept the wrong regular driver/no layer, while first-path cases already passed. After the full pair, later-file driver/layer choices take effect and first-path priority remains. Actual user home/XDG files were not touched.

Cache setting values match, but cache bytes do not: CMAKE_CXX_COMPILER STRING and CMAKE_LINKER FILEPATH entry types changed to UNINITIALIZED. Actual C/ASM flags and link command remain byte-exact. Do not describe the cache as byte-identical or the helper-only results as production results. Valid terminated/embedded-NUL inputs were tested, without an unterminated-string or sanitizer claim.

This is controlled mock CPU verification, not every external profile/driver combination, a performance claim, app packaging or GPU/game/MP acceptance. No unrelated locking change or automatic app termination belongs to L4.
