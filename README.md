# BAR for Apple Silicon

Beyond All Reason in one **BAR.app**, with bar-lobby and an ordinary **Multiplayer (Chobby)** entry. The native Recoil engines use Mesa/Zink, Vulkan and MoltenVK. Requires **Apple Silicon and macOS 27 or later**.

**v0.15.4-alpha.3 is an unsigned experimental prerelease.** [Downloads and checksums](https://github.com/yeojuny/bar-lobby-apple-silicon/releases/tag/v0.15.4-alpha.3) include a DMG, a ZIP of the same app, matching sources and third-party notices.

## Install and play

1. Download the DMG and drag **BAR.app** to Applications, or extract the ZIP and move the app there.
2. Open BAR. Choose **Multiplayer (Chobby)** for the Chobby multiplayer route. Game and map content downloads separately.
3. In **Settings**, choose **Metal3** or **Metal4 (experimental)**. Metal3 is the default; both engine lanes share the preference. A change applies to the **next native launch**, leaving a running game unchanged. Explicit advanced environment overrides take precedence.

The app has ad-hoc integrity signatures, without an Apple Developer ID or notarization. If macOS blocks it after an opening attempt, Apple's documented per-app option is **System Settings → Privacy & Security → Open Anyway**. See [Apple's instructions](https://support.apple.com/en-us/102445). This is documented guidance, not a clean-machine installation test performed for this release.

Automatic in-app updates are disabled. Replace the app manually or use Homebrew to upgrade. Install through the [personal Homebrew tap](https://github.com/yeojuny/homebrew-bar) with `brew install --cask yeojuny/bar/bar-apple-silicon`. The cask was loaded and checked locally; a local Homebrew installation of alpha.2 passed, while a clean-machine installation has not been tested. For an existing cask installation, run `brew update` followed by `brew upgrade --cask yeojuny/bar/bar-apple-silicon`. Existing installations and shared user data remain under your control; this installer does not remove another distributor's apps.

## Engines and evidence

| Route | Native engine label |
| --- | --- |
| bar-lobby | `2026.09.10-0-g694e9df7`, selected historical development source with local corrections |
| Multiplayer (Chobby) | `2026.07.04`, selected stable-line source with local corrections |

These labels identify the bundled lanes; they do not claim today's newest official engine or universal public-peer compatibility. See [validation scope](docs/release-readiness/2026-10-16-alpha3/README.md).

Historical fixed-scene tests observed roughly **26–27% higher mean FPS** for a later Metal3 stack than the older RUN95 baseline on one machine. Those limited whole-stack samples are not a benchmark of this prerelease. Metal4 was slower than Metal3 in the published R80 comparison; no new FPS gain is claimed for recent functional changes or diagnostic removal. [Full measurements and limits](docs/release-readiness/2026-10-15/PERFORMANCE.md) preserve conditions, slow samples and tradeoffs.

Alpha.2 corrects the current game's bundled-widget loading boundary, macOS fullscreen workarea/cutout handling, GS capability reporting, and font/map-edge/VBO/CUS compatibility. It retains the accepted explicit NoGS presentation, CUS GL4, both renderer choices, CPU submit wait OFF and cost collection OFF. The graphics runtime is unchanged. [Alpha.2 changes and validation scope](docs/release-readiness/2026-10-16/README.md).

Alpha.3 fixes normal launcher quit during content downloading: it stops admitting new writes, terminates only this launcher's registered downloaders, and waits for child/pipe closure and admitted writers before exit. Chobby handoff also drains parent-owned downloads while preserving the detached menu/helper. Actual packaged-app quit during a live automatic download passed with downloader termination before launcher exit 0, no forced test cleanup and zero owned processes. Existing CPU fixtures cover queued writes, error/exit-versus-close ordering, repeated quit, escalation and deadline failure. [Details and verification scope](docs/release-readiness/2026-10-16-alpha3/README.md).

Both alpha.3 Chobby menu checks passed with real helper connections, normal parent exit and natural native/helper cleanup in Metal3 and Metal4. No multiplayer game was run.

Alpha.2's prior native rendering evidence remains scoped to its byte-identical native payload: damaged-unit healthbars, Settings, Ultra/4x MSAA, direct Nano/Energy NoGS and CUS in both renderer modes. Its failed Metal4 downloader cleanup receipt remains a failure; the alpha.3 focused download-quit check does not relabel that earlier game run. No alpha.3 game, FPS, energy, complete effect parity, physical iMac transition, full multiplayer, endurance or clean-machine claim is made. The launcher is alpha.3; the unchanged native compatibility build still displays alpha.2 / R95 + VBO + R4.

## Source and credits

Matching [preferred sources](https://github.com/yeojuny/bar-lobby-apple-silicon/releases/download/v0.15.4-alpha.3/BAR-0.15.4-alpha.3-sources.tar.gz), [notices](https://github.com/yeojuny/bar-lobby-apple-silicon/releases/download/v0.15.4-alpha.3/BAR-0.15.4-alpha.3-notices.tar.gz) and [SHA256SUMS](https://github.com/yeojuny/bar-lobby-apple-silicon/releases/download/v0.15.4-alpha.3/SHA256SUMS) accompany the app. GitHub's automatically generated repository archive alone does not reconstruct the complete native stack. [Source and provenance details](docs/release-readiness/2026-10-16-alpha3/SOURCE-STATUS.md) distinguish source delivery from bit reproduction.

Upstream BAR, bar-lobby, Chobby, Recoil, Mesa, MoltenVK and dependency authors retain their credit and licenses. Original launcher and installer artwork is CC0; the game and trademarks are not relicensed. This software is based in part on the work of the **FreeType Team** ([freetype.org](https://freetype.org)).

This personal fork is independent of upstream projects. AI tools assisted development and review.
