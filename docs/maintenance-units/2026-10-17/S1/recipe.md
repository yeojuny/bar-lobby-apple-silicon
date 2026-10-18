# S1 source reconstruction and focused build

1. Obtain the candidate.4 source companion from the immutable-version release URL in `manifest.json`. Verify its 374939453-byte length and SHA256 `65e29a1b17c7d434fa6a4c97b5040a0236f1edb36d869f0b18c6fb27f70c792e`. An asset URL alone is not an integrity guarantee.
2. Read member `BAR-0.17.0-candidate.4-sources/archives/sdl3-4a17e772.tar.gz`. Verify SHA256 `a0d0c257c748660936e2b19c561e338ba8198982c44b9e9dfbaf4312c515197f`; its component root is `sdl3-4a17e772`. This already contains the existing local SDL property corrections. Verify both touched-file preimages against `manifest.json`.
3. Apply the complete `change.patch` from the component root with strip level 1 and no fuzz. Verify both postimage SHA256 values. It includes the production fix and the existing test-suite regression; do not substitute `production-only.patch`.
4. Use the existing ARM64 SDL component build configuration recorded in `manifest.json` and the original source companion's build materials. Recorded workstation paths use `$WORKSPACE`; this is a source/build association and selected configuration record, not a promise that copied cache paths work on another Mac. Do not run stale testautomation binaries against an old library.

The executed focused preparation disabled unrelated optional FFmpeg test discovery using the following setting, preserving production compile flags:

```sh
cmake -S "$WORKSPACE/build/run66-sdl-src-20260903" \
  -B "$WORKSPACE/build/run95-sdl-20261002" \
  -DCMAKE_DISABLE_FIND_PACKAGE_FFmpeg=ON
cmake --build "$WORKSPACE/build/run95-sdl-20261002" \
  --target SDL3-shared testautomation --parallel 3
```

The related existing runner was rebuilt before the before/after runs. Each filter below used `--video dummy --audio dummy --seed S1UTF8FIXEDSEED`, with process-only `DYLD_PRINT_LIBRARIES=1` to record the actual build-local SDL binding:

- `stdlib_stepUTF8`: 14 expected pre-fix assertion failures; 117 post-fix assertions passed.
- `stdlib_strstr`: 20 assertions passed.
- `stdlib_strpbrk`: 54 assertions passed.
- `stdlib_iconv`: 81 assertions passed.

Use the recorded exact command arrays and raw-library/test executable hashes in `validation.json`. These CPU/dummy test invocations are not BAR.app launches or an instruction to change user sound/display settings. No game/FPS/MP test or automatic app termination belongs to S1.
