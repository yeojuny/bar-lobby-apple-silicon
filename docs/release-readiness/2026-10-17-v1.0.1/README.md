# BAR for Apple Silicon 1.0.1

This release contains the eight reviewed maintenance units plus a narrow native compatibility repair for the current game UI handler. The two native engines accept one additional exact 141304-byte handler identity and brace two diagnostic logging branches. Existing fail-closed guards, game logic, rendering source, AI, audio route and official sync identities are retained. Native descriptive labels and launcher version are 1.0.1.

The human confirmed healthbars, commander minimap radar and Legion T2 radar-plane range visible. For the T1 case the world range line was visible and the minimap circle absent; the human accepted current behavior as normal. The cause of that distinction has not been proven. A condition affecting a world line is not evidence explaining a minimap absence.

Existing checks passed: 859 launcher tests, Node/Web types, 28 canonical fixtures, 52 native checks, 247 closure edges and strict ad-hoc signing. The frozen app contains 1192 file/link entries. Publication packaging does not launch or quit the app/game. No all-scout pixel parity, new FPS/energy, full multiplayer/replay synchronization, other-Mac or clean-machine acceptance is claimed.

The 1.0.0 app release was suspended after a real-game display regression. Its source tag, private draft and original artifacts remain preserved; this release uses a new 1.0.1 tag and new assets.

See [source/build details](SOURCE-STATUS.md), [stack](STACK-AND-PATCHES.md), [validation](validation.json) and [repair instructions](repair/README.md). Raw logs and user settings remain private.
