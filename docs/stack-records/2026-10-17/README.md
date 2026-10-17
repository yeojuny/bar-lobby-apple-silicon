# Stack, integrations and attribution — 2026-10-17

This detailed ledger accompanies the existing public sources. It separates the exact component versions, external changes already inherited by those versions, selected extra PR/MR commits, our adaptations and the checks actually performed.

- [Exact components, development snapshots, every engine-base submodule and dependency/source catalogs](COMPONENTS.md)
- [External PR/MR integration ledger, exact included commits and current upstream status](INTEGRATIONS.md)
- [Why some versions are ahead or behind; both engines checked](VERSION-SELECTION.md)
- [Local changes, provenance, costs and validation boundaries](LOCAL-CHANGES.md)
- [Excluded/deferred proposals and historical changes](EXCLUSIONS.md)
- [r73/r75 feature patch series, exact base files and CPU evidence](../../engine-patches/2026-10-17/README.md)

## Product route

`BAR.app → bar-lobby / Chobby → Recoil OpenGL → Mesa/Zink → Vulkan Loader → MoltenVK → Metal`

SDL3/Cocoa/EGL handles native window integration; it is not an SDL_GPU renderer. This packaged route does not require an X11 server or XQuartz. Metal3 remains the default; Metal4 is experimental. CPU submit wait and custom cost collection remain OFF. Custom MoltenVK diagnostic collection is compiled out while functional resource accounting remains. A separate native Metal4 project is independent of this stack and is not covered by this publication.

## Release identity

Public app/Homebrew: **0.17.0-candidate.4**, source tag `c313b26c95fbe81b3dc8f31aaed8a7f46d185fc6`. Locally installed alpha.3 and ordinary workspace Run95 are separate retained artifacts. Candidate.5 has unpublished maintenance/source work; final app publication and Homebrew update remain held for version naming. A newer documentation commit does not update an installed app or prove that a new app passed gameplay checks.

## Reading “all integrations” accurately

The tables enumerate all individually recorded selected external changes in the retained Run95 intake and later accepted stack additions, with the inherited ARM64 foundations and donor attribution. Exact base commits include the rest of each upstream project's ancestry; links and full corresponding-source archives preserve that history without relabeling every upstream commit as a new local optimization. The complete patch/lock/source inventories are available alongside the readable tables. An investigated proposal is not automatically included; exclusions are listed separately. Dependency package entries include dev/build-only items with their flags.

“Integrated locally”, “locally reviewed/tested”, “upstream approved” and “upstream merged” are different facts. This publication creates no official upstream approval, and a later upstream merge does not replace the exact older commit in our frozen app. No individual PR has a demonstrated FPS benefit merely because it is listed here.
