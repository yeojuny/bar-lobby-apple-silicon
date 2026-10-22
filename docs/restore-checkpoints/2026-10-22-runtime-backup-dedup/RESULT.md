# Runtime backup cleanup completed — 2026-10-22

100 previously disclosed duplicate files were removed after independent review, GitHub publication, anonymous readback of every payload, and final local preservation checks. Thirty distinct file variants remain locally and in this Git history.

| Material | Removed copies | Logical bytes |
| --- | ---: | ---: |
| R92 SPIRV-Cross object files | 14 | 29,725,920 |
| Earlier Vulkan header duplicates | 46 | 125,029,305 |
| Release-preparation launcher duplicates | 40 | 177,552,776 |
| Total | 100 | 332,308,001 |

Available space increased by 324,456,448 bytes from immediately before deletion through final verification. Across the full task, including preparation of Git backup objects, the observed net increase was 261,787,648 bytes. These are whole-volume observations, not isolated causal reclaim measurements.

Current apps and builds, all engine/app backup trees, tests, failure evidence, Markdown/patches, and the excluded source-map pair were retained. Twenty-five current/remaining tree metadata digests and 247 source/test/canonical hashes matched before and after, as did the real launcher HEAD/index/status/diff. No product build, app/game launch or GPU test was performed.

The separately published recent experiment-app checkpoint remains available, but its 13 local apps and 42 local payload files remain held for testing before a retirement decision. This operation did not remove them.

See [the original itemized disclosure](README.md), [the exact recovery map](manifest.json), [the result receipt](completion.json), and [the recovery helper](restore.py). Recovery materializes only the selected files into a new destination; it does not recreate historical files retired by earlier cleanups.
