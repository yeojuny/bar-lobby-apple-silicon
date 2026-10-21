# Independent applied review — drawable-size query, 2026-10-20

**Verdict: PASS for the narrow source change and frozen local candidate. Actionable findings: 0; blockers: 0.** The result supports the next separately authorized comparison. It does not establish native display-transition correctness, GPU/game acceptance or an FPS gain.

The review inspected the actual six modified source files, their saved preimages, source-extracted fixtures and completed CPU/native-build/package evidence. No product edits, new tests/builds, app/game launch/quit, signing, remote operations or shared-state changes were performed. The only new files are this report and `independent-review.json`. This is an AI-assisted independent review; the JSON contains complete reviewed pin maps and evidence SHA-256 bindings.

## Source and semantic assessment

Both lanes add only a four-integer `WindowDrawableSize` and `QueryWindowDrawableSize`. The new helper is at `build/run91-recoil-src-694e9df7/rts/System/Platform/Mac/MacSDL3EGLBridge.mm:412` and `artifacts/runtime/run94-chobby-official-20260704-20260924/source/rts/System/Platform/Mac/MacSDL3EGLBridge.mm:411`. The viewport/scissor changes are at `rts/Rendering/GlobalRendering.cpp:2323` and `:2354` in each lane. The independently regenerated unified diff exactly matches `applied-source.patch`; all six current/preimage hashes match their receipts.

For the same observed logical size and layer/fallback inputs, the helper returns the same four sizes as the unchanged full `QueryDisplayGeometry`. A valid positive layer width and height take precedence. If either is missing/nonpositive, both dimensions use the existing `NativeCocoaDrawableScale` policy. The clamping and integer truncation are the same, including fractional values. Explicit `std::max<double>` is equivalent to the old inferred-double call. `SDL_GetWindowSizeInPixels` is safely absent from this result calculation because both branches of the full query unconditionally replace both outputs. The inspected local SDL Cocoa implementation merely reads `windata.viewport.size` in that getter; it does not refresh the layer.

`GetNSWindow`, `CocoaBackingScale`, `CurrentLayerDrawableSize`, `NativeCocoaDrawableScale` and `UpdateLayerDrawableSize` are unchanged. The helper obtains the existing NSWindow through SDL properties and reads the current content-view CAMetalLayer size on each call. Nil NSWindow/content view/layer and a non-Metal layer keep the existing fallback behavior. The null SDL window returns zeros, consistent with the four untouched default fields of the old full query. No ownership, retention, thread dispatch, cached value, invalidation, setting, global state or layer mutation was introduced.

The common valid-layer path avoids display enumeration, names, work area, safe area, SDL display scale and Cocoa backing-scale queries. Fallback under `native`/`retina` can still query Cocoa scale through the existing helper. This distinction matters: the change removes unnecessary full geometry work, not every possible screen access.

Only the default-framebuffer viewport/scissor call sites switch queries. Axis-specific positive-size guards, signed coordinate rounding, extent rounding, nil-window behavior, platform guards and nonzero draw-FBO early returns remain unchanged. The full `QueryDisplayGeometry`, initial display selection, display matching, safe-bounds calculation and complete `UpdateViewPortGeometry` are unchanged. Therefore the iMac/no-notch, actual notch inset, target-display selection and logical safe-area corrections have not been replaced or bypassed in their placement/geometry call sites. No Metal3/Metal4 selection branch was added.

## Existing CPU evidence and coverage

Each lane has 102 passing assertions (the existing 53 plus 49 added), compile/run exits 0, an empty compile log and no sanitizer diagnostics in the recorded stderr. Compilation used `-Wall -Wextra -Werror -fsanitize=address,undefined`; leak detection was disabled. Both fixture hashes match their receipts. Fourteen source bindings per lane were independently compared, including the full query, new helper, real environment-scale parser, actual viewport/scissor and rounding bodies, structs, display helpers and the explicitly limited viewport-geometry prefix.

