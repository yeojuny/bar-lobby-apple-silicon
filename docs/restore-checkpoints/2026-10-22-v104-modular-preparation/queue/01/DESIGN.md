# 1. proof/snapshot 임시 배열의 할당·복사 축소

상태: `implemented-Small-awaiting-qualified-performance`

Reuse the exact bounded-positive-reserve patch and existing correctness qualification. Do not implement another vector/SBO/cache scheme.

## 코드화/실행 조건

- Finish the already prepared forward8/reverse8 comparison without original contaminated8 pooling
- Keep R selected unless a later adoption decision names Small

## 검증

- Existing Small descriptor/texture CPU, native and package receipts; do not repeat without cause

Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.

Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.
