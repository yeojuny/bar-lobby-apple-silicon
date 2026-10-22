# 11. 불필요한 render pass 종료·재시작 감소

상태: `11a-patch-ready-general-pass-merging-gated`

First test Typed frame-local discard (11a), which communicates ended data lifetime upstream. Any later driver pass merge must target one proven redundant boundary and preserve attachment/subresource, load/store, sampling, query, alias and producer-consumer requirements. Never equate E2 descriptor construction with pass merging.

## 코드화/실행 조건

- 11a readonly/model retention/DSA and actual context checks pass
- For broader merging, establish a specific repeated boundary with preserved intermediate observations
- Review fallback for every unknown attachment/query/alias case before code

## 검증

- 11a actual StreamBuffer and Typed owner CPU checks plus later real Mesa context
- Existing suspend/resolve/visibility/native cases for exact proposed merge

Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.

Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.
