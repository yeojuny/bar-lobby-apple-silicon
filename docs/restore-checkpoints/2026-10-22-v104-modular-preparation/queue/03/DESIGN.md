# 3. prepared fallback 명령 목록의 vector 수집을 연결 목록으로 대체

상태: `source-capsule-prepared-prefix-evidence-gates-activation`

Prepared an exclusively owned replay head/tail chain. The existing _next belongs to replay only after completed encoding and before detached pool return. It is never concurrently owned by replay and the async pool. Restore splices prefix/suffix in O(1); no new field in every command.

## 코드화/실행 조건

- Meaningful long-prefix collection/fallback cost established
- Explicit state table owns every command from capture to adoption, cancel, reset or fallback; exactly one pool return

## 검증

- Existing recording-ownership cases: empty/single/long prefix, suffix restoration, cancellation, secondary and simultaneous use
- Delayed pool return and original command order oracle; no cycles or duplicate release

Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.

Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.
