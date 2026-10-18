# BAR for Apple Silicon

Play **Beyond All Reason on Apple Silicon Macs** in one **BAR.app**: use **bar-lobby** for skirmish and **Multiplayer (Chobby)** for the public multiplayer route.

**[Download](https://github.com/yeojuny/bar-lobby-apple-silicon/releases)** · **[Runtime stack and integrated patches](docs/release-readiness/2026-10-18-v1.0.3/STACK-AND-PATCHES.md)** · **[Sources and build information](docs/release-readiness/2026-10-18-v1.0.3/SOURCE-STATUS.md)**

## Requirements and installation

**Apple Silicon and macOS 27 or later are required.** This ARM64 package does not support Intel Macs. XQuartz installation is not required.

Install with Homebrew:

```sh
brew update
brew install --cask yeojuny/bar/bar-apple-silicon
```

To update an existing installation:

```sh
brew update
brew upgrade --cask yeojuny/bar/bar-apple-silicon
```

Quit BAR normally before updating. The cask installs one `/Applications/BAR.app`; Chobby is included inside it. Both routes share game/map content and graphics libraries. An installation from another distributor is not automatically adopted or removed.

Alternatively, open the ARM64 DMG and drag BAR.app to Applications. The ZIP contains the same app. Game/map content downloads separately; automatic in-app updates are disabled.

### First launch

This build is ad-hoc signed, without Apple Developer ID signing or notarization. macOS may show an unidentified-developer or verification warning. If you downloaded it from this repository and trust it, try opening BAR once, then go to **System Settings → Privacy & Security → Open Anyway** for BAR and confirm **Open**. See [Apple’s instructions](https://support.apple.com/en-us/102445).

If it still won’t launch, you can try restarting your Mac once; this is not a guaranteed fix. If it keeps failing, report the exact error message. Warnings that the app will damage your computer should be investigated rather than bypassed.

### Before playing online

Multiplayer follows the normal BAR Chobby handoff. This is an unofficial build, and approval for the official servers has not been confirmed. Online use may put your account at risk, including a ban. **Contact the BAR moderation team before playing online. Offline skirmishes are recommended for now.**

## Version 1.0.3 healthbar compatibility

Healthbars and their unit tracker now load from the bundled native sources independently of the full widget-handler hash. Dedicated shader paths prevent collisions with the game’s geometry-shader fallback. Their rendering source is preserved. Other widgets keep their existing compatibility checks; future widget API or atlas changes may still need maintenance.

The exact 1.0.3 package has CPU and packaging checks; actual game/GPU/other-Mac testing is pending. [Changes and validation scope](docs/release-readiness/2026-10-18-v1.0.3/README.md).

## Version 1.0.2 defaults (retained)

On its first initialization, this version applies the official **Ultra** preset, switches **AA Off**, sets **Fog Diagonal Lines strength to 0**, and selects the **Spring camera**. Separate one-time markers preserve your later graphics and camera choices. Ordinary fog of war is retained. The overhead camera implementation is unchanged.

This exact 1.0.2 package has offline and packaging checks; it has not received a new in-game or iMac acceptance run. [Detailed scope](docs/release-readiness/2026-10-18-v1.0.2/README.md).

## Metal3 or Metal4

In launcher **Settings**, select **Metal3** (default) or **Metal4** (experimental). The choice applies to both native engine routes on their next launch. Metal4 is not guaranteed to be faster or use less power.

## What this port includes

- Native ARM64 Recoil engines with distinct identities: newer Lobby engine `2026.09.01-24-g01efdf4 master` and public-multiplayer Chobby engine `2026.07.04`.
- NoGS rendering adaptations, VBO/VAO and resource-lifetime fixes, and targeted CPU-work reductions. Historical performance evidence is documented [with its comparison limits](docs/release-readiness/2026-10-15/PERFORMANCE.md).
- Native display/safe-area handling, AI library-loading fixes and downloader/process-lifetime corrections.

## Rendering stack

**ARM64 Recoil OpenGL → Mesa/Zink → Vulkan → MoltenVK → Metal**.

**SDL3** handles native macOS windows, input and events; SDL2 is not the active window backend. X11 is a display system and XQuartz its macOS implementation. This app uses native macOS windows and does not require an X11 server or XQuartz installation. OpenGL-to-Metal translation is handled by the graphics stack, not SDL3.

### Native Cocoa presentation, without XQuartz

The port connects the Cocoa window's **CAMetalLayer** to a local **EGL/Kopper/Zink window-surface path**, then creates a **Vulkan Metal surface** that MoltenVK presents through its swapchain. Ordinary frame presentation does not require a separate engine-side full-frame readback-and-represent pipeline. The renderer still uses OpenGL → Zink → MoltenVK; this is native window-system integration, not a native Metal renderer or a claim of zero driver overhead.

The bridge deliberately defaults to **1x drawable scaling** and handles the target screen's safe area, including notched displays. Resolution/UI policy is separate from presentation buffering and synchronization. [Architecture, source map and reuse checklist](docs/platform-integration/COCOA-EGL-METAL-PRESENTATION.md).

### How an SDL2-shaped engine runs on SDL3

A scoped source compatibility adapter, **SDLRecoilCompat.h**, maps the engine's existing SDL2-style calls to SDL3. The CMake target name **SDL2::SDL2** is retained as an alias whose interface links **SDL3::SDL3**; it does not mean the SDL2 runtime is loaded. Additional platform changes implement Cocoa/EGL integration, input and display handling. This is not a complete general-purpose SDL2 compatibility library, and SDL3 alone does not provide the graphics translation or guarantee higher FPS. [Adapter design and reuse checklist](docs/platform-integration/SDL3-COMPATIBILITY.md).

See the [exact versions, source commits and integrated PR/MR ledger](docs/release-readiness/2026-10-18-v1.0.3/STACK-AND-PATCHES.md).

A separate **Native Metal 4 project will be made public soon**. Its performance relative to this MoltenVK-based version is not yet known; it may be faster or slower.

## Documentation, validation and credits

Detailed [validation scope](docs/release-readiness/2026-10-17-v1.0.1/README.md), [development history](docs/release-readiness/2026-10-17-v1.0.1/DEVELOPMENT-HISTORY.md), and [source/build status](docs/release-readiness/2026-10-18-v1.0.3/SOURCE-STATUS.md) are kept separately. The 1.0.1 source combines macOS compatibility maintenance with eight reviewed SDL/Vulkan/SPIRV-Cross fixes. Version 1.0.1 restores native widget routing for the current game UI handler. The earlier 1.0.0 app release was suspended after a reported display failure. Other-Mac, full multiplayer/replay synchronization and clean-machine acceptance remain separately documented.

Download the matching sources, notices and SHA256SUMS alongside each release. GitHub's automatic launcher-only archive is not the complete application source.

Upstream BAR, bar-lobby, Chobby, Recoil, Mesa, MoltenVK and dependency authors retain their credits and licenses. This software is based in part on the work of the **FreeType Team** ([freetype.org](https://freetype.org)). Original installer/launcher artwork is CC0; game assets and trademarks are not relicensed. This is an independent port. AI tools assisted development and review.

Engine-side optimization work in r57 was informed by [benbreen/RecoilEngine-AppleSilicon](https://github.com/benbreen/RecoilEngine-AppleSilicon/tree/a49a8ecc5265c4dd3f8d0016d90b32e81e22c73b): 250µs fence-wait timeouts, deeper model-upload rings, synchronous-worker QoS requests, and avoidance of unnecessary primitive restart. These ideas were adapted to this port; later lifetime/alignment corrections and the narrower index-safety checks are documented in the [origin and adaptation record](docs/engine-patches/2026-10-17/ORIGIN-AND-PERFORMANCE.md). This attribution concerns those renderer/worker optimizations, not a wholesale transplant of benbreen's readback presentation path or simulation changes.

## Source, integrations and reusable patches

See the [detailed stack and PR/MR ledger](docs/stack-records/2026-10-17/README.md) for exact devel/RC pins, inherited versus selected changes and upstream status. [r73/r75 feature patches](docs/engine-patches/README.md) include attribution, exact base files and scoped local validation.

## Local play observations

I’ve tested 1.0.1 locally on a 14-inch M4 Pro MacBook Pro, including notch handling. The gameplay experience feels close to seamless in my testing. I plan to check it on my iMac too; that verification is still pending.

In early skirmish matches launched from the lobby, I’ve seen over 200 FPS even in Low Power Mode, depending on the map and how much is in view. This is a personal early-game observation, not a late-game guarantee, controlled benchmark or iMac result. See [detailed validation limits](docs/release-readiness/2026-10-17-v1.0.1/README.md).
