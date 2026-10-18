# Exact 1.0.1 repair

The patch records source-lane paths under $WORKSPACE. Apply only the matching native-lane hunks to the corresponding complete engine archive; compare exact pre/post hashes in source-correspondence.json. Native complete postimages under sources/ are authoritative. The launcher version files are committed at repository root. Do not apply both engine-lane patches to a single source tree.

Build each engine with VERSION_ADDITIONAL=BAR-1.0.1 using its retained CMake/Ninja configuration. Preserve the public sync identity and original compiler/numeric/link flags. Reproduce the generated version header from its included template-values record. The existing fixture and its current141304-byte handler are included in the source companion's build-support layout; production source/header pins and original rejected-byte checks are retained. No extra graphics/widget code is changed.
