# BAR for Apple Silicon

Beyond All Reason in one **BAR.app**, with bar-lobby for skirmish and **Multiplayer (Chobby)** for the existing public multiplayer route. This independent port uses native ARM64 engines with Mesa/Zink → Vulkan → MoltenVK → Metal. **Apple Silicon and macOS 27 or later are required.** Apple Silicon iMac, Mac mini and Mac Studio are test targets; Intel Macs are not supported by this ARM64 package. XQuartz is not required.

[Download 0.17.0-candidate.4](https://github.com/yeojuny/bar-lobby-apple-silicon/releases/tag/v0.17.0-candidate.4) — experimental prerelease with the newer Lobby/engine integration, fullscreen/Chobby transition corrections and BARb/CircuitAI loading fixes. The previous [0.15.4-alpha.3](https://github.com/yeojuny/bar-lobby-apple-silicon/releases/tag/v0.15.4-alpha.3) remains available for rollback.

## Install or update

With Homebrew:

```sh
brew update
brew install --cask yeojuny/bar/bar-apple-silicon
```

If this same cask is already installed, use:

```sh
brew update
brew upgrade --cask yeojuny/bar/bar-apple-silicon
```

Quit BAR normally before updating. The cask installs one `/Applications/BAR.app`; Chobby is an entry inside it, not a second app. Two distinct engines are included because their multiplayer identities differ; game/map content is shared rather than duplicated per launcher. A BAR.app installed by another distributor is not automatically adopted or deleted.

Alternatively download the ARM64 DMG, open it and drag BAR.app to Applications. The ZIP contains the same app. Game and map content downloads separately. Automatic in-app updates are disabled.

The app has ad-hoc integrity signatures, **without Apple Developer ID signing or notarization**. If macOS blocks an opening attempt, use the per-app option **System Settings → Privacy & Security → Open Anyway**, following [Apple's instructions](https://support.apple.com/en-us/102445). Do not disable system security globally.

## Metal3 or Metal4

In launcher **Settings**, choose **Metal3** or **Metal4 (experimental)**. Metal3 is the default. The preference applies to both engine lanes on the next native launch; an explicit environment override takes precedence. CPU submit wait and custom cost collection remain OFF. Metal4 is not guaranteed to be faster or use less power.

## What changed

| Route | Source and exact engine identity |
| --- | --- |
| bar-lobby | Lobby `e2c45c8fcb5461acb3232539493be15cd0fda7ec`; Recoil `01efdf43121dfd40d105649ef7eb89a8804662d9` with local macOS integration; sync name `2026.09.01-24-g01efdf4 master` |
| Multiplayer (Chobby) | Official multiplayer engine identity `2026.07.04`, with macOS display/linking corrections; it is not replaced by the newer Lobby engine |

The integration includes newer content/session/Tachyon and party/lobby flows, replay/result/history structures, 80-byte model vertex/color support and SDL3 integration. Both native lanes retain the accepted Lua NoGS/CUS presentation, numeric and SHIELD policy, and VBO ownership/fence safeguards. The shared graphics translation runtime remains unchanged from alpha.3; this is separate from any native Metal4 renderer project.

This release also includes:

- Target-screen matching for fullscreen transitions, plus one-time Chobby display migration that preserves subsequent user choices. Screen selection uses the actual display, not a fixed MacBook resolution or notch assumption.
- A single in-flight Chobby launch so concurrent requests do not race the configuration backup or start duplicate preparation.
- Private JsonCpp symbols inside BARb/CircuitAI on both lanes, preserving their C interface and AI logic. Chobby links through the configured Apple linker to avoid invalid Mach-O alignment produced by an older third-party linker.
- Owned downloader and checksum close/drain, including normal quit during download and holding map checksums while the game owns the shared cache/log.

Normal sound and advanced map shading defaults are enabled. A private manual-test profile had retained disabled settings and was corrected locally; that profile is not distributed. Upgrading does not forcibly overwrite saved user preferences. If a retained profile still has silent audio or missing world-space radar previews, check its sound and advanced map shading settings. The radar preview requires map-depth output; minimap visibility alone does not prove that path is enabled.

## Validation and limits

The latest source passed **859 unit tests**, Node/Web type checks and existing sensor fixtures. All **52 packaged native files** passed loader validation; both BARb and CircuitAI loaded with their C entry points on both lanes. Installer contents are checked against the frozen app and its strict ad-hoc signature. The user confirmed the local manual session working before requesting this release for another Mac.

That human confirmation applies to the manually played intermediate app. The final candidate additionally contains an Apple-linker-only Chobby engine relink; its loader and exact sync-version checks passed, but that final relink was not graphically rerun. Earlier candidate.1 Metal3/Metal4 scenes and Chobby menu checks remain historical evidence, not fresh final-binary gameplay proof. See [validation scope](docs/release-readiness/2026-10-17-candidate4/README.md).

Testing on another physical Mac, full public multiplayer/cross-machine replay synchronization, CircuitAI gameplay, endurance, clean-machine installation and new FPS/energy comparisons remain pending. No Metal4-specific minimap defect is established: earlier captures did not control Fog of War/LOS state and draw timing. No complete rendering-parity claim is made.

Historical fixed-scene runs observed roughly 26–27% higher mean Metal3 FPS for a later stack than the older RUN95 baseline on one machine. These whole-stack samples do not benchmark this release or attribute the gain to every small optimization. See [measurements and limits](docs/release-readiness/2026-10-15/PERFORMANCE.md).

## Corresponding sources and credits

Download the release's **sources.tar.gz**, **notices.tar.gz** and **SHA256SUMS** alongside the app. The source companion includes current launcher and both populated engine trees, generated presentation headers, overlays and shared runtime sources. GitHub's automatic launcher-only archive cannot reconstruct the full app. [Source and build limits](docs/release-readiness/2026-10-17-candidate4/SOURCE-STATUS.md) distinguish source correspondence from clean-machine reproducibility.

Upstream BAR, bar-lobby, Chobby, Recoil, Mesa, MoltenVK and dependency authors retain their credit and licenses. Original installer/launcher artwork is CC0; game assets and trademarks are not relicensed. This software is based in part on the work of the **FreeType Team** ([freetype.org](https://freetype.org)). This personal fork is independent of upstream projects. AI tools assisted development and review.
