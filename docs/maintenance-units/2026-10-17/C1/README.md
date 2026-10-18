# C1: negative zero in precise MSL helpers

The complete [patch](change.patch) applies Cross [300681bb](https://github.com/KhronosGroup/SPIRV-Cross/commit/300681bbcb8365a8d1eacdacdbdd0249bbf1d6b1) on the public #2687 port base: four production string replacements and six official expected-output files. Typed negative-zero fma addends/accumulator seeds are retained without replacing prior aliasing logic.

The translator was relinked against the actual changed MSL archive. All six official C1 outputs plus two existing alias outputs match byte-exactly; SPIR-V validation ran. The native build preserves142 production compile commands,4482 public export names, dependencies and install name. Metal compilation, GPU arithmetic/UUID queries, BAR shader reachability and app/game/FPS/MP acceptance were not performed.

[manifest](manifest.json) and [recipe](recipe.md) embed the complete canonical payload, SHA256 `f52facf761992e8d64a3e3c18bfa108565364fb5416b5708b5aeec5e3d26bb3a`, and explicit `-DMVK_GIT_REV=f52facf7` derivation. [validation](validation.json) and [applied audit](applied-audit.json) bind actual source/tool/library checks. Existing apps, tags, Release, Homebrew and V1 are not changed. Separate accepted SDL S1/S2 and Loader L5/L4 source chains are preserved.
