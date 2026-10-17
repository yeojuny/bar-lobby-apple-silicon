# BAR for Apple Silicon

Play **Beyond All Reason on Apple Silicon Macs** in one **BAR.app**: use **bar-lobby** for skirmish and **Multiplayer (Chobby)** for the public multiplayer route.

**[Download](https://github.com/yeojuny/bar-lobby-apple-silicon/releases)** · **[Runtime stack and integrated patches](docs/release-readiness/2026-10-17-candidate5/STACK-AND-PATCHES.md)** · **[Sources and build information](docs/release-readiness/2026-10-17-candidate5/SOURCE-STATUS.md)**

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

The app is ad-hoc signed, without Apple Developer ID signing or notarization. If macOS blocks opening, follow [Apple's per-app Open Anyway instructions](https://support.apple.com/en-us/102445).

## Metal3 or Metal4

In launcher **Settings**, select **Metal3** (default) or **Metal4** (experimental). The choice applies to both native engine routes on their next launch. Metal4 is not guaranteed to be faster or use less power.

## What this port includes

- Native ARM64 Recoil engines with distinct identities: newer Lobby engine `2026.09.01-24-g01efdf4 master` and public-multiplayer Chobby engine `2026.07.04`.
- NoGS rendering adaptations, VBO/VAO and resource-lifetime fixes, and targeted CPU-work reductions. Historical performance evidence is documented [with its comparison limits](docs/release-readiness/2026-10-15/PERFORMANCE.md).
- Native display/safe-area handling, AI library-loading fixes and downloader/process-lifetime corrections.

## Rendering stack

**ARM64 Recoil OpenGL → Mesa/Zink → Vulkan → MoltenVK → Metal**.

**SDL3** handles native macOS windows, input and events; SDL2 is not the active window backend. X11 is a display system and XQuartz its macOS implementation. This app uses native macOS windows and does not require an X11 server or XQuartz installation. OpenGL-to-Metal translation is handled by the graphics stack, not SDL3.

See the [exact versions, source commits and integrated PR/MR ledger](docs/release-readiness/2026-10-17-candidate5/STACK-AND-PATCHES.md).

A separate **Native Metal 4 project will be made public soon**. Its performance relative to this MoltenVK-based version is not yet known; it may be faster or slower.

## Documentation, validation and credits

Detailed [validation scope](docs/release-readiness/2026-10-17-candidate5/README.md), [development history](docs/release-readiness/2026-10-17-candidate5/DEVELOPMENT-HISTORY.md), and [source/build status](docs/release-readiness/2026-10-17-candidate5/SOURCE-STATUS.md) are kept separately. The unreleased maintenance build has CPU/package checks only; other-Mac, full multiplayer/replay synchronization and clean-machine acceptance remain pending.

Download the matching sources, notices and SHA256SUMS alongside each release. GitHub's automatic launcher-only archive is not the complete application source.

Upstream BAR, bar-lobby, Chobby, Recoil, Mesa, MoltenVK and dependency authors retain their credits and licenses. This software is based in part on the work of the **FreeType Team** ([freetype.org](https://freetype.org)). Original installer/launcher artwork is CC0; game assets and trademarks are not relicensed. This is an independent port. AI tools assisted development and review.
