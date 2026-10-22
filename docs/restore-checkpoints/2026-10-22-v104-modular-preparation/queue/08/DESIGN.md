# 8. 기록 간 CPU snapshot의 부분 재사용 확대

상태: `08a-and-08b-source-capsules-prepared-runtime-and-benefit-open`

08a preserves conservative resource invalidation while skipping unchanged legacy implicit payload invalidation. Separately08b derives a bounded recording-local proof for unchanged covered binding slices in a new descriptor combination; changed slices become residual. Repeated observations return to existing full capture, except rejected captures. Global snapshot identity and per-recording fresh native guards/retention/residency remain.

## 코드화/실행 조건

- 08a source/CPU/build/GPU gates are separate from partial-sharing acceptance
- Identify repeated subsets and concrete rescuable miss causes; old selected full/partial replay0 is not evidence of benefit
- Actual partial/full transition, concurrent replacement, drawable/alias revocation and native lifetime fixture after cue

## 검증

- 08a value/growth/layout/encoder/helper cases
- Broader snapshot: existing descriptor/prepared-texture lifecycle cases plus concurrent replacement and stale weak-proof rejection

Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.

Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.
