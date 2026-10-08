# Restore and verify the recorded sources

This is a source restoration guide. It does not claim a complete clean-Mac application build: the lobby, content, retained SDL/Loader packaging inputs, SDK installation and signing workflow are separate. Build invocation evidence in this record uses `${WORKSPACE}` in place of the original private absolute root.

1. Obtain each official repository at its exact `base_commit` in `source-record.json`. For engine submodules and MVK external dependencies, use the explicitly recorded commits rather than floating heads or the baseline repository's default dependency revisions.
2. Run `shasum -a 256 -c SHA256SUMS` from this record directory.
3. Apply the primary patches from each repository root:

```sh
git -C /path/to/RecoilEngine apply --check /path/to/record/patches/engine-r80.patch
git -C /path/to/RecoilEngine apply /path/to/record/patches/engine-r80.patch

git -C /path/to/mesa apply --check /path/to/record/patches/mesa-r80.patch
git -C /path/to/mesa apply /path/to/record/patches/mesa-r80.patch

git -C /path/to/MoltenVK apply --check /path/to/record/patches/mvk-r80.patch
git -C /path/to/MoltenVK apply /path/to/record/patches/mvk-r80.patch
```

4. Apply dependency patches **inside each dependency checkout**. `checkout_path` is relative to its engine or MVK parent. The patch filenames are listed under the corresponding component in `source-record.json`:

| Parent | Dependency checkout | Patch |
|---|---|---|
| RecoilEngine | `AI/Skirmish/BARb` | `engine-dep-AI_Skirmish_BARb-r80.patch` |
| RecoilEngine | `AI/Skirmish/CircuitAI` | `engine-dep-AI_Skirmish_CircuitAI-r80.patch` |
| RecoilEngine | `rts/lib/streflop` | `engine-dep-rts_lib_streflop-r80.patch` |
| MoltenVK | `External/SPIRV-Cross` | `mvk-dep-SPIRV-Cross-r80.patch` |

Dependencies recorded with `no changes` still need their pinned commits but no patch. Engine AI dependency patches are retained compile/assembly compatibility inputs, not new AI optimization work. The streflop patch removes an obsolete macOS `hypot` shim; it is part of the inherited checkpoint, not a newly proposed numerical change for multiplayer.

5. Check changed-file bytes against each `target_sha256`. For symlinks, hash the link target string; for regular files, hash the file bytes. The patch is the source of file modes; hashes alone do not encode executable/symlink mode.
6. Use `build-inputs.json` for the actual component configuration and binary identity. Metal4 was built with `MVK_BUILD_METAL4_FOUNDATION=ON` and selected at runtime with `MVK_CONFIG_USE_METAL4=1`; Metal3 remains separately testable. `MVK_USE_METAL_PRIVATE_API=ON` is part of the historical build inputs. Merely changing an SDK or Metal language version does not enable this command backend.

## Optional reviewed font follow-up

Keep the R80 checkout first if reproducing its measured binaries. To stage the later font candidate, apply `r81-engine-font.patch` in the patched RecoilEngine root. Apply `r81-runtime-fontconfig.patch` in the **bundle's `bundled-assets` root**, whose original `runtime/fontconfig/fonts.conf` hash must match `r81-font-candidate.json`.

These font patches were independently reviewed but not integrated into a tested app. Applying them changes the source state beyond R80. They must not inherit R80's binary hashes or performance claims. Actual engine build, shared bundle config integration, asset-lock update, signing and app/UI validation remain necessary.
