# Reusing the SDL3 compatibility adapter

This port runs on **SDL3**, while retaining selected SDL2-shaped source calls and CMake target names. It is a source compatibility adapter for Recoil, not an SDL2 runtime, a complete SDL2 emulation library, or an OpenGL-to-Metal translator.

## How it works

When `APPLE` and `RECOIL_MACOS_SDL3_EGL` are enabled, `rts/build/cmake/FindSDL2.cmake` resolves SDL3, creates the interface target `SDL2_SDL3Compat`, and aliases the existing `SDL2::SDL2` target to it. That interface links **`SDL3::SDL3`**, places `rts/System/SDLCompat` ahead of other include directories, and supplies the compatibility definitions.

`rts/System/SDLCompat/SDLRecoilCompat.h` adapts the calls used by this engine. For example, SDL3's boolean result from `SDL_GL_SetSwapInterval` is converted to the old caller's expected `0` on success and `-1` on failure. Header shims, renamed symbols, event/input adaptations and separate engine changes complete the integration. The old target name therefore does not establish which library is loaded.

This preserves a familiar engine-facing interface without requiring every caller to be rewritten at once. It does **not** mean all SDL2 programs can use this header unchanged. The official [SDL3 migration guide](https://wiki.libsdl.org/SDL3/README-migration) remains the reference for changed semantics.

## Source map and reuse boundary

The complete, current files are in both engine archives inside the [v1.0.3 source companion](https://github.com/yeojuny/bar-lobby-apple-silicon/releases/tag/v1.0.3), `BAR-1.0.3-sources.tar.gz`:

- `archives/recoil-lobby-01efdf4-1.0.3.tar.gz`
- `archives/recoil-chobby-2026.07.04-1.0.3.tar.gz`

Within each engine archive, start with:

| Source | Responsibility |
|---|---|
| `rts/build/cmake/FindSDL2.cmake` | Existing target name routed to SDL3 |
| `rts/build/cmake/FindSDL3.cmake` | SDL3 discovery |
| `rts/System/SDLCompat/` | Engine-specific headers and call adapters |
| `rts/System/Platform/Mac/MacSDL3EGLBridge.h` and `.mm` | Cocoa window/context/display integration, separate from the call adapter |
| `rts/Rendering/GlobalRendering.cpp` | Engine window and presentation integration |

The historical [R80 engine patch](../stack-records/r80-20261008/patches/engine-r80.patch) makes the integration inspectable in the browser. It is a cumulative historical diff, not a newly extracted standalone patch or the exact latest release by itself. Read its [source record](../stack-records/r80-20261008/source-record.json) before applying it.

## What another port should take

1. Inventory its actual SDL2 calls and target names. Copy only relevant adapters, preserving the original licenses and attribution.
2. Check success/failure conventions, event layouts, window identifiers, keyboard/mouse coordinates, relative input and fullscreen transitions. A successful compile is not a behavioral test.
3. Keep native window ownership and the graphics context path consistent. Migrating the SDL API does not automatically provide the [Cocoa/EGL/Vulkan presentation bridge](COCOA-EGL-METAL-PRESENTATION.md).
4. Verify the resulting executable's linked/loaded SDL library rather than inferring it from an `SDL2::SDL2` target name.
5. Test logical window size, pixel drawable size, monitor changes, input mapping, focus and exit behavior together.

Our default 1x drawable and notch handling are deliberate port policies implemented with Cocoa integration. They are not automatic benefits guaranteed by SDL3. SDL3 alone also makes no FPS promise.

## Provenance and validation

This guide documents existing code; it does not modify or newly validate a binary. The [stack ledger](../stack-records/2026-10-17/COMPONENTS.md) pins the shipped SDL3 development snapshot and the [release notes](../release-readiness/2026-10-18-v1.0.3/README.md) delimit validation. Preserve Recoil/Spring and SDL licensing; documentation here does not relicense their code. This integration has not been published as a standalone supported library, and no upstream acceptance is implied.
