# Historical engine source consolidation — 2026-10-22

The user authorized retiring duplicate files in four October 16–17 engine/launcher backup groups after preserving common source, stage deltas and minimal reproduction inputs, verifying GitHub recovery, and independent review. This checkpoint is not a product release.

## What remains locally

- The complete macos-maintenance common Lobby, Chobby and launcher source roots remain in their existing locations.
- Every unique older file, all original Markdown, both shallow Git databases, local-only files and the two top-level CPU fixtures remain.
- The eleven old launcher files used as canonical copies by checkpoint 61f3f876d22760464ac92a7c8bbe53dd1c8e94b4 remain at the paths recorded there.
- Current applications, active source/builds, Run95/R88/alpha.3 milestones, previous release rollbacks and the separately held recent thirteen apps are not selected. No game, product build, benchmark or installation occurs.

## Stage history and exact deltas

The Lobby upgrade crosses from the 694e9df7 engine lineage to 01efdf4, while the Chobby 2026.07.04 lineage remains separate. Fullscreen/duplicate-launch repair, JsonCpp AI linkage isolation, and subsequent maintenance are distinct states. A current source tag alone does not reconstruct these states. Existing maintenance and r73/r75 public records remain separate evidence.

Each deltas JSON lists files whose content/mode differs from its common base, and files present only in the newer base that must be absent in the older state. The complete catalog also records each file timestamp and directory mode. No equal-sized or same-named file is assumed identical.

| Older snapshot | Common base | Changed/old-only files | Base-only paths | Duplicate files selected | Logical bytes |
|---|---|---:|---:|---:|---:|
| upgrade-lobby | common-lobby | 1308 | 187 | 7582 | 165877888 |
| upgrade-launcher | common-launcher | 306 | 297 | 749 | 60503771 |
| fullscreen-lobby | common-lobby | 3 | 0 | 9038 | 186944431 |
| fullscreen-chobby | common-chobby | 4 | 0 | 8772 | 183661345 |
| jsoncpp-lobby | common-lobby | 2 | 0 | 9039 | 186969951 |
| jsoncpp-chobby | common-chobby | 3 | 0 | 8773 | 183686930 |

43,953 identical regular files totaling 967,644,316 logical bytes are selected. This is not physical space reclaimed. APFS clones can share storage. All source directory roots and retained entries remain; old whole-tree rollback hashes apply only after explicit materialization.

## Public recovery

From a checkout of this directory, run `python3 fetch-inputs.py` to download the checksum-pinned v1.0.3 source asset and the earlier immutable backup payloads. The helper verifies the whole source asset and extracts only the three named source archives. It verifies every external file checksum and refuses to overwrite nonmatching inputs.

Then run `python3 restore.py --snapshot fullscreen-lobby --destination /new/empty/directory`. Choose any snapshot ID listed in manifest.json. Add `--selected-only` to restore only the duplicate files selected for removal. Destinations must not exist; existing backups are never overwritten. Source is treated as bytes and is not built or executed.

The result is explicitly the public projection of the selected snapshot. Personal absolute paths, source maps, OS metadata and credential configuration are excluded from remote payloads and retained at their original local paths. The catalog marks each excluded entry as local-only. The shallow Git databases are also retained locally and are not reconstructed by this helper. Local-only entries must be overlaid from their retained copies for a full non-Git file inventory. HEAD or .git alone does not encode dirty/untracked launcher contents.

The catalog records the complete nine snapshot file inventories and directory modes. The remote verification receipt checks all public files in all nine snapshots, including every file selected for retirement. New object packs contain only content not already available from the pinned public source archives or previous checkpoint. Exact per-file hashes, rather than release names alone, determine reuse.

## Reproduction materials and limitations

The two focused fixture inputs remain at their original paths and have their identities recorded in the catalog. Existing external CPU fixtures, historical preimages, failure logs, reports and patches remain outside the deletion set. No claim is made that a historical native build, GPU workload or multiplayer session has been rerun. Historical sparse app/build paths already retired in earlier cleanups are not recreated by this checkpoint.

File bytes, Unix mode and mtime are portable recovery fields. Inodes, APFS sharing, system provenance, ownership and creation timestamps are not synthesized. Existing source licenses continue to apply; common source archives include their license material.

Prior public evidence: [engine patches and stack](https://github.com/yeojuny/bar-lobby-apple-silicon/tree/bec25b3dfb13350c06a42422b9a88004a5b67c57/docs/engine-patches/2026-10-17), [maintenance units](https://github.com/yeojuny/bar-lobby-apple-silicon/tree/1429cc0c10e54549f13406f03922ec32cda181e0/docs/maintenance-units/2026-10-17). These do not replace this exact snapshot mapping.

Publication records preservation intent, not completion of local deletion. A later RESULT.md records the actual selected removal and observed disk-space change after verification and independent review.
