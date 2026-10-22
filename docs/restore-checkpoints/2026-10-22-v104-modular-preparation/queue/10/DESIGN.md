# 10. allocator 성장·풀·idle 예산의 추가 조정

상태: `policy-evidence-gated-no-new-tuning`

Keep recordings32/growth2MiB/available8/idle64MiB as the parent. Use existing counters and one isolated policy value per experiment if churn or memory pressure identifies a cause. Preserve Q/R quiescent reset and idle-first state machines; 64 was already tested.

## 코드화/실행 조건

- A named churn/memory-pressure condition and a single justified alternative value are recorded
- No change to writer, unsubmitted owner, GPU completion, reset/reoffer/cancel/poison contracts

## 검증

- Existing allocator lifecycle/OOM/cancel tests
- Paired throughput and peak retained-memory observation; do not infer physical reclaim from budget size

Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.

Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.
