> Historical 1.0.0 preparation: app publication was suspended after a real-game widget-routing failure. Use [1.0.1](../2026-10-17-v1.0.1/README.md) for the corrected release and current qualification.

# BAR for Apple Silicon 1.0.0

This source records the 1.0.0 product integration. It combines candidate.5 maintenance and the eight reviewed source units. Product numbering is separate from gameplay/MP/other-Mac qualification.

This version combines candidate.5 macOS maintenance with the eight reviewed source units. Product version 1.0.0 and native display label BAR-1.0.0 do not change the distinct Lobby and Chobby simulation identities. The rendering path remains Recoil OpenGL -> Mesa/Zink -> Vulkan Loader -> MoltenVK -> Metal, with OpenAL/CoreAudio audio.

## Changes and checks

| Change | Why it is included | Existing component evidence |
| --- | --- | --- |
| SDL four-byte UTF-8 decoding | Keep all six payload bits of the second continuation byte, so four-byte sequences decode correctly. | 272 focused/related assertions after the fix; the new case failed14 assertions before it. |
| SDL environment failure cleanup | Check mutex creation before table construction and free the correct resources on failure. | 227 final focused/existing/cumulative assertions; one expected pre-fix failure. |
| Vulkan device-create failure pNext restoration | Restore the caller chain before forwarding a lower-driver creation error. | 16 final production cases passed; five of13 selected pre-fix cases failed. |
| Vulkan settings path-list parsing | Handle separators, one-character paths and later XDG directories while retaining first-directory priority. A previously ignored later file can now change driver/layer selection. | Three helper-mode and nine final production cases; these are separate test modes. |
| SPIRV-Cross precise negative zero | Retain typed negative-zero fma addends/accumulator seeds while preserving existing alias fixes. | Six official outputs and two existing alias outputs byte-exact; current MVK build identity f52facf7. |
| Vulkan surface-list locking | Protect shared surface lookup/lazy creation with the existing recursive Loader lock. | Five final production threading/WSI cases; no same-surface concurrent-destruction claim. |
| Vulkan direct device callback locking | Move create/destroy lock ownership together into shared callbacks for public and layer-direct entry. | 13 final production cases; each explicit success/failure condition records32 calls plus one recovery and no live devices after cleanup. |
| Vulkan debug callback-list locking | Guard the common messenger/report walk and callback dispatch; remove redundant terminator locking as one pair. | 23 final production cases; stderr off/on each64 callbacks, with0/64 output lines and valid userdata lifetime. |

Candidate5 also fixes macOS analytics hwConfig formatting, current Options guard recognition and conservative disk fallback; it removes redundant successful-path diagnostics and retired default imports while preserving user values and functional NoGS/VBO/CUS/display behavior.

Final integration evidence: 859 launcher unit tests, Node/Web type checks, 52 native loader files, 247 closure edges, strict ad-hoc app signatures, and all 1,191 app file/link/mode bindings passed. DMG and ZIP were both read back against that same app. A fresh normal-audio launch also reached a visible Lobby window and renderer-ready state with both bundled engines discovered; it was left open for the user. No game or native menu was started by the agent. See [validation](validation.json) and [source status](SOURCE-STATUS.md). These checks do not establish new graphical game/FPS/MP/endurance, other-Mac or clean-machine acceptance.

## Installation and requirements

Apple Silicon/macOS 27+; one BAR.app includes bar-lobby and Chobby. DMG and ZIP contain the same signed app. The personal cask pins the versioned DMG after public asset verification. No user installation or automatic app/game quit is part of this publication.

Ad-hoc signatures remain the supported signing state; no Developer ID or notarization is claimed. Metal3 is the default and Metal4 experimental. Product numbering is separate from runtime qualification.
