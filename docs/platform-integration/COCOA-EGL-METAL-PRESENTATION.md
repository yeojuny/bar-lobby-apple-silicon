# Reusing the Cocoa/EGL/Vulkan Metal presentation bridge

The MoltenVK build uses a native Cocoa window and a Vulkan Metal surface for ordinary frame presentation. It does not need an X11 server or XQuartz, and it does not use a separate engine-side full-frame readback-and-represent pipeline for that path.

This is window-system integration around the existing OpenGL renderer, not a native Metal rewrite of Recoil and not a claim of zero copies, zero waits or zero latency throughout the driver stack.

## Two paths that meet at the window

The rendering commands follow:

**Recoil OpenGL → Mesa/Zink → Vulkan → MoltenVK → Metal.**

The window/presentation integration follows:

1. SDL3 creates and manages the native window and input/events.
2. `MacSDL3EGLBridge` obtains the Cocoa `NSWindow`/view and attaches a `CAMetalLayer`.
3. The local Mesa Cocoa EGL integration connects an EGL window surface to that layer through the DRI/Kopper interface.
4. Zink's `KOPPER_METAL` path constructs a Vulkan surface with `VkMetalSurfaceCreateInfoEXT` / `vkCreateMetalSurfaceEXT`.
5. The engine's swap calls reach `eglSwapBuffers`, Kopper and Vulkan swapchain presentation. MoltenVK manages the Metal drawables for that surface and presents them to the Cocoa window.

The important integration is the handoff of the native surface between these components. Merely replacing a Vulkan driver library or switching the SDL version does not implement that handoff.

## Source map

Use the [v1.0.3 release](https://github.com/yeojuny/bar-lobby-apple-silicon/releases/tag/v1.0.3), verify `BAR-1.0.3-sources.tar.gz` against `SHA256SUMS`, and unpack the relevant nested archives. GitHub's automatic launcher-only source archive is insufficient.

| Nested archive / file | Responsibility |
|---|---|
| Either `recoil-*-1.0.3.tar.gz`: `rts/System/Platform/Mac/MacSDL3EGLBridge.h`, `.mm` | Cocoa/view/layer ownership, EGL bridge, drawable and target-screen geometry |
| Same engine: `rts/Rendering/GlobalRendering.cpp` | Normal engine swap/window integration |
| `mesa-zink-68cc-input.tar.gz`: `src/egl/drivers/dri2/platform_surfaceless.c` | Local Cocoa EGL window-surface and swap callbacks |
| Same Mesa archive: `src/gallium/frontends/dri/kopper.c` | DRI/Kopper surface handoff |
| Same Mesa archive: `src/gallium/drivers/zink/zink_kopper.c` and related headers | `KOPPER_METAL`, Vulkan Metal surface and swapchain handling |
| `moltenvk-1.0.0.tar.gz`: `MoltenVK/MoltenVK/GPUObjects/MVKSwapchain.mm` | Metal drawable/swapchain presentation |

Archive labels such as `moltenvk-1.0.0` are release-source packaging labels, not the underlying MoltenVK version. Consult the [exact stack ledger](../release-readiness/2026-10-17-candidate5/STACK-AND-PATCHES.md).

For browser review, the historical [engine patch](../stack-records/r80-20261008/patches/engine-r80.patch) and [Mesa patch](../stack-records/r80-20261008/patches/mesa-r80.patch) expose the relevant integration. They contain other work too; they are not standalone drop-in bridge patches. Later fixes and exact postimages are supplied in the release companion.

## Resolution is separate from presentation scheduling

`NativeCocoaDrawableScale` defaults to **1.0**. The bridge computes drawable dimensions from the view bounds and that scale, and keeps target-screen safe-area/fullscreen handling separate from desktop workarea. This is intentional: a high-density panel need not force the game to render at the panel's full backing resolution. Logical input coordinates and drawable dimensions must remain consistent.

Drawable acquisition, GPU completion and swapchain availability still impose synchronization. Keeping 1x rendering does not require an arbitrary fixed frame delay. Conversely, removing a wait without understanding ownership can corrupt frames, and deepening queues can improve throughput while worsening input latency. Changing presentation requires both visual and latency checks, not just an FPS counter.

## Adapting it elsewhere

- Port the engine bridge and the matching Mesa surface plumbing together; an unmodified system Mesa build is not assumed to provide this private Cocoa path.
- Preserve the native window/view/layer lifetime through EGL and swapchain teardown, resize and fullscreen transitions. Respect AppKit thread requirements.
- Check Vulkan Metal-surface support, swapchain image formats, extent updates and error handling. Verify the actual loaded driver.
- Preserve the application's resolution/UI policy. Test notched and non-notched screens, mixed-density monitor moves, mouse coordinates, resize, minimize/restore and clean exit.
- Measure actual presentation intervals, GPU/CPU waits and input responsiveness on macOS. Source inspection does not establish a performance improvement on another port.

This guide is an extraction map, not a claim that one small patch can be applied to every engine. Reuse the narrow relevant changes with their original licenses and attribution; leave unrelated simulation and gameplay changes out of the porting exercise. Mesa, MoltenVK, SDL and Recoil retain their respective upstream credits. No upstream approval of this local integration is implied.

## Validation scope

The [validation records](../release-readiness/2026-10-18-v1.0.3/README.md) distinguish historical gameplay observations, CPU/package checks and pending acceptance on other machines. This documentation update adds no new runtime test result.
