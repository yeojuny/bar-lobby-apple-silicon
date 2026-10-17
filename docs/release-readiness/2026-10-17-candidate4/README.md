# Candidate.4 validation scope

This prerelease preserves the frozen 0.17.0-candidate.4 app (inventory SHA256 `6664183b322ac96783bfeac8f1b36fc6f2d7a8414c47de479cb9b3cacb27ce16`, ASAR `252888bdde37ec812b97cc35f3bf8ee8f82d3309a930e84d2cc08d75180ddccb`). Installer generation does not rebuild the app.

Latest CPU proof comprises 859 launcher unit cases, Node/Web typechecks, existing sensor-host and Lua lifecycle/import checks. The four packaged BARb/CircuitAI libraries were actually loaded and their C entry points resolved. All 52 native payload files passed the system loader validator. The Chobby engine returned its exact 2026.07.04 sync version. Strict ad-hoc signature, frozen native payload association and both installer readbacks passed.

Human play confirmed the intermediate manual app working. It shared final Lobby and corrected AI payloads, with normal audio and advanced map shading enabled in the private profile. The final app also includes the corrected Apple-linker Chobby executable. Its link-only change preserves source and numeric compile policy, but the final executable has no new graphical run. Human confirmation is not a separately measured CircuitAI/public multiplayer/determinism/endurance result.

Earlier candidate.1 both-renderer healthbar/Settings/NoGS/CUS scenes, native/sanitizer checks and Chobby menu/helper/downloader lifecycle checks are historical supporting evidence. The final candidate changes code and native files since then; those scene results are not relabeled as final-binary evidence. The BARb JsonCpp crash, invalid LINKEDIT libraries and engine, EEXIST race, old validation autoquit and disabled private-profile settings are retained in local failure records. The private raw logs/settings are not published.

The renderer minimap defect claim was withdrawn because effective Fog of War/LOS display and timing were uncontrolled. Different-machine display behavior, full public multiplayer/cross-machine replay synchronization, CircuitAI gameplay, Region gameplay, long sessions, clean-machine installation, audio device hotplug and fresh performance/energy comparison remain unverified. Publishing makes this test candidate available; it does not imply those gates passed.

Ordinary workspace BAR.app and the installed alpha.3 remain unchanged on the development Mac. No game/benchmark/automatic termination was executed for publication. Existing public alpha.3 tag/assets and source/build rollbacks are retained.