The added evidence covers full-query/helper four-size equivalence for positive/fractional/incomplete layers, explicit 1/2/1.25 scales, native/retina and invalid values, null/missing windows, zero dimensions, changing size/display fixture fields and independent axis scales. It also exercises the actual viewport/scissor methods for coordinate rounding, fractional fallback and FBO/nil-window bypass. The retained assertions cover target-display parsing, iMac and notch safe areas, stale screen association, safe-window handling, straddling geometry and live inset changes.

The fixture does **not** execute actual SDL properties, Cocoa views or CAMetalLayer access: `GetNSWindow`, `CurrentLayerDrawableSize`, `CocoaBackingScale`, screen/window classes, SDL and GL are doubles. Cocoa scale is constant 2 in the fixture. `UpdateViewPortGeometry` is only its single-screen prefix. Tests named resize/display-move/fullscreen alter fixture fields; they do not exercise a native Space transition. `displayQueries` counts five SDL display-query doubles, so the assertion named `offscreen-no-size-query` does not itself count window/layer-size reads; the production early return supplies the static proof for that bypass. No new test is required to manufacture a stronger claim for this scoped change.

## Build and artifact binding

| Check | Readback |
| --- | --- |
| Current/preimage source | 6 / 6 match; exact patch |
| Protected pins | 74 / 74 match |
| CMakeCache/build.ninja | 4 / 4 match |
| Native input manifests | Lobby 1,271; Chobby 1,265, all current hashes match |
| Incremental builds | 6.309 s / 10.269 s, exits 0 |
| Build actions | Bridge object + GlobalRendering object + engine link per lane |
| Raw current engines and prior backups | Both lanes match recorded hashes |
| Parent/candidate app | 1,194 entries each; both independently rehashed and exact |
| Dependency closure | 211 recorded edges; non-system targets exist inside candidate |
| Launcher source | HEAD `6a3b298c236cd10eff8fd7ce27d15cdb589f650f`, index `073483d1f4a62c9cda7006b467f60da926f889d1c8f126dc0016e3a23b761c87`, normal short status 488 lines exact |

The reviewed build script pins inputs before the build and asserts unchanged hashes afterward. Logs contain only the two expected object builds followed by linking; existing warnings are outside the edited statements (bridge dangling-else, legacy C++ literal/operator and duplicate-link warnings). This is not a warning-free build claim. Recorded version-only outputs remain `2026.09.01-24-g01efdf4 master (BAR-1.0.3)` and `2026.07.04 (BAR-1.0.3)` with the corresponding official sync versions.

The candidate is `artifacts/runtime/v104-drawable-size-candidate-20261020/BAR.app`; its parent is `artifacts/runtime/v104-c-reg-candidate-20261020/BAR.app`. Exactly four inventory entries differ: two engine executables, `Contents/MacOS/BAR` and `Contents/_CodeSignature/CodeResources`. Direct Mach-O readback confirms the launcher's 32 changed bytes are entirely inside the unchanged code-signature span; its length (33,920 bytes) and executable text match. Both engines' packaged `__text` hashes match their respective raw builds and receipts, and their library loads/rpaths exactly match the parent. The unchanged dependency inventories plus retained engine dependency contract support the recorded closure. All translation-stack and launcher-code inventory entries are unchanged.

The existing fail-fast packaging script performs deep/strict signature verification before writing the final receipt, which records success. That completed verification is accepted without rerunning codesign; the reviewer independently bound its current artifact through the full inventory and Mach-O checks. The two prior raw engine backups remain exact.

## Limits and disposition

The helper still reads logical window and layer dimensions separately, just as the old path did. It introduces no atomic snapshot and proves no new synchronization guarantee. Native resize/Space timing, event delivery, real Retina scale discovery and Cocoa thread safety remain outside this CPU review. Native source-input manifests are not a full reproducible-build attestation of the SDK/toolchain/environment. This review does not requalify earlier cumulative candidate changes.

**Proceed to the separately authorized same-condition runtime comparison if directed.** No corrective product edit is requested. Preserve the candidate and prior raw backups; do not describe this result as risk-free, a proven FPS improvement, full native fullscreen/iMac acceptance or release approval. The candidate intentionally retains version metadata 1.0.3 and has not been published or installed by this review.
