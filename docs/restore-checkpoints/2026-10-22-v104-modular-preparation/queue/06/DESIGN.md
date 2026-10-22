# 6. 성공 feedback의 완료 전 예비 깨우기 축소

상태: `source-capsule-prepared-terminal-predicates-reviewed`

Suppress only success feedback pre-retirement notification. Actual child predicate is Completed||error; queue predicate is pending0||firstError. Success feedback bits alone satisfy neither. feedback.error preserves the early notification even with zero handlers; final/error/poison notifications remain.

## 코드화/실행 조건

- CPU sleeping-waiter schedules pass; validate actual native callback progress after activation
- Every terminal/error path and inline/duplicate/range/tail callback reaches a preserved notification
- Existing shutdown failures remain visible; this is not a shutdown fix without reproduction

## 검증

- Existing backend timeline/completion/recording-ownership CPU tests with deterministic sleeper-before-notify schedules
- Error-success race, missing terminal feedback and delayed completion; bounded timeout is test failure

Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.

Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.
