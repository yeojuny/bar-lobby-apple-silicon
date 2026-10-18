# L1 cumulative public source and focused check recipe

Verify public candidate.4 source companion SHA256 `65e29a1b17c7d434fa6a4c97b5040a0236f1edb36d869f0b18c6fb27f70c792e` (374939453 bytes). Read `BAR-0.17.0-candidate.4-sources/archives/vulkan-loader-68cc-input.tar.gz` and verify SHA256 `68269a49344a1b2fd318f56828c0ca7104ef08ea3144e4fe97ac93061e8c7420` (1869775 bytes), root `vulkan-loader-68cc-input`.

Apply complete L5 then complete atomic L4 patches using the commit/patch pins in manifest.json, retaining existing port corrections. Verify both L1 preimages, apply full accepted L1 change.patch at strip level1 without fuzz and verify postimages. loader/wsi.c preimage SHA256 is `5c956aa22fdb22d85fc79b1cd11a508c90429b6a86a7f37d409a4bf8e21a413a`; existing public tests/loader_threading_tests.cpp preimage is `74136c5154c2651f553e1dfd7e85742ed0f6492419f3df3e5333831763cb28fd`. No later locking changes are included.

The actual source is Run95+VBO cumulative port plus candidate.5 custom maintenance and accepted units. Historical run66 source-directory labels are paths, not source versions. Keep the current VK_USE_PLATFORM_MACOS_MVK legacy-iOS guard before lock acquisition and preserve local handle conversion; only the official additions move to fit that port context.

Reuse existing official test_threading/test_regression/mock ICD targets and the declared GoogleTest dependency already connected in the same build _deps (public L5 recipe). No archive copy/download or new test harness is needed. Exact existing build/test commands and actual binding evidence are recorded in validation.json. Restore final production BUILD_TESTS OFF, UPDATE_DEPS OFF, live verification OFF and build the existing vulkan target before the accepted final mock runs.

```sh
cmake -S "$WORKSPACE/build/run66-vulkan-loader-src-20260903" -B "$WORKSPACE/build/run95-loader-20261002" -DBUILD_TESTS=OFF -DUPDATE_DEPS=OFF -DENABLE_LIVE_VERIFICATION_TESTS=OFF -DCMAKE_GTEST_DISCOVER_TESTS_DISCOVERY_MODE=PRE_TEST
cmake --build "$WORKSPACE/build/run95-loader-20261002" --target vulkan --parallel 3
DYLD_PRINT_LIBRARIES=1 "$WORKSPACE/build/run95-loader-20261002/tests/test_threading" '--gtest_filter=Threading.SurfaceCreateDestroyLoop:Threading.SurfaceQueryWhileCreateDestroySurfaceLoop' --gtest_color=no
DYLD_PRINT_LIBRARIES=1 "$WORKSPACE/build/run95-loader-20261002/tests/test_regression" '--gtest_filter=WsiTests.GoogleSurfacelessQuery:WsiTests.GetPhysicalDeviceSurfaceCapabilities2EXTEmulationDriverError:WsiTests.CreateMetalSurfaceWithoutEnablingExtension' --gtest_color=no
```

Actual invocations also select XML evidence destinations. Both threading cases and all three WSI cases pass on final production raw SHA256 `28124bfa19b9145aceb9cc7a87b7c8ba61db293e8e26305404f663e2e4a5b55d`; no MoltenVK or actual window was loaded/created. Original product C/ASM flags/link command and1015 public export names/dependencies/install name are preserved. Cache setting values match but cache bytes do not: ENABLE_LIVE_VERIFICATION_TESTS type changed BOOL to UNINITIALIZED, same OFF value. C1 MVK_GIT_REV=f52facf7 is separate and unchanged.

The official regression holds one query_surface valid until all worker/query threads join, while distinct batches of70 other surfaces grow and shrink the list. It does not validate concurrent destruction of the queried surface. Static review confirms both post-lock exits release and platform early-outs remain before acquire. Ordinary mock stress without ThreadSanitizer cannot establish race freedom or every possible interleaving; no pre-fix failure of the new case was reproduced. The selected error case verifies error forwarding, not every lazy-creation failure branch. No GPU/app/game/FPS/MP/endurance or new release acceptance is claimed.
