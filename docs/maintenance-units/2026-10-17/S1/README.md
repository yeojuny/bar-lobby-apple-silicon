# S1: four-byte UTF-8 decoding

The SDL decoder now keeps all six payload bits from the second continuation byte of a four-byte UTF-8 sequence. The production line follows SDL commit [57f22e6e](https://github.com/libsdl-org/SDL/commit/57f22e6e43ad7c40912645d6cc76083107b4c367). The same patch adds one regression case to the existing Stdlib test suite.

The regression failed 14 assertions before the production fix. After the fix, 117 focused assertions and 155 existing related string assertions passed (272 total), using the newly built raw SDL library. An applied-code audit accepted this exact two-file patch for source publication. Initial optional FFmpeg test discovery failed; the existing optional test dependency was disabled without changing production compile flags, then the focused build/checks passed.

See [manifest](manifest.json), [validation](validation.json), [applied audit](applied-audit.json), [recipe](recipe.md) and the complete [component-relative patch](change.patch). The manifest pins a public source archive and both file preimages. SDL's existing source license and attribution remain in that archive.

This is a source/raw-component checkpoint. It does not update the public app, release or Homebrew cask. Game, GPU, IME, FPS and multiplayer acceptance were not performed for this isolated string change; no binary export census is claimed.
