# BAR for Apple Silicon

Beyond All Reason in one **BAR.app**, with bar-lobby for skirmish and **Multiplayer (Chobby)** for the existing public multiplayer route. This independent port uses native ARM64 Recoil engines with OpenGL → Mesa/Zink → Vulkan → MoltenVK → Metal. **Apple Silicon and macOS 27 or later are required.** Apple Silicon iMac, Mac mini and Mac Studio are test targets; Intel Macs are not supported by this ARM64 package. The native runtime uses **SDL3** for window creation, input and events, with native macOS window integration. SDL2 is not the active window backend. **X11/XQuartz installation is not required**: X11 is the display system, and XQuartz is its macOS implementation. The app does not start an X11 server or use XQuartz for its windows.

[Download 0.17.0-candidate.5](https://github.com/yeojuny/bar-lobby-apple-silicon/releases/tag/v0.17.0-candidate.5) — experimental maintenance prerelease with corrected macOS hardware information for Chobby analytics, updated Options compatibility recognition and quieter diagnostic output, on top of the preceding Lobby/engine and AI-loading fixes. The previous [0.15.4-alpha.3](https://github.com/yeojuny/bar-lobby-apple-silicon/releases/tag/v0.15.4-alpha.3) remains available for rollback.

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

## Runtime versions and patches

See the [exact stack and integrated PR/MR ledger](docs/release-readiness/2026-10-17-candidate5/STACK-AND-PATCHES.md) for versions, source commits, already-merged upstream work, locally integrated open PRs, and local corrections. SDL3 is the active window backend and X11/XQuartz is not required.

## What changed

| Route | Source and exact engine identity |
| --- | --- |
| bar-lobby | Lobby `e2c45c8fcb5461acb3232539493be15cd0fda7ec`; Recoil `01efdf43121dfd40d105649ef7eb89a8804662d9` with local macOS integration; sync name `2026.09.01-24-g01efdf4 master` |
| Multiplayer (Chobby) | Official multiplayer engine identity `2026.07.04`, with macOS display/linking corrections; it is not replaced by the newer Lobby engine |

The integration includes newer content/session/Tachyon and party/lobby flows, replay/result/history structures, 80-byte model vertex/color support and SDL3 integration. Both native lanes retain the accepted Lua NoGS/CUS presentation, numeric and SHIELD policy, and VBO ownership/fence safeguards. The shared graphics translation runtime remains unchanged from alpha.3; this is separate from any native Metal4 renderer project.

Candidate.5 maintenance changes:

- Both native engines supply a real macOS CPU field and a safe `CPU; RAM` string, fixing the missing-delimiter input that caused the official Chobby analytics error. The descriptive hardware string and its derived system-information hash can change; engine sync identities and simulation/numeric policy are unchanged. The official analytics parser itself is unchanged.
- The Options adapter recognizes the current official recursive duplicate guard without modifying that correct implementation; unknown or incomplete shapes still fail closed.
- Successful VBO delegation spam and a fixed feasibility warning were removed; detailed bridge diagnostics require debug logging. VBO/NoGS/CUS and display/safe-area functions remain intact. No measured FPS or energy gain is claimed.
- The launcher skips six obsolete default keys on macOS while retaining saved user values. A Linux-only disk lookup is avoided with the same conservative result. Official Chobby-owned deprecated writes and map/resource warnings can still occur.

Earlier integration fixes retained here:

- Target-screen matching for fullscreen transitions, plus one-time Chobby display migration that preserves subsequent user choices. Screen selection uses the actual display, not a fixed MacBook resolution or notch assumption.
- A single in-flight Chobby launch so concurrent requests do not race the configuration backup or start duplicate preparation.
- Private JsonCpp symbols inside BARb/CircuitAI on both lanes, preserving their C interface and AI logic. Chobby links through the configured Apple linker to avoid invalid Mach-O alignment produced by an older third-party linker.
- Owned downloader and checksum close/drain, including normal quit during download and holding map checksums while the game owns the shared cache/log.

Normal sound and advanced map shading defaults are enabled. A private manual-test profile had retained disabled settings and was corrected locally; that profile is not distributed. Upgrading does not forcibly overwrite saved user preferences. If a retained profile still has silent audio or missing world-space radar previews, check its sound and advanced map shading settings. The radar preview requires map-depth output; minimap visibility alone does not prove that path is enabled.

## Validation and limits

Candidate.5 passed **859 launcher unit tests**, Node/Web types, **144 existing Lua compatibility cases**, **32 VBO checks**, four native hardware cases with sanitizers, four default-settings cases, all **52 packaged native loader files**, and strict ad-hoc signature validation. DMG/ZIP contents are compared with the frozen app. Existing AI libraries and the shared graphics runtime are byte-identical to candidate.4.

**Candidate.5 has not had a fresh app/menu/game run.** Historical candidate.4 AI loads/manual play and earlier scenes/menu checks apply to those preceding binaries; they are not fresh candidate.5 gameplay proof. The earlier other-Mac log identified the analytics input error but did not include an exact app hash. See [validation scope](docs/release-readiness/2026-10-17-candidate5/README.md).

Testing on another physical Mac, full public multiplayer/cross-machine replay synchronization, CircuitAI gameplay, endurance, clean-machine installation and new FPS/energy comparisons remain pending. No Metal4-specific minimap defect is established: earlier captures did not control Fog of War/LOS state and draw timing. No complete rendering-parity claim is made.

Historical fixed-scene runs observed roughly 26–27% higher mean Metal3 FPS for a later stack than the older RUN95 baseline on one machine. These whole-stack samples do not benchmark this release or attribute the gain to every small optimization. See [measurements and limits](docs/release-readiness/2026-10-15/PERFORMANCE.md).

## Corresponding sources and credits

Download the release's **sources.tar.gz**, **notices.tar.gz** and **SHA256SUMS** alongside the app. The source companion includes current launcher and both populated engine trees, generated presentation headers, overlays and shared runtime sources. GitHub's automatic launcher-only archive cannot reconstruct the full app. [Source and build limits](docs/release-readiness/2026-10-17-candidate5/SOURCE-STATUS.md) distinguish source correspondence from clean-machine reproducibility.

Upstream BAR, bar-lobby, Chobby, Recoil, Mesa, MoltenVK and dependency authors retain their credit and licenses. Original installer/launcher artwork is CC0; game assets and trademarks are not relicensed. This software is based in part on the work of the **FreeType Team** ([freetype.org](https://freetype.org)). This personal fork is independent of upstream projects. AI tools assisted development and review.
