# 5. primitive 변환이 없는 패스의 lookahead 순회 생략

상태: `negative-pass-proof-gated-no-code`

Attach a conservative no-conversion summary to an already recorded pass interval only if the existing capture path can produce it cheaply. Any unknown/dynamic topology, fan, restart, provoking requirement, shader write or inherited uncertainty selects the original full planner.

## 코드화/실행 조건

- Existing evidence shows meaningful negative lookahead scanning
- All commands in the exact interval are covered; first pipeline/draw alone is never proof
- Summary construction cost does not simply duplicate the skipped scan

## 검증

- Existing primitive-plan/native cases with baseline planner as oracle
- Dynamic topology, secondary/inherited state and unknown command force fallback; producer/handoff barriers unchanged

Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.

Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.
