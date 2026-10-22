# 7. 동일 제출 그룹의 불변 signal 순서 재검사 재사용

상태: `source-capsule-prepared-immutable-proof-reviewed`

A noncopyable submit-local proof names the exact fresh strongly-held group after its successful complete check. Ended claimed children reject legal event mutation. Publication still reads current event values; direct calls and absent/mismatched proof run full validation.

## 코드화/실행 조건

- Repeated multi-signal groups established; zero/one-signal paths not burdened with new allocation
- Token cannot outlive or cross changed children/signal lists
- Concurrent external event advancement remains rejected at publication

## 검증

- Existing group signal/timeline cases: unsorted/duplicate, zero/one/multi, direct publication and retry
- Current value advances after validation; wrong-group proof falls back, legal Ended mutation is rejected. Arbitrary private-vector mutation is outside the proven invariant.

Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.

Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.
