# 12. MSAA 내부 분할의 중간 resolve 생략

상태: `pass-ownership-proof-gated-no-code`

Only for a proven repeated internal MSAA split, pre-classify fragments and the final consumer before encoder creation. Resolve exactly when required, including final termination without another draw. Unknown/memoryless/alias/visibility cases retain existing resolves. No unconditional extra Store/Load or final encoder.

## 코드화/실행 조건

- A concrete group11 split with multisampled offscreen attachments is observed
- Intermediate consumers, memoryless/private lifetime and final resolve ownership are explicit
- AA Off window setting is not proof all offscreen attachments are single-sample

## 검증

- Existing suspend-resolve and visibility recycle CPU/native cases
- No-final-draw, depth/stencil, alias/readback, memoryless and one-unbroken-pass regressions

Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.

Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.
