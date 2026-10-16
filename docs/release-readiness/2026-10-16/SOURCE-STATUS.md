# Alpha.2 source correspondence

The release companion `BAR-0.15.4-alpha.2-sources.tar.gz` is SHA-256 `a668da2773fc14d5aedab061049d5b26cd10022c218f1d016d666ab527068925`. The notice companion is `ad8b1c63c0656b8e21d088f88d4d8b9fc23b429236344e55a4cc78f5bcccd827`. Validate them using the attached SHA256SUMS.

The source companion contains eleven component archives, complete Lobby and Chobby source snapshots, the exact generated presentation headers, renderer overlays/profile inputs and portable build support. Its manifest SHA-256 is `22482f1e78173f3c450e3d9bf92116c59c704d0d90754edf09981c4a86c411dd`. The launcher archive is `7822d538b915cfc4543e32ebc52a7b8c2f40c44be302c2eec03c2d800354b9c1`.

All 643 non-README launcher source entries match the publication tree exactly. Public README and release-readiness documents are explicit metadata-only differences from the archived launcher snapshot. The Git repository does not contain the two full native source trees or all dependency sources; use the companion rather than only GitHub's automatic repository archive.

The exported existing generator reproduces both compiled presentation headers from the portable pins and exact overlay source. Some retained CPU fixture drivers still refer to their original historical workspace layout; the complete historical suite is not claimed to run standalone after extraction. Build notes disclose provider prerequisites, native cached-link flags and FreeType header/runtime association. Matching preferred source delivery does not claim bit-for-bit reproduction of the app or every system-provider binary.

The shared translation runtime is unchanged from alpha.1. The earlier dependency/source-provider limitations and third-party credits remain documented in the historical 2026-10-15 source status and the new companion build notes.
