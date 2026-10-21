# A/B/C retention and rollback from retained C — 2026-10-20

This records the human choice to retain local **C**, while managing **A/B/C** through GitHub. It does not itself delete A/B. The owner will inspect the separate certification before removing only its two exact local app roots. Current products/source/builds/profiles, stable/milestone apps and all previous checkpoints remain unchanged.

| Role | State | Local retention intent |
|---|---|---|
| A | C-REG before drawable-size | Retire only after certification |
| B | A + live window/drawable size query | Retire only after certification |
| C | B + typed Buffer callers | Retain |

All three display1.0.3 as local cumulative1.0.4 experiments. `versions.json` preserves their original immutable forward-restoration commits and the12-run comparison commit. `rollback-manifest.json` adds an independent **C→A (5files)** and **C→B (3files)** path. No stableRelease/Homebrew/master/tag or source implementation changes are included.

## Payload coverage

The A/B old MVK and signature files already exist as immutable Git blobs and are referenced at parent commit `87d12b908edfc2b27af7b47b0ae1cd81403d870c`. Their blob IDs, SHA256, sizes and modes are bound and their public bytes are rechecked. **A's two old signed engines were not present as raw immutable Git blobs**; the previous initial engine restoration involved patches against the public1.0.3 app. To remove that externalRelease dependency for rollback from retainedC, exactly those two signed engine files (34,959,808 and31,275,968bytes) are added here. Each is below100MB. Shared identical payloads are deduplicated; no full app or large app archive is uploaded.

With retainedC and this GitHub checkpoint, A/B recovery requires **no GitHub Release, source build, current-source edit or old local A/B copy**. Existing forward restoration of C remains available unchanged through [typed Buffer](../2026-10-20-typed-buffer-callers/README.md), [drawable-size](../2026-10-20-drawable-size/README.md), [C-REG](../2026-10-20-c-reg/README.md) and [original basis](../../README.md). The forward route's original public1.0.3 dependency is unchanged; it is not needed by the new C→A/B route.

## Restore to a fresh path only

Check out this checkpoint's immutable commit identified in the publisher certification. It includes `payloads/`, manifest and inventories. Python3.9+ and macOS are required; curl downloads reused public immutable blobs. Run:

```sh
python3 restore-from-c.py --base-app /path/to/retained-C/BAR.app --target A
python3 restore-from-c.py --base-app /path/to/retained-C/BAR.app --target A --out /NEW/path/A/BAR.app
python3 restore-from-c.py --base-app /path/to/retained-C/BAR.app --target B --out /NEW/path/B/BAR.app
```

No `--out` means verify retainedC, fetch/check required rollback bytes and verify the virtual inventory only. With a new output, the helper validates the entire1194-entry C inventory including regular-file modes and symlink targets/modes, resolves and hashes rollback bytes, copies C into a **nonexistent fresh destination**, writes only the overlay there, checks all1194 target entries and strict nested code signature. It never modifies C in place, overwrites an existing app, signs, launches or installs. Quarantine/Finder metadata and arbitrary extended attributes are outside the exact-content claim.

The publisher verified actual A/B/C originals against their full inventories and performed read-only strict signature inspection. Applying the declared overlays to C's inventory matches A/B's originals in memory,1194 entries each. This is a virtual-overlay/byte/signature certification, **not an executed full app reconstruction or new gameplay acceptance**. The publisher makes no full-app copy, game/build/test/install/cleanup or source/settings change.

Small-n/hidden-fullscreen/OS-load caveats and previous unresolved Metal3 timestamp and sampled-exit failures remain as recorded. A/B retirement does not erase their frozen source/patch/performance/failure records or qualify every runtime path. Automation remains PAUSED. The owner's before.json and original inventories are read-only and unchanged; actual user profile contents are not uploaded.
