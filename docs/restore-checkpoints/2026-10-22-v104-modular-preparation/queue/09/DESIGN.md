# 9. per-binding snapshot replay 잠금 범위 축소

상태: `source-capsule-prepared-contention-gates-activation`

Acquire shared immutable entry under mutex, run unchanged live-retain callback outside, and erase on Miss only if exact entry identity still matches. Admitted allocation failure preserves the old map and current native ownership. Replacement adds allocation/refcount cost; concurrently replayed old entries can temporarily exceed the map64 bound.

## 코드화/실행 조건

- Per-binding mutex contention is established, not inferred from a nested callback
- Entry ownership and replace/delete races reviewed jointly with the group8 design
- Noncontended path cost and bounded retained memory remain acceptable

## 검증

- Existing snapshot replay fixture with deterministic replacement between lookup/retain/failure cleanup
- Stale failed entry must not erase a new entry; old owner survives callback; no dangling pointer

Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.

Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.
