# Single-app distribution

BAR.app (`io.github.yeojuny.bar`, version 0.15.4-alpha.1) contains the launcher, distinct bar-lobby/Chobby engine lanes and one shared app-local graphics/audio runtime. Game/maps and mutable settings live outside the signed app. Apple Silicon/macOS 27+ is required.

## Rendering and installation

Settings selects Metal3 (default) or Metal4 (experimental), shared by both lanes and applied at the next native launch. Advanced precedence is `BAR_METAL_BACKEND=METAL3|METAL4`, then `MVK_CONFIG_USE_METAL4=0|1`, then renderer.json, then Metal3. Explicit invalid overrides fail. Renderer caches remain separate. Metal4 requires supporting hardware and is not advertised as faster.

The DMG uses original CC0 charcoal/copper artwork, one BAR.app and an Applications shortcut. The ZIP carries the same frozen app. Both DMG and ZIP were opened independently; all 1,171 app file/link entries, bytes, modes and strict ad-hoc signatures matched inventory `6f8908ed…`. The actual Finder DMG layout showed the original artwork, one BAR.app and Applications shortcut at the configured positions. No privileged helper, source archive inside the app, automatic game launch or security-bypass hook is installed.

This experimental build has ad-hoc integrity signatures without Developer ID/notarization. [Apple documents](https://support.apple.com/en-us/102445) a per-app Privacy & Security → Open Anyway option after an attempted launch. That is documented guidance, not a clean-machine approval path validated by this release. System security/quarantine settings are not modified by the installer.

## Updates and Homebrew

Automatic app updates are disabled. Manual replacement owns manual-install upgrades. Install through the [personal Homebrew tap](https://github.com/yeojuny/homebrew-bar) with `brew install --cask yeojuny/bar/bar-apple-silicon`. The cask was loaded and checked locally; a clean-machine Homebrew installation has not been tested. A personal cask must install the identical versioned DMG by exact SHA, require ARM64/macOS 27+, declare one `app "BAR.app"`, and retain user state. It must not remove another distributor's apps or use a quarantine-removal hook. Migration from an existing conflicting cask is user-controlled.

The original builder asset lock `f65dc1b1…` remains historical. The current launcher build uses the cleaned `fc0a4c9a…` inputs, omitting five unused pkgconfig files and empty metadata directories. Selected native binaries retain build/source-root strings; this release makes no whole-app zero-personal-path claim. Sanitized source/public metadata excludes private environment/session data.

See [Homebrew's Cask Cookbook](https://docs.brew.sh/Cask-Cookbook) for declarative version/SHA/artifact/architecture requirements. Actual final checks are recorded in [validation scope](README.md); source/notices accompany the corresponding binary release.
