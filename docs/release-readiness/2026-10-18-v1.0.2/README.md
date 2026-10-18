# BAR for Apple Silicon 1.0.2

This update applies the official Ultra preset, then AA Off (MSAA=0, MSAALevel=-1), Fog Diagonal Lines strength0, and the official Spring camera on first initialization. AA is also initialized before the native context through the launcher and Chobby settings. Separate one-time graphics, AA and camera markers preserve later user choices. Normal fog of war remains enabled as configured by the game.

Spring is selected through the official Options camera handler (index3/native mode2/viewspring) after widget initialization and Camera Remember restoration. The human confirmed normal Tab/minimap navigation with Spring in comparison and chose Spring as sufficient. The overhead implementation is unchanged; display/Retina/notch/safe-area/resolution code was not changed.

Use the final app-builder-output-spring package. The earlier first1.0.2 app is superseded. Final checks: Lua119 including12 camera cases, canonical28, both native builds/loader/version checks, seven packaged asset groups, strict ad-hoc signature and1192 app entries. Initial graphics-stage checks include67 focused launcher cases, Node types and4 defaults checks. The final Spring stage does not change the initial1.0.2 ASAR.

No game was launched to qualify the exact final1.0.2 app. No new GPU, iMac, FPS, full multiplayer/replay-sync or clean-machine acceptance is claimed. Earlier1.0.1 user observations remain historical. This update is published at the human's request using the scoped offline/package evidence.

See [source/build details](SOURCE-STATUS.md), [stack](STACK-AND-PATCHES.md) and [validation](validation.json). Private logs/settings are excluded. Publisher packaging does not launch, quit or install the app/game.
