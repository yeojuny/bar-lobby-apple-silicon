# L5: restore the caller pNext chain on device-creation failure

Apply the narrow production hunk from Vulkan-Loader [77406fdf](https://github.com/KhronosGroup/Vulkan-Loader/commit/77406fdfcd5706fd2a5d8f4473a6408fa6218b32) to the pinned public port base. The existing pNext restoration now runs before returning a lower CreateDevice error; the original error is propagated and the success-only chain-device assignment remains success-only. No new allocation or locking policy is introduced.

The complete four-file [patch](change.patch) includes the production file, the existing regression tests and minimal existing mock-ICD result/call-count controls. Before the fix, 5 of 13 selected cases failed as expected. Afterward, all 16 cases passed against the final **production Loader with BUILD_TESTS OFF**, using the same test executable and mock ICD. The original C/ASM flags and link command, 1,015 public export names, dependencies and install name were preserved.

See [manifest](manifest.json), [validation](validation.json), [applied audit](applied-audit.json), and [recipe](recipe.md). The manifest pins all four public preimages and the exact existing test-only GoogleTest dependency. The maintenance commit follows S2; the independent SDL S1/S2 chain is preserved.

This is a source/raw-component checkpoint. It does not repair all possible early returns or establish real GPU, gameplay, FPS, multiplayer or broad memory-leak acceptance. Apps, installed/public releases, tags and Homebrew are outside this checkpoint.
